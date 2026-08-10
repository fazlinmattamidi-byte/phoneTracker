import 'dart:async';

import 'package:flutter/foundation.dart';

import '../anpr/matching_engine.dart';
import '../anpr/plate_types.dart';
import 'api_client.dart';
import 'auth_repository.dart';
import 'domain.dart';
import 'localization.dart';

enum AppThemeChoice {
  dark,
  light,
}

enum AppSection {
  dashboard,
  search,
  scanner,
  history,
  more,
  vehicles,
  users,
  settings,
  profile,
}

enum SearchScope {
  all,
  plate,
  customer,
  finance,
  reference,
  vehicle,
}

class VehicleImportSummary {
  const VehicleImportSummary({
    required this.imported,
    required this.updated,
    required this.skipped,
  });

  final int imported;
  final int updated;
  final int skipped;
}

class AppState extends ChangeNotifier {
  AppState();

  final AuthRepository authRepository = AuthRepository();
  late final PlateqApiClient apiClient =
      PlateqApiClient(config: PlateqApiConfig.fromEnvironment());
  final List<Vehicle> vehicles = List<Vehicle>.of(seedVehicles);
  final List<AppUser> users = List<AppUser>.of(seedUsers);
  final List<CameraDevice> cameras = List<CameraDevice>.of(seedCameras);
  final List<HistoryLog> history = List<HistoryLog>.of(seedHistory);

  AppUser? currentUser;
  AuthSession? session;
  SystemSettings settings = defaultSettings;
  AppSection section = AppSection.dashboard;
  AppLanguage language = AppLanguage.en;
  AppThemeChoice themeChoice = AppThemeChoice.dark;
  bool authReady = false;
  String? authError;

  bool get isAuthenticated => currentUser != null;
  Role get role => currentUser?.role ?? Role.superAdmin;
  bool get isAdminRole => role == Role.admin || role == Role.superAdmin;
  bool get canEdit => isAdminRole;
  bool get canManageUsers => isAdminRole;
  bool get canManageVehicles => isAdminRole;
  bool get canManageSystem => role == Role.superAdmin;
  String t(String key) => localizedText(language, key);

  int get bottomIndex {
    switch (section) {
      case AppSection.dashboard:
        return 0;
      case AppSection.search:
        return 1;
      case AppSection.scanner:
        return 2;
      case AppSection.history:
        return 3;
      case AppSection.more:
      case AppSection.vehicles:
      case AppSection.users:
      case AppSection.settings:
      case AppSection.profile:
        return 4;
    }
  }

  void loginAs(AppUser user) {
    currentUser = user;
    authError = null;
    section = AppSection.dashboard;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    final restored = await authRepository.restoreSession();
    if (restored != null) {
      final user =
          _firstWhereOrNull(users, (item) => item.id == restored.userId);
      if (user != null && user.status == 'ACTIVE') {
        currentUser = user;
        session = restored;
      } else {
        await authRepository.clearSession();
        currentUser = null;
        session = null;
      }
    }
    authReady = true;
    notifyListeners();
  }

  Future<bool> loginWithCredentials({
    required String email,
    required String password,
    required Role fallbackRole,
  }) async {
    try {
      final nextSession = await apiClient.login(
        email: email,
        password: password,
        fallbackRole: fallbackRole,
        fallbackUsers: users,
      );
      await authRepository.saveSession(nextSession);
      final user = _userForSession(nextSession);
      session = nextSession;
      loginAs(user);
      addHistoryLog(
        type: 'AUTH',
        action: 'Login: ${user.email}',
        details: 'Authenticated local demo session for ${user.role.code}',
        statusMatch: 'LOGIN',
      );
      return true;
    } on AuthException catch (error) {
      authError = error.message;
      notifyListeners();
      return false;
    } on PlateqApiException catch (error) {
      authError = error.message;
      notifyListeners();
      return false;
    }
  }

