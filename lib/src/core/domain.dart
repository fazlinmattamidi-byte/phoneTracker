enum Role {
  user,
  admin,
  superAdmin,
}

extension RoleCode on Role {
  String get code {
    switch (this) {
      case Role.user:
        return 'USER';
      case Role.admin:
        return 'ADMIN';
      case Role.superAdmin:
        return 'SUPER_ADMIN';
    }
  }

  String get label {
    switch (this) {
      case Role.user:
        return 'User';
      case Role.admin:
        return 'Admin';
      case Role.superAdmin:
        return 'Super Admin';
    }
  }

  static Role fromCode(String value) {
    switch (value) {
      case 'USER':
        return Role.user;
      case 'ADMIN':
        return Role.admin;
      case 'SUPER_ADMIN':
      default:
        return Role.superAdmin;
    }
  }
}

enum VehicleStatus {
  active,
  flagged,
  pending,
  cleared,
}

extension VehicleStatusCode on VehicleStatus {
  String get code {
    switch (this) {
      case VehicleStatus.active:
        return 'ACTIVE';
      case VehicleStatus.flagged:
        return 'FLAGGED';
      case VehicleStatus.pending:
        return 'PENDING';
      case VehicleStatus.cleared:
        return 'CLEARED';
    }
  }
}

enum VehiclePriority {
  high,
  medium,
  low,
}

