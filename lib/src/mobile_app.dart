import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'anpr/native_anpr_bridge.dart';
import 'core/app_state.dart';
import 'core/domain.dart';
import 'core/localization.dart';
import 'core/native_share.dart';

class PlateQMobileApp extends StatefulWidget {
  const PlateQMobileApp({super.key});

  @override
  State<PlateQMobileApp> createState() => _PlateQMobileAppState();
}

class _PlateQMobileAppState extends State<PlateQMobileApp> {
  late final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    unawaited(_state.restoreSession());
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: _state,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'TRACK',
            theme: _buildTheme(_state.themeChoice == AppThemeChoice.light
                ? Brightness.light
                : Brightness.dark),
            home: !_state.authReady
                ? const StartupScreen()
                : _state.isAuthenticated
                    ? const PlateQShell()
                    : const LoginScreen(),
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  const cyan = Color(0xFF06B6D4);
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF020617) : const Color(0xFFEFF6FF),
    colorScheme: ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: brightness,
      surface: isDark ? const Color(0xFF0F172A) : Colors.white,
      primary: cyan,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF020617),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF020617),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: cyan),
      ),
    ),
  );
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState notifier,
    required super.child,
  }) : super(notifier: notifier);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.notifier!;
  }
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Role _selectedRole = Role.superAdmin;
  late final TextEditingController _email =
      TextEditingController(text: 'superadmin@track.my');
  late final TextEditingController _password =
      TextEditingController(text: 'password');
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _selectRole(Role role) {
    final state = AppScope.of(context);
    final user = state.users.firstWhere((item) => item.role == role,
        orElse: () => state.users.first);
    setState(() {
      _selectedRole = role;
      _email.text = user.email;
    });
  }

  Future<void> _submit() async {
    final state = AppScope.of(context);
    setState(() => _busy = true);
    final success = await state.loginWithCredentials(
      email: _email.text,
      password: _password.text,
      fallbackRole: _selectedRole,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success && state.authError != null) {
      _showSnack(context, state.authError!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final roles = <Role>[Role.user, Role.admin, Role.superAdmin];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF22D3EE)),
                      ),
                      child: Image.asset('public/logo.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'TRACK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.t('appSubName'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          state.t('demoRole'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF22D3EE),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (final role in roles)
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: ChoiceChip(
                                    selected: _selectedRole == role,
                                    label: Text(_roleLabel(state, role),
                                        overflow: TextOverflow.ellipsis),
                                    onSelected: (_) => _selectRole(role),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(state.t('loginTitle'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(
                          state.t('loginSubtitle'),
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (state.authError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            state.authError!,
                            style: const TextStyle(
                                color: Color(0xFFF87171),
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: Icon(_busy
                              ? Icons.hourglass_empty
                              : Icons.arrow_forward),
                          label: Text(state.t('loginButton')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlateQShell extends StatelessWidget {
  const PlateQShell({super.key});

  void _selectNavigationIndex(AppState state, int index) {
    switch (index) {
      case 0:
        state.go(AppSection.dashboard);
        break;
      case 1:
        state.go(AppSection.search);
        break;
      case 2:
        state.go(AppSection.scanner);
        break;
      case 3:
        state.go(AppSection.history);
        break;
      case 4:
        state.go(AppSection.more);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final compactHeader = size.width < 430;
    final wideLayout = size.width >= 900;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: Image.asset('public/logo.png', fit: BoxFit.cover),
            ),
            if (!compactHeader) ...[
              const SizedBox(width: 10),
              const Text('TRACK',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0)),
            ],
          ],
        ),
        actions: [
          if (compactHeader)
            IconButton(
              tooltip: '${state.t('languageSetting')}: ${state.language.code}',
              onPressed: state.toggleLanguage,
              icon: const Icon(Icons.language),
            )
          else
            TextButton.icon(
              onPressed: state.toggleLanguage,
              icon: const Icon(Icons.language, size: 18),
              label: Text(state.language.code),
            ),
          IconButton(
            tooltip: state.t('themeSetting'),
            onPressed: state.toggleTheme,
            icon: Icon(state.themeChoice == AppThemeChoice.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
          ),
          if (!compactHeader) _RolePill(role: state.role),
          IconButton(
            tooltip: state.t('navProfile'),
            onPressed: () => state.go(AppSection.profile),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: state.t('navLogout'),
            onPressed: state.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: wideLayout
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      selectedIndex: state.bottomIndex,
                      onDestinationSelected: (index) =>
                          _selectNavigationIndex(state, index),
                      labelType: NavigationRailLabelType.all,
                      minWidth: 82,
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.dashboard_outlined),
                          selectedIcon: const Icon(Icons.dashboard),
                          label: Text(state.t('navDashboard')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.search),
                          label: Text(state.t('navSearch')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.camera_alt_outlined),
                          selectedIcon: const Icon(Icons.camera_alt),
                          label: Text(state.t('navScanner')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.history),
                          label: Text(state.t('navHistory')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.more_horiz),
                          label: Text(state.t('moreMenu')),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 14),
                    Expanded(child: _SectionBody(section: state.section)),
                  ],
                )
              : _SectionBody(section: state.section),
        ),
      ),
      bottomNavigationBar: wideLayout
          ? null
          : NavigationBar(
              selectedIndex: state.bottomIndex,
              onDestinationSelected: (index) =>
                  _selectNavigationIndex(state, index),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: state.t('navDashboard'),
                ),
                NavigationDestination(
                    icon: const Icon(Icons.search),
                    label: state.t('navSearch')),
                NavigationDestination(
                  icon: const Icon(Icons.camera_alt_outlined),
                  selectedIcon: const Icon(Icons.camera_alt),
                  label: state.t('navScanner'),
                ),
                NavigationDestination(
                    icon: const Icon(Icons.history),
                    label: state.t('navHistory')),
                NavigationDestination(
                    icon: const Icon(Icons.more_horiz),
                    label: state.t('moreMenu')),
              ],
            ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case AppSection.dashboard:
        return const DashboardScreen();
      case AppSection.search:
        return const SearchScreen();
      case AppSection.scanner:
        return const ScannerScreen();
      case AppSection.history:
        return const HistoryScreen();
      case AppSection.more:
        return const MoreScreen(showHeader: true);
      case AppSection.vehicles:
        return const VehiclesScreen();
      case AppSection.users:
        return const UsersScreen();
      case AppSection.settings:
        return const SettingsScreen();
      case AppSection.profile:
        return const ProfileScreen();
    }
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final activeCases = state.vehicles
        .where((vehicle) => vehicle.status == VehicleStatus.active)
        .length;
    final detections =
        state.history.where((log) => log.type == 'DETECTION').length;
    final searches = state.history.where((log) => log.type == 'SEARCH').length;
    final recent = state.history.take(5).toList();

    return ListView(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            StatTile(
                label: state.t('totalVehicles'),
                value: '${state.vehicles.length}',
                icon: Icons.directions_car),
            StatTile(
                label: state.t('activeCases'),
                value: '$activeCases',
                icon: Icons.shield_outlined),
            StatTile(
                label: state.t('todayScans'),
                value: '$detections',
                icon: Icons.camera_alt_outlined),
            StatTile(
                label: state.t('manualSearches'),
                value: '$searches',
                icon: Icons.search),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.camera_alt_outlined, title: state.t('quickNav')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: Text(state.t('openScannerBtn')),
                    onPressed: () => state.go(AppSection.scanner),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.search, size: 18),
                    label: Text(state.t('searchPlateBtn')),
                    onPressed: () => state.go(AppSection.search),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.directions_car, size: 18),
                    label: Text(state.t('vehiclesRepoBtn')),
                    onPressed: () => state.go(AppSection.vehicles),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: Text(state.t('auditHistoryBtn')),
                    onPressed: () => state.go(AppSection.history),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.history, title: state.t('recentMatchesTitle')),
              const SizedBox(height: 8),
              for (final log in recent) HistoryListTile(log: log),
            ],
          ),
        ),
      ],
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  SearchResult? _result;
  SearchScope _scope = SearchScope.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final result =
        AppScope.of(context).searchVehicles(_query.text, scope: _scope);
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(icon: Icons.search, title: state.t('searchTitle')),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    InputDecoration(labelText: state.t('searchPlaceholder')),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in SearchScope.values)
                    ChoiceChip(
                      selected: _scope == scope,
                      label: Text(_searchScopeLabel(state, scope)),
                      onSelected: (_) => setState(() => _scope = scope),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: Text(state.t('searchBtn')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_result != null) SearchResultPanel(result: _result!),
      ],
    );
  }
}