  void loginAsRole(Role role) {
    final user = users.firstWhere(
      (item) => item.role == role,
      orElse: () => users.first,
    );
    loginAs(user);
  }

  AppUser _userForSession(AuthSession nextSession) {
    final existing =
        _firstWhereOrNull(users, (item) => item.id == nextSession.userId);
    if (existing != null) return existing;
    final name = nextSession.email.contains('@')
        ? nextSession.email.split('@').first
        : nextSession.email;
    final avatar = (name.isEmpty ? 'MU' : name)
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .padRight(2, 'U')
        .substring(0, 2)
        .toUpperCase();
    final user = AppUser(
      id: nextSession.userId.isEmpty
          ? 'user-${DateTime.now().microsecondsSinceEpoch}'
          : nextSession.userId,
      name: name.isEmpty ? 'Mobile User' : name,
      email: nextSession.email,
      phone: '',
      role: nextSession.role,
      status: 'ACTIVE',
      avatar: avatar,
      lastLogin: DateTime.now().toUtc(),
      createdBy: 'backend',
    );
    users.insert(0, user);
    return user;
  }

  void logout() {
    final user = currentUser;
    if (user != null) {
      addHistoryLog(
        type: 'AUTH',
        action: 'Logout: ${user.email}',
        details: 'Ended local mobile session for ${user.role.code}',
        statusMatch: 'LOGOUT',
      );
    }
    unawaited(authRepository.clearSession());
    session = null;
    authError = null;
    currentUser = null;
    notifyListeners();
  }

  void go(AppSection nextSection) {
    if (nextSection == AppSection.users && !canManageUsers) {
      return;
    }
    section = nextSection;
    notifyListeners();
  }

  SearchResult searchVehicles(String query,
      {SearchScope scope = SearchScope.all}) {
    final cleaned = cleanPlateNumber(query);
    final lowerQuery = query.trim().toLowerCase();
    if (cleaned.isEmpty && lowerQuery.isEmpty) {
      return const SearchResult(exactMatch: null, possibleMatches: <Vehicle>[]);
    }

    final canPlateMatch =
        scope == SearchScope.all || scope == SearchScope.plate;
    final match = canPlateMatch
        ? evaluateDatabaseMatch(
            cleaned,
            1,
            vehicles,
            minConfidenceThreshold: 0,
          )
        : const MatchEvaluationResult(
            matchType: MatchType.none,
            matchedVehicle: null,
            possibleMatches: <Vehicle>[],
            confidence: 0,
            normalizedPlate: '',
            category: PlateCategory.unknownValidCandidate,
            reason: 'Search scope is not plate-based',
          );
    final exactMatch = match.matchedVehicle;

    final possibleByText = vehicles.where((vehicle) {
      return _vehicleMatchesSearchScope(vehicle, cleaned, lowerQuery, scope) &&
          vehicle.id != exactMatch?.id;
    }).toList();
    final possibleMatches = <Vehicle>[
      ...match.possibleMatches,
      for (final vehicle in possibleByText)
        if (!match.possibleMatches.any((item) => item.id == vehicle.id))
          vehicle,
    ];

    addHistoryLog(
      type: 'SEARCH',
      action: 'Manual Search: ${query.trim()}',
      plate: cleaned.isEmpty ? null : cleaned,
      details: exactMatch == null
          ? 'No exact match'
          : 'Exact match: ${exactMatch.brand} ${exactMatch.model}',
      statusMatch: exactMatch != null
          ? 'EXACT'
          : possibleMatches.isNotEmpty
              ? 'POSSIBLE'
              : match.matchType.code,
    );

    return SearchResult(
        exactMatch: exactMatch, possibleMatches: possibleMatches);
  }

