import 'package:equatable/equatable.dart';

class Bill extends Equatable {
  final String id;
  final String branchId;
  final String sessionId;
  final String tableId;
  final String invoiceNumber;
  final String? cashierId;
  final String? cashierName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final double subtotal;
  final double discount;
  final double serviceCharge;
  final double vatAmount;
  final double totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final double amountPaid;
  final double changeAmount;
  final DateTime createdAt;

  const Bill({
    required this.id,
    required this.branchId,
    required this.sessionId,
    required this.tableId,
    required this.invoiceNumber,
    this.cashierId,
    this.cashierName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    this.discount = 0,
    this.serviceCharge = 0,
    required this.vatAmount,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.amountPaid,
    this.changeAmount = 0,
    required this.createdAt,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      sessionId: json['session_id'] as String,
      tableId: json['table_id'] as String,
      invoiceNumber: json['invoice_number'] as String,
      cashierId: json['cashier_id'] as String?,
      cashierName: json['cashier_name'] as String?,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      subtotal: (json['sub_total'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      serviceCharge: (json['service_charge'] as num?)?.toDouble() ?? 0,
      vatAmount: (json['vat_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String,
      paymentStatus: json['payment_status'] as String,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      changeAmount: (json['change_amount'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, invoiceNumber, paymentStatus];
}

class CreditRecord extends Equatable {
  final String id;
  final String branchId;
  final String billId;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;
  final double creditAmount;
  final double paidAmount;
  final String status; // pending | partial_paid | paid | overdue
  final DateTime? dueDate;
  final DateTime createdAt;

  const CreditRecord({
    required this.id,
    required this.branchId,
    required this.billId,
    this.customerId,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    required this.creditAmount,
    this.paidAmount = 0,
    required this.status,
    this.dueDate,
    required this.createdAt,
  });

  double get outstanding => creditAmount - paidAmount;
  bool get isOverdue => dueDate != null && DateTime.now().isAfter(dueDate!) && status != 'paid';

  factory CreditRecord.fromJson(Map<String, dynamic> json) {
    return CreditRecord(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      billId: json['bill_id'] as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      customerAddress: json['customer_address'] as String?,
      creditAmount: (json['credit_amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, customerName, creditAmount, status];
}
