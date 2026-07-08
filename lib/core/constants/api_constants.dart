// ============================================================
// KATIYA STATION RMS — API CONSTANTS
// Self-hosted NestJS Backend Configuration
// ============================================================

class ApiConstants {
  ApiConstants._();

  // ── Base URLs ──────────────────────────────────────────────
  // Change this to your VPS domain/IP once deployed
  // Development: http://localhost:3000
  // Production:  https://api.katiyastation.com
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String wsUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String apiVersion = '/api/v1';
  static String get apiBase => '$baseUrl$apiVersion';

  // ── Auth Endpoints ─────────────────────────────────────────
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';
  static const String changePassword = '/auth/change-password';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';

  // ── Branch Endpoints ───────────────────────────────────────
  static const String branches = '/branches';
  static String branchById(String id) => '/branches/$id';

  // ── User / Staff Profile Endpoints ────────────────────────
  static const String users = '/users';
  static String userById(String id) => '/users/$id';
  static String toggleUserActive(String id) => '/users/$id/toggle-active';
  static String resetUserPassword(String id) => '/users/$id/reset-password';

  // ── Restaurant Tables Endpoints ────────────────────────────
  static const String tables = '/tables';
  static String tableById(String id) => '/tables/$id';
  static String tableSessions(String tableId) => '/tables/$tableId/sessions';
  static String currentSession(String tableId) => '/tables/$tableId/current-session';
  static String requestBill(String tableId) => '/tables/$tableId/request-bill';
  static String transferSession(String tableId) => '/tables/$tableId/transfer-session';

  // ── Table Sessions ─────────────────────────────────────────
  static const String sessions = '/sessions';
  static String sessionById(String id) => '/sessions/$id';
  static String openSession(String tableId) => '/tables/$tableId/open';
  static String closeSession(String sessionId) => '/sessions/$sessionId/close';
  static String holdSession(String sessionId) => '/sessions/$sessionId/hold';
  static String unholdSession(String sessionId) => '/sessions/$sessionId/unhold';
  static String mergeSession(String sessionId) => '/sessions/$sessionId/merge';
  static String splitSession(String sessionId) => '/sessions/$sessionId/split';

  // ── KOT (Kitchen Order Ticket) Endpoints ──────────────────
  static const String kots = '/kots';
  static String kotById(String id) => '/kots/$id';
  static String kotsBySession(String sessionId) => '/sessions/$sessionId/kots';
  static String updateKotStatus(String kotId) => '/kots/$kotId/status';
  static String kotItems(String kotId) => '/kots/$kotId/items';
  static String updateKotItemQuantity(String itemId) => '/kots/items/$itemId/quantity';
  static String updateKotItemStatus(String kotId, String itemId) => '/kots/$kotId/items/$itemId/status';
  static String printKot(String kotId) => '/kots/$kotId/print';
  static String returnKotItem(String kotId, String itemId) => '/kots/$kotId/items/$itemId/return';

  // ── Menu Endpoints ─────────────────────────────────────────
  static const String menuCategories = '/menu/categories';
  static String menuCategoryById(String id) => '/menu/categories/$id';
  static const String menuItems = '/menu/items';
  static String menuItemById(String id) => '/menu/items/$id';
  static const String menuImportExcel = '/menu/import/excel';
  static String menuByBranch(String branchId) => '/menu/branch/$branchId';
  static String menuItemRecipe(String itemId) => '/menu/items/$itemId/recipe';
  static String recipeById(String id) => '/menu/recipes/$id';
  static String recipeIngredients(String recipeId) => '/menu/recipes/$recipeId/ingredients';
  static String recipeIngredientById(String id) => '/menu/recipe-ingredients/$id';

  // ── Billing Endpoints ──────────────────────────────────────
  static const String bills = '/billing/bills';
  static String billById(String id) => '/billing/bills/$id';
  static String generateBill(String sessionId) => '/billing/sessions/$sessionId/generate';
  static const String paymentHistory = '/billing/payment-history';

  // ── Credit (Udhaaro) Endpoints ─────────────────────────────
  static const String credits = '/credit';
  static String creditById(String id) => '/credit/$id';
  static String settleCredit(String id) => '/credit/$id/settle';

  // ── Inventory Endpoints ────────────────────────────────────
  static const String inventory = '/inventory';
  static String inventoryById(String id) => '/inventory/$id';
  static String adjustStock(String id) => '/inventory/$id/adjust';
  static const String stockMovements = '/inventory/movements';