  void upsertVehicle(Vehicle vehicle) {
    final index = vehicles.indexWhere((item) => item.id == vehicle.id);
    final action = index == -1 ? 'Added Vehicle' : 'Updated Vehicle';
    final nextVehicle = vehicle.copyWith(
      plate: cleanPlateNumber(vehicle.plate),
      updatedDate: DateTime.now().toUtc(),
    );
    if (index == -1) {
      vehicles.insert(0, nextVehicle);
    } else {
      vehicles[index] = nextVehicle;
    }
    addHistoryLog(
      type: 'DATABASE',
      action: '$action: ${nextVehicle.plate}',
      plate: nextVehicle.plate,
      details:
          '${nextVehicle.brand} ${nextVehicle.model} for ${nextVehicle.customerName}',
      statusMatch: nextVehicle.status.code,
    );
  }

  void removeVehicle(Vehicle vehicle) {
    vehicles.removeWhere((item) => item.id == vehicle.id);
    addHistoryLog(
      type: 'DATABASE',
      action: 'Deleted Vehicle: ${vehicle.plate}',
      plate: vehicle.plate,
      details:
          '${vehicle.brand} ${vehicle.model} removed from local repository',
      statusMatch: 'DELETED',
    );
  }

  VehicleImportSummary importVehiclesFromCsv(String csv) {
    final rows = _parseCsv(csv);
    if (rows.isEmpty) {
      addHistoryLog(
        type: 'DATABASE',
        action: 'Import Vehicles CSV',
        details: 'No CSV rows were found.',
        statusMatch: 'IMPORT_EMPTY',
      );
      return const VehicleImportSummary(imported: 0, updated: 0, skipped: 0);
    }

    final headers = rows.first.map(_normalizeCsvHeader).toList();
    var imported = 0;
    var updated = 0;
    var skipped = 0;

    for (final row in rows.skip(1)) {
      final record = <String, String>{};
      for (var index = 0; index < headers.length; index += 1) {
        record[headers[index]] = index < row.length ? row[index].trim() : '';
      }

      final plate = cleanPlateNumber(_csvValue(record, ['plate', 'plate_no']));
      final customerName = _csvValue(record, [
        'customer_name',
        'customer',
        'name',
        'customername',
      ]).trim();
      if (plate.isEmpty || customerName.isEmpty) {
        skipped += 1;
        continue;
      }

      final now = DateTime.now().toUtc();
      final requestedId = _csvValue(record, ['id', 'vehicle_id']).trim();
      final existingIndex = vehicles.indexWhere((vehicle) {
        final idMatches = requestedId.isNotEmpty && vehicle.id == requestedId;
        return idMatches || cleanPlateNumber(vehicle.plate) == plate;
      });
      final existing = existingIndex == -1 ? null : vehicles[existingIndex];
      final nextVehicle = Vehicle(
        id: existing?.id ??
            (requestedId.isNotEmpty ? requestedId : _nextGeneratedVehicleId()),
        plate: plate,
        customerName: customerName,
        customerId: _csvValue(record, [
          'customer_id',
          'customerid',
          'cust_id',
        ]).ifBlank(existing?.customerId ?? 'CUST-${plate.hashCode.abs()}'),
        phone: _csvValue(record, ['phone', 'phone_number', 'contact'])
            .ifBlank(existing?.phone ?? ''),
        brand: _csvValue(record, ['brand', 'make'])
            .ifBlank(existing?.brand ?? 'Unknown'),
        model:
            _csvValue(record, ['model']).ifBlank(existing?.model ?? 'Unknown'),
        colour: _csvValue(record, ['colour', 'color'])
            .ifBlank(existing?.colour ?? 'Unknown'),
        year: _parseInt(_csvValue(record, ['year'])) ??
            existing?.year ??
            DateTime.now().year,
        financeCompany: _csvValue(record, [
          'finance_company',
          'finance',
          'bank',
        ]).ifBlank(existing?.financeCompany ?? 'Unassigned'),
        outstandingAmount: _parseAmount(_csvValue(record, [
              'outstanding_amount',
              'outstanding',
              'amount',
            ])) ??
            existing?.outstandingAmount ??
            0,
        reference: _csvValue(record, [
          'reference',
          'case_reference',
          'case_ref',
        ]).ifBlank(existing?.reference ?? 'REF-$plate'),
        priority: _parsePriority(_csvValue(record, ['priority'])) ??
            existing?.priority ??
            VehiclePriority.medium,
        status: _parseStatus(_csvValue(record, ['status'])) ??
            existing?.status ??
            VehicleStatus.active,
        remark: _csvValue(record, ['remark', 'remarks', 'note', 'notes'])
            .ifBlank(existing?.remark ?? ''),
        createdDate: _parseDate(_csvValue(record, [
              'created_date',
              'created',
              'createddate',
            ])) ??
            existing?.createdDate ??
            now,
        updatedDate: now,
      );

      if (existingIndex == -1) {
        vehicles.insert(0, nextVehicle);
        imported += 1;
      } else {
        vehicles[existingIndex] = nextVehicle;
        updated += 1;
      }
    }

    addHistoryLog(
      type: 'DATABASE',
      action: 'Import Vehicles CSV',
      details:
          'Imported $imported, updated $updated, skipped $skipped vehicle rows.',
      statusMatch: 'IMPORT',
    );
    return VehicleImportSummary(
      imported: imported,
      updated: updated,
      skipped: skipped,
    );
  }

