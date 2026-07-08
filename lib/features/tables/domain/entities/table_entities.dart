import 'package:equatable/equatable.dart';

// ─── Table Status Constants ────────────────────────────────────────────────
class TableStatus {
  static const String available = 'available';
  static const String occupied = 'occupied';
  static const String reserved = 'reserved';
  static const String readyForBilling = 'ready_for_billing';
  static const String closed = 'closed'; // disabled
}

// ─── Session Status Constants ──────────────────────────────────────────────
class SessionStatus {
  static const String open = 'open';
  static const String billed = 'billed';
  static const String closed = 'closed';
}

// ─── RestaurantTable Entity ────────────────────────────────────────────────
class RestaurantTable extends Equatable {
  final String id;
  final String branchId;
  final String tableNumber;
  final String section; // floor name
  final int capacity;
  final String status;
  final String? currentSessionId;
  final bool billRequested;
  final DateTime? billRequestedAt;
  final String? description;
  final bool isEnabled;
  final DateTime? createdAt;

  const RestaurantTable({
    required this.id,
    required this.branchId,
    required this.tableNumber,
    required this.section,
    required this.capacity,
    required this.status,
    this.currentSessionId,
    this.billRequested = false,
    this.billRequestedAt,
    this.description,
    this.isEnabled = true,
    this.createdAt,
  });

  factory RestaurantTable.fromJson(Map<String, dynamic> json) {
    return RestaurantTable(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      tableNumber: json['table_number'] as String,
      section: json['section'] as String? ?? 'Main',
      capacity: json['capacity'] as int? ?? 4,
      status: json['status'] as String? ?? TableStatus.available,
      currentSessionId: json['current_session_id'] as String?,
      billRequested: json['bill_requested'] as bool? ?? false,
      billRequestedAt: json['bill_requested_at'] != null
          ? DateTime.parse(json['bill_requested_at'] as String)
          : null,
      description: json['description'] as String?,
      isEnabled: json['is_enabled'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'branch_id': branchId,
        'table_number': tableNumber,
        'section': section,
        'capacity': capacity,
        'status': status,
        'bill_requested': billRequested,
        'bill_requested_at': billRequestedAt?.toIso8601String(),
        'description': description,
        'is_enabled': isEnabled,
      };

  RestaurantTable copyWith({
    String? status,
    String? currentSessionId,
    bool? billRequested,
    DateTime? billRequestedAt,
    bool? isEnabled,
    String? description,
    String? tableNumber,
    String? section,
    int? capacity,
  }) {
    return RestaurantTable(
      id: id,
      branchId: branchId,
      tableNumber: tableNumber ?? this.tableNumber,
      section: section ?? this.section,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      billRequested: billRequested ?? this.billRequested,
      billRequestedAt: billRequestedAt ?? this.billRequestedAt,
      description: description ?? this.description,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt,
    );
  }

  bool get isAvailable => status == TableStatus.available && isEnabled;
  bool get isOccupied => status == TableStatus.occupied;
  bool get isReserved => status == TableStatus.reserved;
  bool get isReadyForBilling => status == TableStatus.readyForBilling || billRequested;
  bool get isDisabled => !isEnabled || status == TableStatus.closed;

  @override
  List<Object?> get props => [
        id,
        tableNumber,
        status,
        section,
        currentSessionId,
        billRequested,
        billRequestedAt,
        isEnabled,
      ];
}

// ─── TableSession Entity ───────────────────────────────────────────────────
class TableSession extends Equatable {
  final String id;
  final String tableId;
  final String branchId;
  final String sessionNumber;
  final String status;
  final String? waiterId;
  final String? waiterName;
  final String? customerId;
  final int guestCount;
  final double totalAmount;
  final DateTime openedAt;
  final DateTime? closedAt;
  final bool billRequested;
  final DateTime? billRequestedAt;
  final String? notes;
  final bool onHold;
  final String? holdReason;

  const TableSession({
    required this.id,
    required this.tableId,
    required this.branchId,
    required this.sessionNumber,
    required this.status,
    this.waiterId,
    this.waiterName,
    this.customerId,
    this.guestCount = 1,
    this.totalAmount = 0,
    required this.openedAt,
    this.closedAt,
    this.billRequested = false,
    this.billRequestedAt,
    this.notes,
    this.onHold = false,
    this.holdReason,
  });

  factory TableSession.fromJson(Map<String, dynamic> json) {
    return TableSession(
      id: json['id'] as String,
      tableId: json['table_id'] as String,
      branchId: json['branch_id'] as String,
      sessionNumber: json['session_number'] as String,
      status: json['status'] as String? ?? SessionStatus.open,
      waiterId: json['waiter_id'] as String?,
      waiterName: json['waiter_name'] as String?,
      customerId: json['customer_id'] as String?,
      guestCount: json['guest_count'] as int? ?? 1,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      openedAt: DateTime.parse(json['opened_at'] as String),
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      billRequested: json['bill_requested'] as bool? ?? false,
      billRequestedAt: json['bill_requested_at'] != null
          ? DateTime.parse(json['bill_requested_at'] as String)
          : null,
      notes: json['notes'] as String?,
      onHold: json['on_hold'] as bool? ?? false,
      holdReason: json['hold_reason'] as String?,
    );
  }

  Duration get duration => DateTime.now().difference(openedAt);

  String get durationLabel {
    final d = duration;
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  bool get isOpen => status == SessionStatus.open;
  bool get isClosed => status == SessionStatus.closed;
  bool get isBilled => status == SessionStatus.billed;

  @override
  List<Object?> get props => [
        id,
        tableId,
        sessionNumber,
        status,
        totalAmount,
        billRequested,
        billRequestedAt,
        guestCount,
        onHold,
      ];
}

// ─── Reservation Entity ────────────────────────────────────────────────────
class TableReservation extends Equatable {
  final String id;
  final String branchId;
  final String? tableId;
  final String? tableNumber;
  final String customerName;
  final String? customerPhone;
  final int guestCount;
  final DateTime reservationTime;
  final String status; // pending, confirmed, seated, cancelled, no_show
  final String? notes;
  final DateTime? createdAt;

  const TableReservation({
    required this.id,
    required this.branchId,
    this.tableId,
    this.tableNumber,
    required this.customerName,
    this.customerPhone,
    required this.guestCount,
    required this.reservationTime,
    required this.status,
    this.notes,
    this.createdAt,
  });

  factory TableReservation.fromJson(Map<String, dynamic> json) {
    return TableReservation(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      tableId: json['table_id'] as String?,
      tableNumber: json['table_number'] as String?,
      customerName: json['customer_name'] as String? ?? 'Guest',
      customerPhone: json['customer_phone'] as String?,
      guestCount: json['guest_count'] as int? ?? 2,
      reservationTime: DateTime.parse(json['reservation_time'] as String),
      status: json['status'] as String? ?? 'confirmed',
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'branch_id': branchId,
        'table_id': tableId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'guest_count': guestCount,
        'reservation_time': reservationTime.toIso8601String(),
        'status': status,
        'notes': notes,
      };

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isSeated => status == 'seated';
  bool get isCancelled => status == 'cancelled';
  bool get isNoShow => status == 'no_show';

  bool get isUpcoming =>
      reservationTime.isAfter(DateTime.now()) && !isCancelled && !isNoShow;
  bool get isToday {
    final now = DateTime.now();
    return reservationTime.year == now.year &&
        reservationTime.month == now.month &&
        reservationTime.day == now.day;
  }

  @override
  List<Object?> get props => [id, tableId, customerName, reservationTime, status];
}