class SearchResultPanel extends StatelessWidget {
  const SearchResultPanel({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (result.exactMatch == null && result.possibleMatches.isEmpty) {
      return SectionCard(
        child: ListTile(
          leading:
              const Icon(Icons.check_circle_outline, color: Color(0xFF22D3EE)),
          title: Text(state.t('noMatchTitle')),
          subtitle: Text(state.t('noMatchDesc')),
        ),
      );
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.exactMatch != null)
            VehicleMatchCard(vehicle: result.exactMatch!, tone: 'EXACT'),
          for (final vehicle in result.possibleMatches)
            VehicleMatchCard(vehicle: vehicle, tone: 'POSSIBLE'),
        ],
      ),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final NativeAnprBridge _bridge = NativeAnprBridge();
  StreamSubscription<AnprEvent>? _subscription;
  List<NativeCameraDevice> _nativeCameras = const [];
  List<AnprTrack> _tracks = const [];
  AnprAlert? _latestAlert;
  String? _selectedCameraId;
  String _runtimeState = 'UNINITIALIZED';
  String _deviceTier = 'AUTO';
  String _detectorProvider = 'NONE';
  String _ocrProvider = 'NONE';
  String _environmentProvider = 'NONE';
  String _plateQualityProvider = 'NONE';
  String _environmentLabel = 'GOOD_CONDITION';
  String _plateQualityClass = 'UNKNOWN';
  String _status = 'Native scanner bridge idle';
  double _cameraFps = 0;
  double _detectorFps = 0;
  double _environmentConfidence = 0;
  double _plateQualityScore = 0;
  int _ocrQueueDepth = 0;
  bool _scanning = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subscription =
        _bridge.events.listen(_handleEvent, onError: _handleBridgeError);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose().ignore();
    super.dispose();
  }

  void _handleEvent(AnprEvent event) {
    if (!mounted) return;
    AnprAlert? alertToLog;
    setState(() {
      if (event is RuntimeAnprEvent) {
        _runtimeState = event.runtimeState;
        _deviceTier = event.deviceTier;
        _detectorProvider = event.detectorProvider;
        _ocrProvider = event.ocrProvider;
        _environmentProvider = event.environmentProvider;
        _plateQualityProvider = event.plateQualityProvider;
        _environmentLabel = event.environmentLabel;
        _environmentConfidence = event.environmentConfidence;
        _plateQualityClass = event.plateQualityClass;
        _plateQualityScore = event.plateQualityScore;
        _cameraFps = event.cameraFps;
        _detectorFps = event.detectorFps;
        _ocrQueueDepth = event.ocrQueueDepth;
        _status = event.runtimeState;
      } else if (event is TrackUpdateAnprEvent) {
        _tracks = event.tracks;
      } else if (event is MatchAlertAnprEvent) {
        _latestAlert = event.alert;
        alertToLog = event.alert;
      } else if (event is ErrorAnprEvent) {
        _status = event.message;
      }
    });
    final alert = alertToLog;
    if (alert != null) {
      final state = AppScope.of(context);
      state.addHistoryLog(
        type: 'DETECTION',
        action: 'Live Scan: ${alert.plate}',
        plate: alert.plate,
        details: '${alert.matchType} match from ${alert.cameraLabel}',
        statusMatch: alert.matchType,
        cameraName: alert.cameraLabel,
      );
    }
  }

  void _handleBridgeError(Object error) {
    if (!mounted) return;
    setState(() {
      _status = _friendlyBridgeError(error);
      _scanning = false;
    });
  }

  Future<void> _initialize() async {
    setState(() => _busy = true);
    try {
      final status = await _bridge.initialize();
      final cameras = await _bridge.listCameras();
      setState(() {
        _runtimeState = status.runtimeState;
        _deviceTier = status.deviceTier;
        _detectorProvider = status.detectorProvider;
        _ocrProvider = status.ocrProvider;
        _environmentProvider = status.environmentProvider;
        _plateQualityProvider = status.plateQualityProvider;
        _nativeCameras = cameras;
        _selectedCameraId =
            _firstWhereOrNull(cameras, (camera) => camera.isDefault)?.id ??
                (cameras.isNotEmpty ? cameras.first.id : null);
        _status = 'Native runtime ${status.runtimeState}';
      });
    } catch (error) {
      setState(() => _status = _friendlyBridgeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final state = AppScope.of(context);
    final cameraId = _selectedCameraId ?? 'native-back';
    setState(() {
      _busy = true;
      _status = 'Starting native scanner';
    });
    try {
      await _bridge.startScanning(
        cameraId: cameraId,
        detectionThreshold: state.settings.detectionConfidence,
        recognitionThreshold: state.settings.ocrConfidence,
        consensusVotes: state.settings.consensusVotes,
        maxTracks: state.settings.maxTracks,
        maxOcrConcurrency: state.settings.maxOcrConcurrency,
        enableSpecialSeries: state.settings.enableSpecialSeries,
      );
      setState(() {
        _scanning = true;
        _runtimeState = 'SCANNING';
        _status = 'Scanning selected camera';
      });
    } catch (error) {
      setState(() {
        _status = _friendlyBridgeError(error);
        _scanning = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _bridge.stopScanning();
    } catch (_) {
      // Stop remains idempotent in the UI; native code owns cleanup details.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _scanning = false;
          _runtimeState = 'READY';
          _status = 'Scanner stopped';
          _tracks = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final selectedCamera = _firstWhereOrNull(
        _nativeCameras, (camera) => camera.id == _selectedCameraId);
    final cameraLabel = selectedCamera?.label ?? 'Rear Camera';

    return ListView(
      children: [
        SectionTitle(
            icon: Icons.camera_alt_outlined,
            title: state.t('liveScannerTitle')),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : (_scanning ? _stop : _start),
                icon: Icon(_scanning ? Icons.stop : Icons.play_arrow),
                label: Text(
                    _scanning ? 'Stop Scanning' : state.t('openScannerBtn')),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Initialize native runtime',
              onPressed: _busy ? null : _initialize,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_nativeCameras.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _selectedCameraId,
            decoration: const InputDecoration(labelText: 'Select Camera'),
            items: [
              for (final camera in _nativeCameras)
                DropdownMenuItem(
                    value: camera.id,
                    child: Text('${camera.label} (${camera.facing})')),
            ],
            onChanged: _scanning
                ? null
                : (value) {
                    setState(() => _selectedCameraId = value);
                    if (value != null) _bridge.selectCamera(value).ignore();
                  },
          ),
        const SizedBox(height: 10),
        CameraSurface(
            scanning: _scanning, tracks: _tracks, alert: _latestAlert),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(icon: Icons.memory, title: _status),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MetricChip(
                      label: state.t('cameraPreview'), value: cameraLabel),
                  MetricChip(label: 'Runtime', value: _runtimeState),
                  MetricChip(label: 'Tier', value: _deviceTier),
                  MetricChip(label: 'Detector', value: _detectorProvider),
                  MetricChip(label: 'OCR', value: _ocrProvider),
                  MetricChip(
                      label: state.t('cameraFps'),
                      value: _cameraFps.toStringAsFixed(1)),
                  MetricChip(
                      label: state.t('detectionFps'),
                      value: _detectorFps.toStringAsFixed(1)),
                  MetricChip(
                      label: 'Environment',
                      value:
                          '$_environmentLabel ${(_environmentConfidence * 100).round()}%'),
                  MetricChip(
                      label: 'Quality',
                      value:
                          '$_plateQualityClass ${(_plateQualityScore * 100).round()}%'),
                  MetricChip(
                      label: 'Env Provider', value: _environmentProvider),
                  MetricChip(
                      label: 'Quality Provider', value: _plateQualityProvider),
                  MetricChip(label: 'OCR Queue', value: '$_ocrQueueDepth'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.list_alt, title: state.t('recentDetectionList')),
              const SizedBox(height: 8),
              if (_tracks.isEmpty)
                const Text('Waiting for native track events.',
                    style: TextStyle(color: Color(0xFF94A3B8)))
              else
                for (final track in _tracks)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.center_focus_strong,
                        color: Color(0xFF22D3EE)),
                    title:
                        Text(track.plate.isEmpty ? track.trackId : track.plate),
                    subtitle: Text(
                        '${track.pipelineState} · ${track.state} · ${track.qualityClass}'),
                    trailing: Text('${(track.confidence * 100).round()}%'),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class CameraSurface extends StatelessWidget {
  const CameraSurface({
    super.key,
    required this.scanning,
    required this.tracks,
    required this.alert,
  });

  final bool scanning;
  final List<AnprTrack> tracks;
  final AnprAlert? alert;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: const Color(0xFF020617),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (scanning)
                    const PlatformCameraPreview()
                  else
                    const CameraIdleView(),
                  for (final track in tracks)
                    Positioned(
                      left: track.bbox.x * constraints.maxWidth,
                      top: track.bbox.y * constraints.maxHeight,
                      width: track.bbox.width * constraints.maxWidth,
                      height: track.bbox.height * constraints.maxHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: _trackColor(track.matchType), width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  if (alert != null) AlertOverlay(alert: alert!),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class PlatformCameraPreview extends StatelessWidget {
  const PlatformCameraPreview({super.key});

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const AndroidView(viewType: 'plateq.anpr_camera_preview');
      case TargetPlatform.iOS:
        return const UiKitView(viewType: 'plateq.anpr_camera_preview');
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return const CameraIdleView();
    }
  }
}

class CameraIdleView extends StatelessWidget {
  const CameraIdleView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt_outlined, color: Color(0xFF22D3EE), size: 44),
          SizedBox(height: 8),
          Text('Native camera preview',
              style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Tap start scanning to open the native camera.',
              style: TextStyle(color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

class AlertOverlay extends StatelessWidget {
  const AlertOverlay({super.key, required this.alert});

  final AnprAlert alert;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(alert.plate,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 18)),
                  Text(
                      '${alert.matchType} · ${(alert.confidence * 100).round()}% · ${alert.cameraLabel}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final TextEditingController _query = TextEditingController();
  VehicleStatus? _status;
  VehiclePriority? _priority;
  int _page = 0;
  final int _pageSize = 12;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openEditor({Vehicle? vehicle}) async {
    final state = AppScope.of(context);
    final result = await showDialog<Vehicle>(
      context: context,
      builder: (_) => VehicleDraftDialog(
          vehicle: vehicle, nextId: _nextVehicleId(state.vehicles)),
    );
    if (!mounted || result == null) return;
    state.upsertVehicle(result);
    _showSnack(context, vehicle == null ? 'Vehicle added' : 'Vehicle updated');
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final confirmed = await _confirmAction(context, 'Delete ${vehicle.plate}?',
        'This removes the local demo repository entry.');
    if (!mounted || !confirmed) return;
    AppScope.of(context).removeVehicle(vehicle);
    _showSnack(context, 'Vehicle deleted');
  }

  Future<void> _exportVehicles(List<Vehicle> vehicles) async {
    final csv = _vehiclesToCsv(vehicles);
    final shared = await NativeShare.shareText(
      title: 'Export Vehicles CSV',
      fileName: 'plateq-vehicles.csv',
      mimeType: 'text/csv',
      text: csv,
    );
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: csv));
    }
    if (!mounted) return;
    AppScope.of(context).addHistoryLog(
      type: 'DATABASE',
      action: 'Export Vehicles CSV',
      details: shared
          ? '${vehicles.length} filtered vehicles shared through native sheet'
          : '${vehicles.length} filtered vehicles copied to clipboard fallback',
      statusMatch: 'EXPORT',
    );
    _showSnack(context,
        shared ? 'Vehicle CSV shared' : 'Vehicle CSV copied as fallback');
  }

  Future<void> _importVehicles() async {
    final csv = await NativeShare.pickCsv();
    if (!mounted) return;
    if (csv == null || csv.trim().isEmpty) {
      _showSnack(context, 'No CSV selected');
      return;
    }
    final summary = AppScope.of(context).importVehiclesFromCsv(csv);
    setState(() => _page = 0);
    _showSnack(
      context,
      'Imported ${summary.imported}, updated ${summary.updated}, skipped ${summary.skipped}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final filtered = state.vehicles.where((vehicle) {
      return _matchesVehicleFilter(vehicle, _query.text, _status, _priority);
    }).toList();
    final pageItems = _pagedItems(filtered, _page, _pageSize);
    return ListView(
      children: [
        SectionTitle(
            icon: Icons.directions_car, title: state.t('manageVehiclesTitle')),
        Text(state.t('manageVehiclesSub'),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: state.t('searchVehiclePlaceholder'),
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<VehicleStatus?>(
                    value: _status,
                    hint: const Text('Status'),
                    items: [
                      const DropdownMenuItem<VehicleStatus?>(
                          value: null, child: Text('All Status')),
                      for (final status in VehicleStatus.values)
                        DropdownMenuItem<VehicleStatus?>(
                            value: status, child: Text(status.code)),
                    ],
                    onChanged: (value) => setState(() {
                      _status = value;
                      _page = 0;
                    }),
                  ),
                  DropdownButton<VehiclePriority?>(
                    value: _priority,
                    hint: Text(state.t('priority')),
                    items: [
                      const DropdownMenuItem<VehiclePriority?>(
                          value: null, child: Text('All Priority')),
                      for (final priority in VehiclePriority.values)
                        DropdownMenuItem<VehiclePriority?>(
                            value: priority, child: Text(priority.code)),
                    ],
                    onChanged: (value) => setState(() {
                      _priority = value;
                      _page = 0;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed:
                        state.canManageVehicles ? () => _openEditor() : null,
                    icon: const Icon(Icons.add),
                    label: Text(state.t('addVehicle')),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.canManageVehicles ? _importVehicles : null,
                    icon: const Icon(Icons.upload_file),
                    label: Text(state.t('importCsv')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportVehicles(filtered),
                    icon: const Icon(Icons.download),
                    label: Text(state.t('exportCsv')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text('${filtered.length} / ${state.vehicles.length} vehicles',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const EmptyPanel(message: 'No vehicles match the current filters.'),
        for (final vehicle in pageItems)
          VehicleListCard(
            vehicle: vehicle,
            canEdit: state.canManageVehicles,
            onEdit: () => _openEditor(vehicle: vehicle),
            onDelete: () => _deleteVehicle(vehicle),
          ),
        if (filtered.isNotEmpty)
          PagedListControls(
            totalItems: filtered.length,
            page: _page,
            pageSize: _pageSize,
            onPageChanged: (page) => setState(() => _page = page),
          ),
      ],
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _query = TextEditingController();
  String? _type;
  bool _newestFirst = true;
  int _page = 0;
  final int _pageSize = 20;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _exportHistory(List<HistoryLog> history) async {
    final csv = _historyToCsv(history);
    final shared = await NativeShare.shareText(
      title: 'Export Audit History CSV',
      fileName: 'plateq-history.csv',
      mimeType: 'text/csv',
      text: csv,
    );
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: csv));
    }
    if (!mounted) return;
    _showSnack(context,
        shared ? 'History CSV shared' : 'History CSV copied as fallback');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final history = state.history
        .where((log) => _matchesHistoryFilter(log, _query.text, _type))
        .toList()
      ..sort((a, b) => _newestFirst
          ? b.timestamp.compareTo(a.timestamp)
          : a.timestamp.compareTo(b.timestamp));
    final pageItems = _pagedItems(history, _page, _pageSize);
    final types = state.history.map((log) => log.type).toSet().toList()..sort();
    return ListView(
      children: [
        SectionTitle(icon: Icons.history, title: state.t('historyTitle')),
        Text(state.t('historySub'),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Filter plate, actor, action, details...',
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String?>(
                    value: _type,
                    hint: const Text('Type'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All Types')),
                      for (final type in types)
                        DropdownMenuItem<String?>(
                            value: type, child: Text(type)),
                    ],
                    onChanged: (value) => setState(() {
                      _type = value;
                      _page = 0;
                    }),
                  ),
                  FilterChip(
                    selected: _newestFirst,
                    avatar: const Icon(Icons.south, size: 18),
                    label: const Text('Newest First'),
                    onSelected: (value) => setState(() {
                      _newestFirst = value;
                      _page = 0;
                    }),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportHistory(history),
                    icon: const Icon(Icons.download),
                    label: Text(state.t('exportCsv')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text('${history.length} audit records',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const EmptyPanel(
              message: 'No audit records match the current filters.'),
        for (final log in pageItems) HistoryListTile(log: log),
        if (history.isNotEmpty)
          PagedListControls(
            totalItems: history.length,
            page: _page,
            pageSize: _pageSize,
            onPageChanged: (page) => setState(() => _page = page),
          ),
      ],
    );
  }
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _query = TextEditingController();
  Role? _role;
  String? _status;
  int _page = 0;
  final int _pageSize = 10;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openEditor({AppUser? user}) async {
    final state = AppScope.of(context);
    final result = await showDialog<AppUser>(
      context: context,
      builder: (_) => UserDraftDialog(
          user: user,
          nextId: _nextUserId(state.users),
          createdBy: state.currentUser?.id),
    );
    if (!mounted || result == null) return;
    state.upsertUser(result);
    _showSnack(context, user == null ? 'User added' : 'User updated');
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await _confirmAction(context, 'Delete ${user.name}?',
        'This removes the local demo user entry.');
    if (!mounted || !confirmed) return;
    AppScope.of(context).removeUser(user);
    _showSnack(context, 'User deleted');
  }

  void _toggleUser(AppUser user) {
    final nextStatus = user.status == 'ACTIVE' ? 'DISABLED' : 'ACTIVE';
    AppScope.of(context).setUserStatus(user, nextStatus);
    _showSnack(context, 'User ${nextStatus.toLowerCase()}');
  }

  void _resetPassword(AppUser user) {
    AppScope.of(context).resetUserPassword(user);
    _showSnack(context, 'Password reset recorded');
  }

  void _viewHistory(AppUser user) {
    final state = AppScope.of(context);
    final logs = state.history
        .where((log) =>
            log.actorId == user.id ||
            log.actorName == user.name ||
            log.userRole == user.role)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    showDialog<void>(
      context: context,
      builder: (_) => UserHistoryDialog(user: user, logs: logs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.canManageUsers) {
      return const PermissionPanel();
    }
    final filtered = state.users
        .where((user) => _matchesUserFilter(user, _query.text, _role, _status))
        .toList();
    final pageItems = _pagedItems(filtered, _page, _pageSize);
    final statuses = state.users.map((user) => user.status).toSet().toList()
      ..sort();
    return ListView(
      children: [
        SectionTitle(
            icon: Icons.people_alt_outlined,
            title: state.t('manageUsersTitle')),
        Text(state.t('manageUsersSub'),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search name, email, phone...',
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<Role?>(
                    value: _role,
                    hint: Text(state.t('roleHeader')),
                    items: [
                      const DropdownMenuItem<Role?>(
                          value: null, child: Text('All Roles')),
                      for (final role in Role.values)
                        DropdownMenuItem<Role?>(
                            value: role, child: Text(_roleLabel(state, role))),
                    ],
                    onChanged: (value) => setState(() {
                      _role = value;
                      _page = 0;
                    }),
                  ),
                  DropdownButton<String?>(
                    value: _status,
                    hint: const Text('Status'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All Status')),
                      for (final status in statuses)
                        DropdownMenuItem<String?>(
                            value: status, child: Text(status)),
                    ],
                    onChanged: (value) => setState(() {
                      _status = value;
                      _page = 0;
                    }),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(state.t('addUser')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text('${filtered.length} / ${state.users.length} users',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const EmptyPanel(message: 'No users match the current filters.'),
        for (final user in pageItems)
          UserListCard(
            user: user,
            canDelete: state.currentUser?.id != user.id,
            onEdit: () => _openEditor(user: user),
            onToggle: () => _toggleUser(user),
            onResetPassword: () => _resetPassword(user),
            onDelete: () => _deleteUser(user),
            onViewHistory: () => _viewHistory(user),
          ),
        if (filtered.isNotEmpty)
          PagedListControls(
            totalItems: filtered.length,
            page: _page,
            pageSize: _pageSize,
            onPageChanged: (page) => setState(() => _page = page),
          ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final settings = state.settings;
    return ListView(
      children: [
        SectionTitle(
            icon: Icons.settings_outlined, title: state.t('settingsTitle')),
        Text(state.t('settingsSub'),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.language, title: state.t('languageSetting')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      selected: state.language == AppLanguage.bm,
                      label: const Text('Bahasa Melayu (BM)',
                          overflow: TextOverflow.ellipsis),
                      onSelected: (_) => state.setLanguage(AppLanguage.bm),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      selected: state.language == AppLanguage.en,
                      label: const Text('English (EN)',
                          overflow: TextOverflow.ellipsis),
                      onSelected: (_) => state.setLanguage(AppLanguage.en),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionTitle(
                  icon: Icons.palette_outlined, title: state.t('themeSetting')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      selected: state.themeChoice == AppThemeChoice.dark,
                      avatar: const Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text(state.t('darkModeLabel'),
                          overflow: TextOverflow.ellipsis),
                      onSelected: (_) =>
                          state.setThemeChoice(AppThemeChoice.dark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      selected: state.themeChoice == AppThemeChoice.light,
                      avatar: const Icon(Icons.light_mode_outlined, size: 18),
                      label: Text(state.t('lightModeLabel'),
                          overflow: TextOverflow.ellipsis),
                      onSelected: (_) =>
                          state.setThemeChoice(AppThemeChoice.light),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingSlider(
                label: state.t('detectionConfidenceThreshold'),
                value: settings.detectionConfidence,
                onChanged: (value) => state.updateSettings(
                    settings.copyWith(detectionConfidence: value)),
              ),
              SettingSlider(
                label: state.t('ocrConfidenceThreshold'),
                value: settings.ocrConfidence,
                onChanged: (value) => state
                    .updateSettings(settings.copyWith(ocrConfidence: value)),
              ),
              SettingIntSlider(
                label: 'Auto Refresh Rate',
                value: settings.autoRefreshRate,
                min: 5,
                max: 120,
                suffix: 's',
                onChanged: (value) => state
                    .updateSettings(settings.copyWith(autoRefreshRate: value)),
              ),
              SettingIntSlider(
                label: 'Consensus Votes',
                value: settings.consensusVotes,
                min: 1,
                max: 6,
                onChanged: (value) => state
                    .updateSettings(settings.copyWith(consensusVotes: value)),
              ),
              SettingIntSlider(
                label: 'Max Active Tracks',
                value: settings.maxTracks,
                min: 1,
                max: 16,
                onChanged: (value) =>
                    state.updateSettings(settings.copyWith(maxTracks: value)),
              ),
              SettingIntSlider(
                label: 'Max OCR Concurrency',
                value: settings.maxOcrConcurrency,
                min: 1,
                max: 6,
                onChanged: (value) => state.updateSettings(
                    settings.copyWith(maxOcrConcurrency: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Special-Series Recognition'),
                subtitle: const Text(
                    'Enable registered special-prefix correction and probability scoring'),
                value: settings.enableSpecialSeries,
                onChanged: (value) => state.updateSettings(
                    settings.copyWith(enableSpecialSeries: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(state.t('soundAlertSetting')),
                subtitle: Text(state.t('soundAlertSub')),
                value: settings.soundAlerts,
                onChanged: (value) =>
                    state.updateSettings(settings.copyWith(soundAlerts: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Developer Mode'),
                subtitle: const Text(
                    'Show runtime diagnostics and native bridge warnings'),
                value: settings.developerMode,
                onChanged: state.canManageSystem
                    ? (value) => state
                        .updateSettings(settings.copyWith(developerMode: value))
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dataset Mode'),
                subtitle: const Text(
                    'Record reviewed samples for future detector/OCR retraining'),
                value: settings.datasetMode,
                onChanged: state.canManageSystem
                    ? (value) => state
                        .updateSettings(settings.copyWith(datasetMode: value))
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        MoreScreen(showHeader: true),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _oldPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  String? _loadedUserId;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _oldPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  void _syncUser(AppUser? user) {
    if (user == null || _loadedUserId == user.id) return;
    _loadedUserId = user.id;
    _name.text = user.name;
    _email.text = user.email;
    _phone.text = user.phone;
  }

  void _saveProfile() {
    AppScope.of(context).updateCurrentUser(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
    );
    _showSnack(context, 'Profile updated');
  }

  void _changePassword() {
    if (_oldPassword.text.isEmpty || _newPassword.text.length < 6) {
      _showSnack(context,
          'Enter current password and a new password with at least 6 characters');
      return;
    }
    AppScope.of(context).addHistoryLog(
      type: 'USER',
      action: 'Profile Password Change',
      details: 'Password change recorded for current demo user',
      statusMatch: 'PASSWORD',
    );
    _oldPassword.clear();
    _newPassword.clear();
    _showSnack(context, 'Password change recorded');
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).currentUser;
    final state = AppScope.of(context);
    _syncUser(user);
    return ListView(
      children: [
        SectionTitle(
            icon: Icons.person_outline, title: state.t('profileTitle')),
        Text(state.t('profileSub'),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
                radius: 28, child: Icon(Icons.person_outline)),
            title: Text(user?.name ?? '-'),
            subtitle: Text(user?.email ?? '-'),
            trailing: Text(user?.role.code ?? '-'),
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.edit_outlined, title: state.t('editProfileInfo')),
              const SizedBox(height: 10),
              TextField(
                  controller: _name,
                  decoration:
                      InputDecoration(labelText: state.t('fullNameLabel'))),
              const SizedBox(height: 10),
              TextField(
                  controller: _phone,
                  decoration:
                      InputDecoration(labelText: state.t('phoneNumberLabel'))),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    InputDecoration(labelText: state.t('emailAddressLabel')),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: user == null ? null : _saveProfile,
                icon: const Icon(Icons.save_outlined),
                label: Text(state.t('saveProfileBtn')),
              ),
            ],
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.lock_reset, title: state.t('changePassword')),
              const SizedBox(height: 10),
              TextField(
                controller: _oldPassword,
                obscureText: true,
                decoration: InputDecoration(labelText: state.t('oldPassword')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _newPassword,
                obscureText: true,
                decoration: InputDecoration(labelText: state.t('newPassword')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: user == null ? null : _changePassword,
                icon: const Icon(Icons.password),
                label: Text(state.t('changePassword')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, this.showHeader = false});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = <_MoreItem>[
      _MoreItem(
          state.t('navVehicles'), Icons.directions_car, AppSection.vehicles),
      if (state.canManageUsers)
        _MoreItem(
            state.t('navUsers'), Icons.people_alt_outlined, AppSection.users),
      _MoreItem(
          state.t('navSettings'), Icons.settings_outlined, AppSection.settings),
      _MoreItem(
          state.t('navProfile'), Icons.person_outline, AppSection.profile),
    ];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            SectionTitle(icon: Icons.more_horiz, title: state.t('moreMenu')),
            const SizedBox(height: 8),
          ],
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, color: const Color(0xFF22D3EE)),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => state.go(item.section),
            ),
        ],
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.label, this.icon, this.section);

  final String label;
  final IconData icon;
  final AppSection section;
}

class PermissionPanel extends StatelessWidget {
  const PermissionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return SectionCard(
      child: ListTile(
        leading: const Icon(Icons.lock_outline, color: Color(0xFF22D3EE)),
        title: Text(state.t('readOnlyBadge')),
        subtitle: const Text(
            'This section follows the existing ADMIN / SUPER_ADMIN permission rule.'),
      ),
    );
  }
}

class VehicleDraftDialog extends StatefulWidget {
  const VehicleDraftDialog({super.key, this.vehicle, required this.nextId});

  final Vehicle? vehicle;
  final String nextId;

  @override
  State<VehicleDraftDialog> createState() => _VehicleDraftDialogState();
}

class _VehicleDraftDialogState extends State<VehicleDraftDialog> {
  late final TextEditingController _plate =
      TextEditingController(text: widget.vehicle?.plate ?? '');
  late final TextEditingController _customerName =
      TextEditingController(text: widget.vehicle?.customerName ?? '');
  late final TextEditingController _customerId =
      TextEditingController(text: widget.vehicle?.customerId ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.vehicle?.phone ?? '');
  late final TextEditingController _brand =
      TextEditingController(text: widget.vehicle?.brand ?? '');
  late final TextEditingController _model =
      TextEditingController(text: widget.vehicle?.model ?? '');
  late final TextEditingController _colour =
      TextEditingController(text: widget.vehicle?.colour ?? '');
  late final TextEditingController _year = TextEditingController(
      text: '${widget.vehicle?.year ?? DateTime.now().year}');
  late final TextEditingController _finance =
      TextEditingController(text: widget.vehicle?.financeCompany ?? '');
  late final TextEditingController _amount = TextEditingController(
      text: widget.vehicle?.outstandingAmount.toStringAsFixed(0) ?? '');
  late final TextEditingController _reference =
      TextEditingController(text: widget.vehicle?.reference ?? '');
  late final TextEditingController _remark =
      TextEditingController(text: widget.vehicle?.remark ?? '');
  late VehiclePriority _priority =
      widget.vehicle?.priority ?? VehiclePriority.medium;
  late VehicleStatus _status = widget.vehicle?.status ?? VehicleStatus.active;

  @override
  void dispose() {
    _plate.dispose();
    _customerName.dispose();
    _customerId.dispose();
    _phone.dispose();
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _year.dispose();
    _finance.dispose();
    _amount.dispose();
    _reference.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now().toUtc();
    final original = widget.vehicle;
    final plate = cleanPlateNumber(_plate.text);
    if (plate.isEmpty || _customerName.text.trim().isEmpty) {
      _showSnack(context, 'Plate and customer name are required');
      return;
    }
    Navigator.of(context).pop(
      Vehicle(
        id: original?.id ?? widget.nextId,
        plate: plate,
        customerName: _customerName.text.trim(),
        customerId: _customerId.text.trim().isEmpty
            ? 'CUST-${widget.nextId}'
            : _customerId.text.trim(),
        phone: _phone.text.trim(),
        brand: _brand.text.trim().isEmpty ? 'Unknown' : _brand.text.trim(),
        model: _model.text.trim().isEmpty ? 'Unknown' : _model.text.trim(),
        colour: _colour.text.trim().isEmpty ? 'Unknown' : _colour.text.trim(),
        year: int.tryParse(_year.text.trim()) ?? DateTime.now().year,
        financeCompany:
            _finance.text.trim().isEmpty ? 'Unassigned' : _finance.text.trim(),
        outstandingAmount: double.tryParse(_amount.text.trim()) ?? 0,
        reference: _reference.text.trim().isEmpty
            ? 'REF-${widget.nextId}'
            : _reference.text.trim(),
        priority: _priority,
        status: _status,
        remark: _remark.text.trim(),
        createdDate: original?.createdDate ?? now,
        updatedDate: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AlertDialog(
      title:
          Text(widget.vehicle == null ? state.t('addVehicle') : 'Edit Vehicle'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                  controller: _plate,
                  label: state.t('plateNumber'),
                  textCapitalization: TextCapitalization.characters),
              _DialogField(
                  controller: _customerName, label: state.t('customerName')),
              _DialogField(controller: _customerId, label: 'Customer ID'),
              _DialogField(
                  controller: _phone,
                  label: state.t('phoneNumberLabel'),
                  keyboardType: TextInputType.phone),
              Row(
                children: [
                  Expanded(
                      child: _DialogField(controller: _brand, label: 'Brand')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _DialogField(controller: _model, label: 'Model')),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child:
                          _DialogField(controller: _colour, label: 'Colour')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _DialogField(
                          controller: _year,
                          label: 'Year',
                          keyboardType: TextInputType.number)),
                ],
              ),
              _DialogField(
                  controller: _finance, label: state.t('financeCompany')),
              _DialogField(
                  controller: _amount,
                  label: 'Outstanding Amount',
                  keyboardType: TextInputType.number),
              _DialogField(
                  controller: _reference, label: state.t('caseReference')),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<VehiclePriority>(
                      initialValue: _priority,
                      decoration:
                          InputDecoration(labelText: state.t('priority')),
                      items: [
                        for (final priority in VehiclePriority.values)
                          DropdownMenuItem(
                              value: priority, child: Text(priority.code)),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? _priority),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<VehicleStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final status in VehicleStatus.values)
                          DropdownMenuItem(
                              value: status, child: Text(status.code)),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
              _DialogField(controller: _remark, label: 'Remark', maxLines: 3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class UserDraftDialog extends StatefulWidget {
  const UserDraftDialog(
      {super.key, this.user, required this.nextId, this.createdBy});

  final AppUser? user;
  final String nextId;
  final String? createdBy;

  @override
  State<UserDraftDialog> createState() => _UserDraftDialogState();
}

class _UserDraftDialogState extends State<UserDraftDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user?.name ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.user?.email ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.user?.phone ?? '');
  late Role _role = widget.user?.role ?? Role.user;
  late String _status = widget.user?.status ?? 'ACTIVE';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      _showSnack(context, 'Name and email are required');
      return;
    }
    Navigator.of(context).pop(
      AppUser(
        id: widget.user?.id ?? widget.nextId,
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        role: _role,
        status: _status,
        avatar: widget.user?.avatar ?? '',
        lastLogin: widget.user?.lastLogin ?? DateTime.now().toUtc(),
        createdBy: widget.user?.createdBy ?? widget.createdBy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AlertDialog(
      title: Text(widget.user == null ? state.t('addUser') : 'Edit User'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(controller: _name, label: state.t('fullNameLabel')),
              _DialogField(
                  controller: _email,
                  label: state.t('emailAddressLabel'),
                  keyboardType: TextInputType.emailAddress),
              _DialogField(
                  controller: _phone,
                  label: state.t('phoneNumberLabel'),
                  keyboardType: TextInputType.phone),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Role>(
                      initialValue: _role,
                      decoration:
                          InputDecoration(labelText: state.t('roleHeader')),
                      items: [
                        for (final role in Role.values)
                          DropdownMenuItem(
                              value: role,
                              child: Text(_roleLabel(state, role))),
                      ],
                      onChanged: (value) =>
                          setState(() => _role = value ?? _role),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                            value: 'ACTIVE', child: Text('ACTIVE')),
                        DropdownMenuItem(
                            value: 'DISABLED', child: Text('DISABLED')),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class VehicleListCard extends StatelessWidget {
  const VehicleListCard({
    super.key,
    required this.vehicle,
    this.canEdit = false,
    this.onEdit,
    this.onDelete,
  });

  final Vehicle vehicle;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(vehicle.plate,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        subtitle: Text(
          '${vehicle.brand} ${vehicle.model} / ${vehicle.colour} / ${vehicle.year}\n'
          '${vehicle.customerName} / ${vehicle.financeCompany} / ${vehicle.reference}\n'
          '${vehicle.status.code} / ${vehicle.remark}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(vehicle.priority.code,
                    style: const TextStyle(
                        color: Color(0xFF22D3EE), fontWeight: FontWeight.w900)),
                Text(_currency(vehicle.outstandingAmount),
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
            if (canEdit)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class UserListCard extends StatelessWidget {
  const UserListCard({
    super.key,
    required this.user,
    required this.canDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onResetPassword,
    required this.onDelete,
    required this.onViewHistory,
  });

  final AppUser user;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            child: Text(user.name.isEmpty
                ? '?'
                : user.name.characters.first.toUpperCase())),
        title: Text(user.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            '${user.email}\n${user.phone} / ${user.status} / ${_formatTime(user.lastLogin)}'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user.role.code,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'toggle') onToggle();
                if (value == 'reset') onResetPassword();
                if (value == 'delete') onDelete();
                if (value == 'history') onViewHistory();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                    value: 'history', child: Text('View History')),
                PopupMenuItem(
                    value: 'toggle',
                    child:
                        Text(user.status == 'ACTIVE' ? 'Disable' : 'Enable')),
                const PopupMenuItem(
                    value: 'reset', child: Text('Reset Password')),
                if (canDelete)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UserHistoryDialog extends StatelessWidget {
  const UserHistoryDialog({super.key, required this.user, required this.logs});

  final AppUser user;
  final List<HistoryLog> logs;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${user.name} History'),
      content: SizedBox(
        width: 520,
        child: logs.isEmpty
            ? const Text('No audit records for this user yet.')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final log in logs)
                      ListTile(
                        leading: Icon(_historyIcon(log.type),
                            color: const Color(0xFF22D3EE)),
                        title: Text(log.action),
                        subtitle: Text(
                            '${log.details}\n${_formatTime(log.timestamp)}'),
                        isThreeLine: true,
                        trailing: Text(log.statusMatch ?? log.type),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class VehicleMatchCard extends StatelessWidget {
  const VehicleMatchCard(
      {super.key, required this.vehicle, required this.tone});

  final Vehicle vehicle;
  final String tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          tone == 'EXACT' ? Icons.warning_amber : Icons.help_outline,
          color: tone == 'EXACT'
              ? const Color(0xFFF87171)
              : const Color(0xFFFBBF24),
        ),
        title: Text(vehicle.plate,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        subtitle: Text(
            '${vehicle.brand} ${vehicle.model} · ${vehicle.customerName}\n${vehicle.financeCompany} · ${vehicle.reference}'),
        isThreeLine: true,
        trailing:
            Text(tone, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class HistoryListTile extends StatelessWidget {
  const HistoryListTile({super.key, required this.log});

  final HistoryLog log;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(_historyIcon(log.type), color: const Color(0xFF22D3EE)),
        title: Text(log.plate ?? log.action,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${log.details}\n${_formatTime(log.timestamp)}'),
        isThreeLine: true,
        trailing: Text(log.statusMatch ?? log.type,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${(value * 100).round()}%'),
          ],
        ),
        Slider(
            value: value,
            min: 0.1,
            max: 0.95,
            divisions: 85,
            onChanged: onChanged),
      ],
    );
  }
}

class SettingIntSlider extends StatelessWidget {
  const SettingIntSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('$value$suffix'),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (next) => onChanged(next.round()),
        ),
      ],
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.inbox_outlined, color: Color(0xFF22D3EE)),
        title: Text(message),
      ),
    );
  }
}

class PagedListControls extends StatelessWidget {
  const PagedListControls({
    super.key,
    required this.totalItems,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
  });

  final int totalItems;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final pageCount = ((totalItems + pageSize - 1) ~/ pageSize).clamp(1, 9999);
    final safePage = page.clamp(0, pageCount - 1);
    final start = totalItems == 0 ? 0 : safePage * pageSize + 1;
    final end = (safePage * pageSize + pageSize).clamp(0, totalItems);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$start-$end of $totalItems',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Previous Page',
            onPressed: safePage == 0 ? null : () => onPageChanged(safePage - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          Text('${safePage + 1} / $pageCount',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Next Page',
            onPressed: safePage >= pageCount - 1
                ? null
                : () => onPageChanged(safePage + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
              Icon(icon, color: const Color(0xFF22D3EE), size: 18),
            ],
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF22D3EE), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class MetricChip extends StatelessWidget {
  const MetricChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value', overflow: TextOverflow.ellipsis),
      side: const BorderSide(color: Color(0xFF1E293B)),
      backgroundColor: const Color(0xFF020617),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final Role role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        label: Text(role.code,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        backgroundColor: const Color(0xFF082F49),
        side: const BorderSide(color: Color(0xFF155E75)),
      ),
    );
  }
}

Color _trackColor(String matchType) {
  switch (matchType) {
    case 'EXACT':
      return const Color(0xFFEF4444);
    case 'POSSIBLE':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF06B6D4);
  }
}

String _friendlyBridgeError(Object error) {
  if (error is MissingPluginException) {
    return 'Native ANPR plugin is not registered yet. Generate Android/iOS shells and implement the bridge contract.';
  }
  if (error is PlatformException) {
    return error.message ?? error.code;
  }
  return error.toString();
}

String _currency(double value) {
  return 'RM ${value.toStringAsFixed(0)}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final date = local.toString();
  return date.length >= 16 ? date.substring(0, 16) : date;
}

String _roleLabel(AppState state, Role role) {
  switch (role) {
    case Role.user:
      return state.t('roleUser');
    case Role.admin:
      return state.t('roleAdmin');
    case Role.superAdmin:
      return state.t('roleSuperAdmin');
  }
}

String _searchScopeLabel(AppState state, SearchScope scope) {
  switch (scope) {
    case SearchScope.all:
      return 'All';
    case SearchScope.plate:
      return state.t('plateNumber');
    case SearchScope.customer:
      return state.t('customerName');
    case SearchScope.finance:
      return state.t('financeCompany');
    case SearchScope.reference:
      return state.t('caseReference');
    case SearchScope.vehicle:
      return state.t('vehicleDetails');
  }
}

bool _matchesVehicleFilter(
  Vehicle vehicle,
  String query,
  VehicleStatus? status,
  VehiclePriority? priority,
) {
  if (status != null && vehicle.status != status) return false;
  if (priority != null && vehicle.priority != priority) return false;
  final lowerQuery = query.trim().toLowerCase();
  final cleaned = cleanPlateNumber(query);
  if (lowerQuery.isEmpty && cleaned.isEmpty) return true;
  final haystacks = [
    vehicle.plate,
    vehicle.customerName,
    vehicle.customerId,
    vehicle.phone,
    vehicle.brand,
    vehicle.model,
    vehicle.colour,
    vehicle.financeCompany,
    vehicle.reference,
    vehicle.remark,
    vehicle.status.code,
    vehicle.priority.code,
    '${vehicle.year}',
  ];
  return haystacks.any((value) {
    return value.toLowerCase().contains(lowerQuery) ||
        cleanPlateNumber(value).contains(cleaned);
  });
}

bool _matchesHistoryFilter(HistoryLog log, String query, String? type) {
  if (type != null && log.type != type) return false;
  final lowerQuery = query.trim().toLowerCase();
  final cleaned = cleanPlateNumber(query);
  if (lowerQuery.isEmpty && cleaned.isEmpty) return true;
  final haystacks = [
    log.type,
    log.action,
    log.plate ?? '',
    log.details,
    log.statusMatch ?? '',
    log.cameraName ?? '',
    log.actorName ?? '',
    log.userRole.code,
  ];
  return haystacks.any((value) {
    return value.toLowerCase().contains(lowerQuery) ||
        cleanPlateNumber(value).contains(cleaned);
  });
}

bool _matchesUserFilter(
    AppUser user, String query, Role? role, String? status) {
  if (role != null && user.role != role) return false;
  if (status != null && user.status != status) return false;
  final lowerQuery = query.trim().toLowerCase();
  if (lowerQuery.isEmpty) return true;
  return [user.name, user.email, user.phone, user.role.code, user.status]
      .any((value) {
    return value.toLowerCase().contains(lowerQuery);
  });
}

List<T> _pagedItems<T>(List<T> items, int page, int pageSize) {
  if (items.isEmpty) return const [];
  final pageCount = ((items.length + pageSize - 1) ~/ pageSize).clamp(1, 9999);
  final safePage = page.clamp(0, pageCount - 1);
  final start = safePage * pageSize;
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start, end);
}

String _nextVehicleId(List<Vehicle> vehicles) {
  final next = vehicles.length + 1;
  return 'veh-${next.toString().padLeft(3, '0')}';
}

String _nextUserId(List<AppUser> users) {
  final next = users.length + 1;
  return 'user-${next.toString().padLeft(3, '0')}';
}

String _vehiclesToCsv(List<Vehicle> vehicles) {
  final rows = <List<Object?>>[
    [
      'plate',
      'customer_name',
      'customer_id',
      'phone',
      'brand',
      'model',
      'colour',
      'year',
      'finance_company',
      'outstanding_amount',
      'reference',
      'priority',
      'status',
      'remark',
    ],
    for (final vehicle in vehicles)
      [
        vehicle.plate,
        vehicle.customerName,
        vehicle.customerId,
        vehicle.phone,
        vehicle.brand,
        vehicle.model,
        vehicle.colour,
        vehicle.year,
        vehicle.financeCompany,
        vehicle.outstandingAmount,
        vehicle.reference,
        vehicle.priority.code,
        vehicle.status.code,
        vehicle.remark,
      ],
  ];
  return rows.map(_csvRow).join('\n');
}

String _historyToCsv(List<HistoryLog> history) {
  final rows = <List<Object?>>[
    [
      'timestamp',
      'type',
      'action',
      'plate',
      'details',
      'status',
      'actor',
      'role',
      'camera'
    ],
    for (final log in history)
      [
        log.timestamp.toIso8601String(),
        log.type,
        log.action,
        log.plate ?? '',
        log.details,
        log.statusMatch ?? '',
        log.actorName ?? '',
        log.userRole.code,
        log.cameraName ?? '',
      ],
  ];
  return rows.map(_csvRow).join('\n');
}

String _csvRow(List<Object?> values) {
  return values.map((value) {
    final escaped = '$value'.replaceAll('"', '""');
    return '"$escaped"';
  }).join(',');
}

IconData _historyIcon(String type) {
  switch (type) {
    case 'DETECTION':
      return Icons.camera_alt_outlined;
    case 'DATABASE':
      return Icons.storage_outlined;
    case 'USER':
      return Icons.people_alt_outlined;
    default:
      return Icons.search;
  }
}

Future<bool> _confirmAction(
    BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm')),
      ],
    ),
  );
  return result ?? false;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