  void upsertUser(AppUser user) {
    final index = users.indexWhere((item) => item.id == user.id);
    final action = index == -1 ? 'Added User' : 'Updated User';
    if (index == -1) {
      users.insert(0, user);
    } else {
      users[index] = user;
      if (currentUser?.id == user.id) currentUser = user;
    }
    addHistoryLog(
      type: 'USER',
      action: '$action: ${user.name}',
      details: '${user.email} / ${user.role.code} / ${user.status}',
      statusMatch: user.status,
    );
  }

  void setUserStatus(AppUser user, String status) {
    upsertUser(user.copyWith(status: status));
  }

  void removeUser(AppUser user) {
    if (currentUser?.id == user.id) return;
    users.removeWhere((item) => item.id == user.id);
    addHistoryLog(
      type: 'USER',
      action: 'Deleted User: ${user.name}',
      details: '${user.email} removed from local user list',
      statusMatch: 'DELETED',
    );
  }

  void resetUserPassword(AppUser user) {
    addHistoryLog(
      type: 'USER',
      action: 'Password Reset: ${user.name}',
      details: 'Demo reset action recorded for ${user.email}',
      statusMatch: 'RESET',
    );
  }

  void updateCurrentUser({
    required String name,
    required String email,
    required String phone,
  }) {
    final user = currentUser;
    if (user == null) return;
    upsertUser(user.copyWith(name: name, email: email, phone: phone));
  }

  void addHistoryLog({
    required String type,
    required String action,
    required String details,
    String? plate,
    String? statusMatch,
    String? cameraId,
    String? cameraName,
    String? note,
  }) {
    history.insert(
      0,
      HistoryLog(
        id: 'hist-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        action: action,
        plate: plate,
        details: details,
        userRole: role,
        timestamp: DateTime.now().toUtc(),
        statusMatch: statusMatch,
        cameraId: cameraId,
        cameraName: cameraName,
        note: note,
        actorId: currentUser?.id,
        actorName: currentUser?.name,
      ),
    );
    notifyListeners();
  }

  void updateSettings(SystemSettings nextSettings) {
    settings = nextSettings;
    notifyListeners();
  }

  String _nextGeneratedVehicleId() {
    var next = vehicles.length + 1;
    while (vehicles.any(
        (vehicle) => vehicle.id == 'veh-${next.toString().padLeft(3, '0')}')) {
      next += 1;
    }
    return 'veh-${next.toString().padLeft(3, '0')}';
  }

  void setLanguage(AppLanguage nextLanguage) {
    language = nextLanguage;
    notifyListeners();
  }