extension VehiclePriorityCode on VehiclePriority {
  String get code {
    switch (this) {
      case VehiclePriority.high:
        return 'HIGH';
      case VehiclePriority.medium:
        return 'MEDIUM';
      case VehiclePriority.low:
        return 'LOW';
    }
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.plate,
    required this.customerName,
    required this.customerId,
    required this.phone,
    required this.brand,
    required this.model,
    required this.colour,
    required this.year,
    required this.financeCompany,
    required this.outstandingAmount,
    required this.reference,
    required this.priority,
    required this.status,
    required this.remark,
    required this.createdDate,
    required this.updatedDate,
  });

  final String id;
  final String plate;
  final String customerName;
  final String customerId;
  final String phone;
  final String brand;
  final String model;
  final String colour;
  final int year;
  final String financeCompany;
  final double outstandingAmount;
  final String reference;
  final VehiclePriority priority;
  final VehicleStatus status;
  final String remark;
  final DateTime createdDate;
  final DateTime updatedDate;

  Vehicle copyWith({
    String? id,
    String? plate,
    String? customerName,
    String? customerId,
    String? phone,
    String? brand,
    String? model,
    String? colour,
    int? year,
    String? financeCompany,
    double? outstandingAmount,
    String? reference,
    VehiclePriority? priority,
    VehicleStatus? status,
    String? remark,
    DateTime? createdDate,
    DateTime? updatedDate,
  }) {
    return Vehicle(
      id: id ?? this.id,
      plate: plate ?? this.plate,
      customerName: customerName ?? this.customerName,
      customerId: customerId ?? this.customerId,
      phone: phone ?? this.phone,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      colour: colour ?? this.colour,
      year: year ?? this.year,
      financeCompany: financeCompany ?? this.financeCompany,
      outstandingAmount: outstandingAmount ?? this.outstandingAmount,
      reference: reference ?? this.reference,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      remark: remark ?? this.remark,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.avatar,
    required this.lastLogin,
    this.createdBy,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final Role role;
  final String status;
  final String avatar;
  final DateTime lastLogin;
  final String? createdBy;

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    Role? role,
    String? status,
    String? avatar,
    DateTime? lastLogin,
    String? createdBy,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      status: status ?? this.status,
      avatar: avatar ?? this.avatar,
      lastLogin: lastLogin ?? this.lastLogin,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}

class CameraDevice {
  const CameraDevice({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
    required this.type,
    required this.url,
    required this.fps,
    required this.resolution,
  });

  final String id;
  final String name;
  final String location;
  final String status;
  final String type;
  final String url;
  final int fps;
  final String resolution;
}

class HistoryLog {
  const HistoryLog({
    required this.id,
    required this.type,
    required this.action,
    required this.details,
    required this.userRole,
    required this.timestamp,
    this.plate,
    this.statusMatch,
    this.note,
    this.cameraId,
    this.cameraName,
    this.actorId,
    this.actorName,
  });

  final String id;
  final String type;
  final String action;
  final String? plate;
  final String details;
  final Role userRole;
  final DateTime timestamp;
  final String? statusMatch;
  final String? note;
  final String? cameraId;
  final String? cameraName;
  final String? actorId;
  final String? actorName;
}

class SystemSettings {
  const SystemSettings({
    required this.detectionConfidence,
    required this.ocrConfidence,
    required this.soundAlerts,
    required this.autoRefreshRate,
    required this.consensusVotes,
    required this.maxTracks,
    required this.maxOcrConcurrency,
    required this.enableSpecialSeries,
    required this.developerMode,
    required this.datasetMode,
  });

  final double detectionConfidence;
  final double ocrConfidence;
  final bool soundAlerts;
  final int autoRefreshRate;
  final int consensusVotes;
  final int maxTracks;
  final int maxOcrConcurrency;
  final bool enableSpecialSeries;
  final bool developerMode;
  final bool datasetMode;

  SystemSettings copyWith({
    double? detectionConfidence,
    double? ocrConfidence,
    bool? soundAlerts,
    int? autoRefreshRate,
    int? consensusVotes,
    int? maxTracks,
    int? maxOcrConcurrency,
    bool? enableSpecialSeries,
    bool? developerMode,
    bool? datasetMode,
  }) {
    return SystemSettings(
      detectionConfidence: detectionConfidence ?? this.detectionConfidence,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      soundAlerts: soundAlerts ?? this.soundAlerts,
      autoRefreshRate: autoRefreshRate ?? this.autoRefreshRate,
      consensusVotes: consensusVotes ?? this.consensusVotes,
      maxTracks: maxTracks ?? this.maxTracks,
      maxOcrConcurrency: maxOcrConcurrency ?? this.maxOcrConcurrency,
      enableSpecialSeries: enableSpecialSeries ?? this.enableSpecialSeries,
      developerMode: developerMode ?? this.developerMode,
      datasetMode: datasetMode ?? this.datasetMode,
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.exactMatch,
    required this.possibleMatches,
  });

  final Vehicle? exactMatch;
  final List<Vehicle> possibleMatches;
}

String cleanPlateNumber(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

DateTime _dt(String value) => DateTime.parse(value);

const defaultSettings = SystemSettings(
  detectionConfidence: 0.35,
  ocrConfidence: 0.60,
  soundAlerts: true,
  autoRefreshRate: 30,
  consensusVotes: 3,
  maxTracks: 8,
  maxOcrConcurrency: 3,
  enableSpecialSeries: true,
  developerMode: false,
  datasetMode: false,
);

Vehicle _seedVehicle({
  required String id,
  required String plate,
  required String customerName,
  required String customerId,
  required String phone,
  required String brand,
  required String model,
  required String colour,
  required int year,
  required String financeCompany,
  required double outstandingAmount,
  required String reference,
  required VehiclePriority priority,
  required VehicleStatus status,
  required String remark,
  required String createdDate,
  required String updatedDate,
}) {
  return Vehicle(
    id: id,
    plate: plate,
    customerName: customerName,
    customerId: customerId,
    phone: phone,
    brand: brand,
    model: model,
    colour: colour,
    year: year,
    financeCompany: financeCompany,
    outstandingAmount: outstandingAmount,
    reference: reference,
    priority: priority,
    status: status,
    remark: remark,
    createdDate: _dt(createdDate),
    updatedDate: _dt(updatedDate),
  );
}

final seedVehicles = <Vehicle>[
  Vehicle(
    id: 'veh-001',
    plate: 'ANN7569',
    customerName: 'Ahmad',
    customerId: 'CUST-001',
    phone: '+60 12-345 6789',
    brand: 'Perodua',
    model: 'Bezza',
    colour: 'White',
    year: 2021,
    financeCompany: 'CIMB Bank',
    outstandingAmount: 15000,
    reference: 'CIMB001',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Priority repossession case.',
    createdDate: _dt('2026-06-10T08:30:00Z'),
    updatedDate: _dt('2026-07-20T14:15:00Z'),
  ),
  Vehicle(
    id: 'veh-002',
    plate: 'ABC1234',
    customerName: 'Muthu',
    customerId: 'CUST-002',
    phone: '+60 16-889 1234',
    brand: 'Yamaha',
    model: 'Y15ZR',
    colour: 'Blue',
    year: 2022,
    financeCompany: 'Aeon Credit',
    outstandingAmount: 6800,
    reference: 'AEON-M01',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Overdue installment 5 months.',
    createdDate: _dt('2026-05-12T10:00:00Z'),
    updatedDate: _dt('2026-07-21T09:30:00Z'),
  ),
  Vehicle(
    id: 'veh-003',
    plate: '1122DP',
    customerName: 'Embassy Officer',
    customerId: 'CUST-003',
    phone: '+60 19-333 4455',
    brand: 'Mercedes-Benz',
    model: 'E200',
    colour: 'Black',
    year: 2020,
    financeCompany: 'Affinity Capital',
    outstandingAmount: 42000,
    reference: 'DIP-99',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Diplomatic series flagged case.',
    createdDate: _dt('2026-04-18T11:20:00Z'),
    updatedDate: _dt('2026-07-19T16:00:00Z'),
  ),
  Vehicle(
    id: 'veh-004',
    plate: 'QAA1234',
    customerName: 'Abang Johari',
    customerId: 'CUST-004',
    phone: '+60 13-801 9988',
    brand: 'Ford',
    model: 'Ranger',
    colour: 'Silver',
    year: 2023,
    financeCompany: 'Bank Islam',
    outstandingAmount: 31000,
    reference: 'BIMB-101',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Sarawak state territory vehicle.',
    createdDate: _dt('2026-06-01T09:10:00Z'),
    updatedDate: _dt('2026-07-22T11:45:00Z'),
  ),
  Vehicle(
    id: 'veh-005',
    plate: 'SAB1234',
    customerName: 'Jeffry Kitingan',
    customerId: 'CUST-005',
    phone: '+60 14-772 3344',
    brand: 'Toyota',
    model: 'Hilux',
    colour: 'White',
    year: 2022,
    financeCompany: 'Sabah Credit',
    outstandingAmount: 24500,
    reference: 'SCC-909',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Sabah registration unit.',
    createdDate: _dt('2026-03-25T13:40:00Z'),
    updatedDate: _dt('2026-07-18T10:00:00Z'),
  ),
  _seedVehicle(
    id: 'veh-006',
    plate: 'W8821X',
    customerName: 'Lim Guan Hock',
    customerId: 'CUST-006',
    phone: '+60 12-998 1122',
    brand: 'Proton',
    model: 'X50',
    colour: 'Red',
    year: 2021,
    financeCompany: 'Maybank',
    outstandingAmount: 18500,
    reference: 'MBB-8821',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Kuala Lumpur active repo.',
    createdDate: '2026-05-02T14:30:00Z',
    updatedDate: '2026-07-22T17:10:00Z',
  ),
  _seedVehicle(
    id: 'veh-007',
    plate: 'VAB1290',
    customerName: 'Siti Nurhaliza',
    customerId: 'CUST-007',
    phone: '+60 17-665 4433',
    brand: 'Honda',
    model: 'CR-V',
    colour: 'Grey',
    year: 2020,
    financeCompany: 'Public Bank',
    outstandingAmount: 28900,
    reference: 'PBB-1290',
    priority: VehiclePriority.medium,
    status: VehicleStatus.flagged,
    remark: 'Spotted in Petaling Jaya area.',
    createdDate: '2026-04-10T16:00:00Z',
    updatedDate: '2026-07-23T08:20:00Z',
  ),
  _seedVehicle(
    id: 'veh-008',
    plate: 'BKP4412',
    customerName: 'Chong Wei Feng',
    customerId: 'CUST-008',
    phone: '+60 11-234 5678',
    brand: 'BMW',
    model: '320i',
    colour: 'Black',
    year: 2019,
    financeCompany: 'Hong Leong Bank',
    outstandingAmount: 52000,
    reference: 'HLB-4412',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Selangor area high value asset.',
    createdDate: '2026-02-14T11:00:00Z',
    updatedDate: '2026-07-21T13:00:00Z',
  ),
  _seedVehicle(
    id: 'veh-009',
    plate: 'JSH7710',
    customerName: 'Zulkifli Hassan',
    customerId: 'CUST-009',
    phone: '+60 19-876 5432',
    brand: 'Proton',
    model: 'Saga',
    colour: 'Ruby Red',
    year: 2022,
    financeCompany: 'RHB Bank',
    outstandingAmount: 9800,
    reference: 'RHB-7710',
    priority: VehiclePriority.low,
    status: VehicleStatus.pending,
    remark: 'Johor Bahru border alert.',
    createdDate: '2026-06-18T10:15:00Z',
    updatedDate: '2026-07-22T09:00:00Z',
  ),
  _seedVehicle(
    id: 'veh-010',
    plate: 'PNN3300',
    customerName: 'Tan Kah Kee',
    customerId: 'CUST-010',
    phone: '+60 16-554 9911',
    brand: 'Toyota',
    model: 'Vios',
    colour: 'Silver',
    year: 2021,
    financeCompany: 'Affin Bank',
    outstandingAmount: 16400,
    reference: 'AFF-3300',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Penang island target.',
    createdDate: '2026-05-19T12:00:00Z',
    updatedDate: '2026-07-20T15:30:00Z',
  ),
  _seedVehicle(
    id: 'veh-011',
    plate: 'KDA9090',
    customerName: 'Rozita Che Wan',
    customerId: 'CUST-011',
    phone: '+60 12-443 2211',
    brand: 'Mazda',
    model: 'CX-5',
    colour: 'Soul Red',
    year: 2021,
    financeCompany: 'MBSB Bank',
    outstandingAmount: 34000,
    reference: 'MBSB-9090',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Kedah border region.',
    createdDate: '2026-04-05T09:40:00Z',
    updatedDate: '2026-07-19T14:10:00Z',
  ),
  _seedVehicle(
    id: 'veh-012',
    plate: 'AKR5050',
    customerName: 'Ramasamy',
    customerId: 'CUST-012',
    phone: '+60 13-332 1100',
    brand: 'Nissan',
    model: 'Navara',
    colour: 'Orange',
    year: 2020,
    financeCompany: 'CIMB Bank',
    outstandingAmount: 22800,
    reference: 'CIMB-5050',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Perak estate area vehicle.',
    createdDate: '2026-03-12T15:00:00Z',
    updatedDate: '2026-07-17T11:20:00Z',
  ),
  Vehicle(
    id: 'veh-013',
    plate: 'WYY88',
    customerName: 'Dato Seri Vincent',
    customerId: 'CUST-013',
    phone: '+60 12-888 8888',
    brand: 'Toyota',
    model: 'Alphard',
    colour: 'White',
    year: 2022,
    financeCompany: 'Maybank',
    outstandingAmount: 115000,
    reference: 'MBB-W88',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Luxury VIP van repo notice.',
    createdDate: _dt('2026-01-10T10:00:00Z'),
    updatedDate: _dt('2026-07-23T07:45:00Z'),
  ),
  _seedVehicle(
    id: 'veh-014',
    plate: 'VCE4040',
    customerName: 'Farah Ann',
    customerId: 'CUST-014',
    phone: '+60 17-221 8899',
    brand: 'Honda',
    model: 'Civic',
    colour: 'White',
    year: 2022,
    financeCompany: 'Public Bank',
    outstandingAmount: 27500,
    reference: 'PBB-4040',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Subang Jaya target.',
    createdDate: '2026-06-15T11:30:00Z',
    updatedDate: '2026-07-22T16:20:00Z',
  ),
  _seedVehicle(
    id: 'veh-015',
    plate: 'BLM9911',
    customerName: 'Mohd Faiz',
    customerId: 'CUST-015',
    phone: '+60 18-990 4422',
    brand: 'Perodua',
    model: 'Myvi',
    colour: 'Cranberry Red',
    year: 2020,
    financeCompany: 'Hong Leong Bank',
    outstandingAmount: 11200,
    reference: 'HLB-9911',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Shah Alam residential area.',
    createdDate: '2026-05-30T14:00:00Z',
    updatedDate: '2026-07-21T18:00:00Z',
  ),
  _seedVehicle(
    id: 'veh-016',
    plate: 'JQX2244',
    customerName: 'Kavitha Devi',
    customerId: 'CUST-016',
    phone: '+60 16-778 8811',
    brand: 'Proton',
    model: 'X70',
    colour: 'Armour Silver',
    year: 2021,
    financeCompany: 'Bank Islam',
    outstandingAmount: 29500,
    reference: 'BIMB-2244',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Tebrau commercial strip.',
    createdDate: '2026-04-22T13:10:00Z',
    updatedDate: '2026-07-22T12:00:00Z',
  ),
  _seedVehicle(
    id: 'veh-017',
    plate: 'PKK7788',
    customerName: 'Khoo Boon Beng',
    customerId: 'CUST-017',
    phone: '+60 12-401 2299',
    brand: 'Honda',
    model: 'City',
    colour: 'Modern Steel',
    year: 2021,
    financeCompany: 'RHB Bank',
    outstandingAmount: 17800,
    reference: 'RHB-7788',
    priority: VehiclePriority.low,
    status: VehicleStatus.cleared,
    remark: 'Settlement completed on 20 July.',
    createdDate: '2026-03-01T08:00:00Z',
    updatedDate: '2026-07-20T10:00:00Z',
  ),
  _seedVehicle(
    id: 'veh-018',
    plate: 'AAM1010',
    customerName: 'Shaharuddin',
    customerId: 'CUST-018',
    phone: '+60 19-556 7744',
    brand: 'Perodua',
    model: 'Axia',
    colour: 'Lava Red',
    year: 2019,
    financeCompany: 'Aeon Credit',
    outstandingAmount: 8200,
    reference: 'AEON-1010',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Ipoh town center.',
    createdDate: '2026-05-14T09:20:00Z',
    updatedDate: '2026-07-18T16:30:00Z',
  ),
  _seedVehicle(
    id: 'veh-019',
    plate: 'QS888A',
    customerName: 'Henry Golding',
    customerId: 'CUST-019',
    phone: '+60 11-100 2003',
    brand: 'Toyota',
    model: 'Camry',
    colour: 'Graphite',
    year: 2022,
    financeCompany: 'Maybank',
    outstandingAmount: 48000,
    reference: 'MBB-QS88',
    priority: VehiclePriority.high,
    status: VehicleStatus.active,
    remark: 'Kuching Waterfront parking alert.',
    createdDate: '2026-06-08T15:30:00Z',
    updatedDate: '2026-07-22T08:15:00Z',
  ),
  _seedVehicle(
    id: 'veh-020',
    plate: 'SAC4455',
    customerName: 'Wilfred Madius',
    customerId: 'CUST-020',
    phone: '+60 14-889 0011',
    brand: 'Perodua',
    model: 'Ativa',
    colour: 'Turquoise Blue',
    year: 2022,
    financeCompany: 'Affin Bank',
    outstandingAmount: 19800,
    reference: 'AFF-4455',
    priority: VehiclePriority.medium,
    status: VehicleStatus.active,
    remark: 'Kota Kinabalu port area.',
    createdDate: '2026-05-01T10:45:00Z',
    updatedDate: '2026-07-21T11:00:00Z',
  ),
  ..._generatedDemoVehicles(),
];

List<Vehicle> _generatedDemoVehicles() {
  const statePrefixes = [
    'W',
    'V',
    'B',
    'J',
    'P',
    'K',
    'A',
    'Q',
    'SAB',
    'M',
    'N',
    'C',
    'D'
  ];
  const brands = [
    'Perodua',
    'Proton',
    'Toyota',
    'Honda',
    'Mazda',
    'Nissan',
    'BMW',
    'Mercedes-Benz',
    'Ford'
  ];
  const banks = [
    'Maybank',
    'CIMB Bank',
    'Public Bank',
    'Hong Leong Bank',
    'Bank Islam',
    'RHB Bank',
    'Affin Bank',
    'Aeon Credit',
    'MBSB Bank'
  ];
  const colors = ['White', 'Black', 'Silver', 'Grey', 'Red', 'Blue', 'Amber'];
  const priorities = [
    VehiclePriority.high,
    VehiclePriority.medium,
    VehiclePriority.low
  ];
  const statuses = [
    VehicleStatus.active,
    VehicleStatus.active,
    VehicleStatus.flagged,
    VehicleStatus.pending,
    VehicleStatus.active
  ];
  const models = <String, List<String>>{
    'Perodua': ['Bezza', 'Myvi', 'Axia', 'Ativa', 'Alza'],
    'Proton': ['X50', 'X70', 'Saga', 'Persona', 'Iriz'],
    'Toyota': ['Hilux', 'Vios', 'Camry', 'Yaris', 'Corolla'],
    'Honda': ['Civic', 'City', 'CR-V', 'HR-V', 'Accord'],
    'Mazda': ['CX-5', 'CX-30', 'Mazda 3'],
    'Nissan': ['Navara', 'Serena', 'Almera'],
    'BMW': ['320i', '530i', 'X3'],
    'Mercedes-Benz': ['C200', 'GLC250', 'A200'],
    'Ford': ['Ranger', 'Everest'],
  };

  return List<Vehicle>.generate(30, (index) {
    final itemNumber = index + 21;
    final statePrefix = statePrefixes[index % statePrefixes.length];
    final plateNumber = 1000 + index * 231;
    final brand = brands[index % brands.length];
    final modelList = models[brand] ?? const ['Model Standard'];
    final model = modelList[index % modelList.length];
    final bank = banks[index % banks.length];
    final color = colors[index % colors.length];
    final priority = priorities[index % priorities.length];
    final status = statuses[index % statuses.length];

    return _seedVehicle(
      id: 'veh-${itemNumber.toString().padLeft(3, '0')}',
      plate: '$statePrefix${plateNumber}K',
      customerName: 'Customer Demo $itemNumber',
      customerId: 'CUST-${itemNumber.toString().padLeft(3, '0')}',
      phone: '+60 1${index % 9}-$plateNumber 889',
      brand: brand,
      model: model,
      colour: color,
      year: 2019 + (index % 5),
      financeCompany: bank,
      outstandingAmount: (8500 + index * 1450).toDouble(),
      reference: 'REF-$statePrefix-$plateNumber',
      priority: priority,
      status: status,
      remark: 'Automated database seed entry #$itemNumber',
      createdDate: '2026-0${1 + (index % 6)}-${10 + (index % 15)}T10:00:00Z',
      updatedDate: '2026-07-${15 + (index % 8)}T12:00:00Z',
    );
  });
}

final seedUsers = <AppUser>[
  AppUser(
    id: 'user-001',
    name: 'Super Admin Track',
    email: 'superadmin@track.my',
    phone: '+60 12-000 9999',
    role: Role.superAdmin,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-24T00:45:00Z'),
    createdBy: 'system',
  ),
  AppUser(
    id: 'user-010',
    name: 'Super Admin Audit',
    email: 'audit.super@track.my',
    phone: '+60 12-880 1001',
    role: Role.superAdmin,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1560250097-0b93528c311a?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-24T00:20:00Z'),
    createdBy: 'system',
  ),
  AppUser(
    id: 'user-002',
    name: 'Admin Operational',
    email: 'admin@track.my',
    phone: '+60 13-111 8888',
    role: Role.admin,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T22:30:00Z'),
    createdBy: 'user-001',
  ),
  AppUser(
    id: 'user-011',
    name: 'Admin North Zone',
    email: 'north.admin@track.my',
    phone: '+60 13-221 8801',
    role: Role.admin,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T21:10:00Z'),
    createdBy: 'user-001',
  ),
  AppUser(
    id: 'user-012',
    name: 'Admin East Ops',
    email: 'east.admin@track.my',
    phone: '+60 13-221 8802',
    role: Role.admin,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T20:55:00Z'),
    createdBy: 'user-010',
  ),
  AppUser(
    id: 'user-003',
    name: 'Officer User',
    email: 'officer@track.my',
    phone: '+60 19-222 7777',
    role: Role.user,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T19:15:00Z'),
    createdBy: 'user-002',
  ),
  AppUser(
    id: 'user-021',
    name: 'Officer Farid',
    email: 'farid.officer@track.my',
    phone: '+60 19-222 7711',
    role: Role.user,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T18:45:00Z'),
    createdBy: 'user-002',
  ),
  AppUser(
    id: 'user-022',
    name: 'Officer Mei Lin',
    email: 'meilin.officer@track.my',
    phone: '+60 18-322 7712',
    role: Role.user,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T17:35:00Z'),
    createdBy: 'user-002',
  ),
  AppUser(
    id: 'user-023',
    name: 'Officer Kumar',
    email: 'kumar.officer@track.my',
    phone: '+60 17-422 7713',
    role: Role.user,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1507591064344-4c6ce005b128?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T16:20:00Z'),
    createdBy: 'user-011',
  ),
  AppUser(
    id: 'user-024',
    name: 'Officer Iman',
    email: 'iman.officer@track.my',
    phone: '+60 16-522 7714',
    role: Role.user,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T15:50:00Z'),
    createdBy: 'user-011',
  ),
  AppUser(
    id: 'user-025',
    name: 'Officer Daniel',
    email: 'daniel.officer@track.my',
    phone: '+60 15-622 7715',
    role: Role.user,
    status: 'DISABLED',
    avatar:
        'https://images.unsplash.com/photo-1519345182560-3f2917c472ef?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-22T12:10:00Z'),
    createdBy: 'user-012',
  ),
  AppUser(
    id: 'user-026',
    name: 'Officer Nur Aina',
    email: 'aina.officer@track.my',
    phone: '+60 14-722 7716',
    role: Role.user,
    status: 'ACTIVE',
    avatar:
        'https://images.unsplash.com/photo-1531123897727-8f129e1688ce?auto=format&fit=crop&w=250&q=80',
    lastLogin: _dt('2026-07-23T14:05:00Z'),
    createdBy: 'user-012',
  ),
];

final seedCameras = <CameraDevice>[
  const CameraDevice(
    id: 'native-back',
    name: 'Rear Camera',
    location: 'Device',
    status: 'ONLINE',
    type: 'NATIVE',
    url: 'camera://rear',
    fps: 30,
    resolution: '1920x1080',
  ),
];

final seedHistory = <HistoryLog>[
  HistoryLog(
    id: 'hist-001',
    type: 'DETECTION',
    action: 'Live Scan: ANN7569',
    plate: 'ANN7569',
    details: 'Exact match from scanner reference data.',
    userRole: Role.admin,
    timestamp: _dt('2026-08-01T04:30:00Z'),
    statusMatch: 'EXACT',
    cameraId: 'native-back',
    cameraName: 'Rear Camera',
  ),
  HistoryLog(
    id: 'hist-002',
    type: 'SEARCH',
    action: 'Manual Search: QAA1234',
    plate: 'QAA1234',
    details: 'Sarawak plate manual search.',
    userRole: Role.user,
    timestamp: _dt('2026-08-01T04:15:00Z'),
    statusMatch: 'EXACT',
  ),
];
