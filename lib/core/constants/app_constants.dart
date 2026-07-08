class AppConstants {
  AppConstants._();

  static const String appName = 'Katiya Station RMS';
  static const String restaurantName = 'Katiya Station Restaurant & Bar';

  // User Roles
  static const String roleSuperAdmin = 'super_admin';
  static const String roleBranchManager = 'branch_manager';
  static const String roleCashier = 'cashier';
  static const String roleWaiter = 'waiter';
  static const String roleKitchen = 'kitchen';
  static const String roleInventory = 'inventory';
  static const String roleAccountant = 'accountant';

  // Table Statuses
  static const String tableAvailable = 'available';
  static const String tableOccupied = 'occupied';
  static const String tableReserved = 'reserved';
  static const String tableCleaning = 'cleaning';

  // Session Statuses
  static const String sessionOpen = 'open';
  static const String sessionClosed = 'closed';
  static const String sessionBilled = 'billed';

  // KOT Statuses
  static const String kotPending = 'pending';
  static const String kotPreparing = 'preparing';
  static const String kotReady = 'ready';
  static const String kotServed = 'served';
  static const String kotCancelled = 'cancelled';

  // Bill/Payment Statuses
  static const String paymentPaid = 'paid';
  static const String paymentPartial = 'partial_paid';
  static const String paymentCredit = 'credit';
  static const String paymentRefunded = 'refunded';

  // Credit Statuses
  static const String creditPending = 'pending';
  static const String creditPartial = 'partial_paid';
  static const String creditPaid = 'paid';
  static const String creditOverdue = 'overdue';

  // Reservation Statuses
  static const String reservationPending = 'pending';
  static const String reservationConfirmed = 'confirmed';
  static const String reservationArrived = 'arrived';
  static const String reservationCompleted = 'completed';
  static const String reservationCancelled = 'cancelled';
  static const String reservationNoShow = 'no_show';

  // Payment Methods
  static const String paymentCash = 'cash';
  static const String paymentCard = 'card';
  static const String paymentEsewa = 'esewa';
  static const String paymentKhalti = 'khalti';
  static const String paymentFonepay = 'fonepay';
  static const String paymentBankTransfer = 'bank_transfer';

  // VAT Rate (Nepal standard)
  static const double vatRate = 0.13;
  static const double serviceChargeRate = 0.10;

  // Loyalty
  static const double loyaltyPointsPerRupee = 0.01; // 1 pt per NPR 100
}