  void toggleLanguage() {
    language = language == AppLanguage.en ? AppLanguage.bm : AppLanguage.en;
    notifyListeners();
  }

  void setThemeChoice(AppThemeChoice nextTheme) {
    themeChoice = nextTheme;
    notifyListeners();
  }

  void toggleTheme() {
    themeChoice = themeChoice == AppThemeChoice.dark
        ? AppThemeChoice.light
        : AppThemeChoice.dark;
    notifyListeners();
  }
}

bool _vehicleMatchesSearchScope(
    Vehicle vehicle, String cleaned, String lowerQuery, SearchScope scope) {
  final plate = cleanPlateNumber(vehicle.plate);
  final haystacks = switch (scope) {
    SearchScope.plate => <String>[plate],
    SearchScope.customer => <String>[
        vehicle.customerName,
        vehicle.customerId,
        vehicle.phone
      ],
    SearchScope.finance => <String>[vehicle.financeCompany],
    SearchScope.reference => <String>[vehicle.reference],
    SearchScope.vehicle => <String>[
        vehicle.brand,
        vehicle.model,
        vehicle.colour,
        '${vehicle.year}'
      ],
    SearchScope.all => <String>[
        plate,
        vehicle.customerName,
        vehicle.customerId,
        vehicle.phone,
        vehicle.financeCompany,
        vehicle.reference,
        vehicle.brand,
        vehicle.model,
        vehicle.colour,
        '${vehicle.year}',
      ],
  };

  return haystacks.any((value) {
    final normalized = cleanPlateNumber(value);
    final lower = value.toLowerCase();
    return (cleaned.isNotEmpty && normalized.contains(cleaned)) ||
        (lowerQuery.isNotEmpty && lower.contains(lowerQuery));
  });
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

List<List<String>> _parseCsv(String csv) {
  final rows = <List<String>>[];
  final currentRow = <String>[];
  final currentValue = StringBuffer();
  var inQuotes = false;

  for (var index = 0; index < csv.length; index += 1) {
    final char = csv[index];
    if (char == '"') {
      final nextIsQuote = index + 1 < csv.length && csv[index + 1] == '"';
      if (inQuotes && nextIsQuote) {
        currentValue.write('"');
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char == ',' && !inQuotes) {
      currentRow.add(currentValue.toString());
      currentValue.clear();
      continue;
    }
    if ((char == '\n' || char == '\r') && !inQuotes) {
      if (char == '\r' && index + 1 < csv.length && csv[index + 1] == '\n') {
        index += 1;
      }
      currentRow.add(currentValue.toString());
      currentValue.clear();
      if (currentRow.any((value) => value.trim().isNotEmpty)) {
        rows.add(List<String>.of(currentRow));
      }
      currentRow.clear();
      continue;
    }
    currentValue.write(char);
  }

  currentRow.add(currentValue.toString());
  if (currentRow.any((value) => value.trim().isNotEmpty)) {
    rows.add(currentRow);
  }
  return rows;
}

String _normalizeCsvHeader(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

String _csvValue(Map<String, String> record, List<String> keys) {
  for (final key in keys) {
    final normalized = _normalizeCsvHeader(key);
    final value = record[normalized];
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

int? _parseInt(String value) {
  return int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), ''));
}

double? _parseAmount(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

DateTime? _parseDate(String value) {
  if (value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim())?.toUtc();
}

VehiclePriority? _parsePriority(String value) {
  final normalized = _normalizeCsvHeader(value).toUpperCase();
  for (final priority in VehiclePriority.values) {
    if (priority.code == normalized) return priority;
  }
  return null;
}

VehicleStatus? _parseStatus(String value) {
  final normalized = _normalizeCsvHeader(value).toUpperCase();
  for (final status in VehicleStatus.values) {
    if (status.code == normalized) return status;
  }
  return null;
}

extension on String {
  String ifBlank(String fallback) => trim().isEmpty ? fallback : trim();
}