  // ── Bar Endpoints ──────────────────────────────────────────
  static const String barStock = '/bar/stock';
  static String barStockById(String id) => '/bar/stock/$id';
  static const String barTransactions = '/bar/transactions';
  static String barDispense(String id) => '/bar/stock/$id/dispense';

  // ── Purchase Endpoints ─────────────────────────────────────
  static const String purchases = '/purchases';
  static String purchaseById(String id) => '/purchases/$id';
  static String purchaseItems(String purchaseId) => '/purchases/$purchaseId/items';

  // ── Supplier Endpoints ─────────────────────────────────────
  static const String suppliers = '/suppliers';
  static String supplierById(String id) => '/suppliers/$id';

  // ── Expense Endpoints ──────────────────────────────────────
  static const String expenses = '/expenses';
  static String expenseById(String id) => '/expenses/$id';

  // ── Customer Endpoints ─────────────────────────────────────
  static const String customers = '/customers';
  static String customerById(String id) => '/customers/$id';
  static String customerByPhone(String phone) => '/customers/phone/$phone';

  // ── Reservation Endpoints ──────────────────────────────────
  static const String reservations = '/reservations';
  static String reservationById(String id) => '/reservations/$id';
  static String updateReservationStatus(String id) => '/reservations/$id/status';

  // ── Loyalty Endpoints ──────────────────────────────────────
  static const String loyalty = '/loyalty';
  static String earnPoints(String customerId) => '/loyalty/$customerId/earn';
  static String redeemPoints(String customerId) => '/loyalty/$customerId/redeem';
  static String loyaltyHistory(String customerId) => '/loyalty/$customerId/history';
  static const String loyaltyRecent = '/loyalty/recent';

  // ── Staff Endpoints ────────────────────────────────────────
  static const String staff = '/staff';
  static const String myStaffRecord = '/staff/me';
  static String staffById(String id) => '/staff/$id';

  // ── Attendance Endpoints ───────────────────────────────────
  static const String attendance = '/attendance';
  static String attendanceById(String id) => '/attendance/$id';
  static String clockIn(String staffId) => '/attendance/$staffId/clock-in';
  static String clockOut(String staffId) => '/attendance/$staffId/clock-out';
  static String attendanceByStaff(String staffId) => '/attendance/staff/$staffId';
  static String attendanceToday(String staffId) => '/attendance/staff/$staffId/today';

  // ── Payroll Endpoints ──────────────────────────────────────
  static const String payroll = '/payroll';
  static String payrollById(String id) => '/payroll/$id';
  static String generateSalary(String staffId) => '/payroll/$staffId/generate';

  // ── Shift Closing Endpoints ────────────────────────────────
  static const String shiftClosing = '/shift-closing';
  static const String shiftTodaySummary = '/shift-closing/today-summary';
  static String shiftById(String id) => '/shift-closing/$id';
  static String approveShift(String id) => '/shift-closing/$id/approve';
  static String rejectShift(String id) => '/shift-closing/$id/reject';

  // ── Reports Endpoints ──────────────────────────────────────
  static const String reports = '/reports';
  static const String reportSummary = '/reports/summary';
  static const String salesReport = '/reports/sales';
  static const String inventoryReport = '/reports/inventory';
  static const String staffReport = '/reports/staff';
  static const String revenueReport = '/reports/revenue';
  static const String dashboardSummary = '/reports/dashboard';

  // ── Notification Endpoints ─────────────────────────────────
  static const String notifications = '/notifications';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static const String markAllRead = '/notifications/mark-all-read';
  static const String fcmToken = '/notifications/fcm-token';

  // ── Audit Log Endpoints ────────────────────────────────────
  static const String auditLogs = '/audit-logs';

  // ── Super Admin Endpoints ──────────────────────────────────
  static const String superAdminHealth = '/super-admin/health';
  static const String superAdminRedis = '/super-admin/redis';
  static const String superAdminDatabase = '/super-admin/database';
  static const String superAdminBackup = '/super-admin/backup';
  static const String superAdminRestore = '/super-admin/restore';
  static const String superAdminLogs = '/super-admin/logs';
  static const String superAdminContainers = '/super-admin/containers';

  // ── Uploads ────────────────────────────────────────────────
  static const String uploads = '/uploads';
  static String uploadMenuItemImage(String itemId) => '/uploads/menu-items/$itemId';

  // ── Request Timeouts ──────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // ── Pagination Defaults ────────────────────────────────────
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
}
