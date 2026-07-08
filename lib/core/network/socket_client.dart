// ============================================================
// KATIYA STATION RMS — SOCKET.IO CLIENT
// Replaces Supabase Realtime with Socket.IO + Redis Pub/Sub
// Handles: KOT updates, table status, live kitchen, billing
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/api_constants.dart';
import '../storage/secure_storage.dart';

/// Socket event names — must match the backend gateway
class SocketEvents {
  SocketEvents._();

  // KOT events
  static const String kotNew = 'kot:new';
  static const String kotUpdated = 'kot:updated';
  static const String kotStatusChanged = 'kot:status_changed';

  // Table / Session events
  static const String tableStatusChanged = 'table:status_changed';
  static const String sessionOpened = 'session:opened';
  static const String sessionClosed = 'session:closed';

  // Order events
  static const String orderItemAdded = 'order:item_added';
  static const String orderItemCancelled = 'order:item_cancelled';

  // Billing events
  static const String billGenerated = 'bill:generated';
  static const String billPaid = 'bill:paid';

  // Inventory events
  static const String inventoryLowStock = 'inventory:low_stock';

  // Notification events
  static const String notificationNew = 'notification:new';

  // Shift events
  static const String shiftClosed = 'shift:closed';
  static const String shiftApproved = 'shift:approved';

  // Waiter / table-move events
  static const String tableTransferred = 'table:transferred';
  static const String waiterAssigned = 'session:waiter_assigned';

  // Branch user account events (add / edit / block / delete)
  static const String userChanged = 'user:changed';

  // Purchase events (recorded spend → daily report)
  static const String purchaseCreated = 'purchase:created';
}

/// Room name builders — must match the backend gateway
class SocketRooms {
  SocketRooms._();
  static String branch(String branchId) => 'branch:$branchId';
  static String table(String tableId) => 'table:$tableId';
  static String kitchen(String branchId) => 'kitchen:$branchId';
}

class SocketClient {
  SocketClient._();
  static final SocketClient instance = SocketClient._();

  io.Socket? _socket;
  final _eventControllers = <String, StreamController<dynamic>>{};
  bool _isConnected = false;
  String? _currentBranchId;

  // ── Public state ───────────────────────────────────────────
  bool get isConnected => _isConnected;

  // ── Connect (called after successful login) ────────────────
  Future<void> connect() async {
    if (_socket != null && _isConnected) return;

    final token = await SecureStorage.instance.getAccessToken();
    if (token == null) return;

    _socket = io.io(
      '${ApiConstants.wsUrl}/rms',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('[SocketClient] Connected to /rms');

      // Re-join branch room after reconnect
      if (_currentBranchId != null) {
        joinBranchRoom(_currentBranchId!);
      }
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('[SocketClient] Disconnected');
    });

    _socket!.onConnectError((err) {
      debugPrint('[SocketClient] Connection error: $err');
    });

    _socket!.onError((err) {
      debugPrint('[SocketClient] Error: $err');
    });

    // Forward all known events to their stream controllers
    for (final event in _allEvents) {
      _socket!.on(event, (data) => _emit(event, data));
    }

    _socket!.connect();
  }

  // ── Room Management ────────────────────────────────────────
  void joinBranchRoom(String branchId) {
    _currentBranchId = branchId;
    _socket?.emit('join_room', SocketRooms.branch(branchId));
    _socket?.emit('join_room', SocketRooms.kitchen(branchId));
    debugPrint('[SocketClient] Joined branch room: $branchId');
  }

  void joinTableRoom(String tableId) {
    _socket?.emit('join_room', SocketRooms.table(tableId));
    debugPrint('[SocketClient] Joined table room: $tableId');
  }

  void leaveTableRoom(String tableId) {
    _socket?.emit('leave_room', SocketRooms.table(tableId));
  }

  void leaveBranchRoom(String branchId) {
    _socket?.emit('leave_room', SocketRooms.branch(branchId));
    _socket?.emit('leave_room', SocketRooms.kitchen(branchId));
  }

  // ── Event Streams ──────────────────────────────────────────
  Stream<dynamic> on(String event) {
    if (!_eventControllers.containsKey(event)) {
      _eventControllers[event] = StreamController<dynamic>.broadcast();
    }
    return _eventControllers[event]!.stream;
  }

  /// Convenience typed stream helpers
  Stream<Map<String, dynamic>> onKotNew() =>
      on(SocketEvents.kotNew).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onKotUpdated() =>
      on(SocketEvents.kotUpdated).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onKotStatusChanged() =>
      on(SocketEvents.kotStatusChanged).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onTableStatusChanged() =>
      on(SocketEvents.tableStatusChanged).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onSessionOpened() =>
      on(SocketEvents.sessionOpened).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onSessionClosed() =>
      on(SocketEvents.sessionClosed).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onBillGenerated() =>
      on(SocketEvents.billGenerated).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onNotification() =>
      on(SocketEvents.notificationNew).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onLowStock() =>
      on(SocketEvents.inventoryLowStock).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onOrderItemCancelled() =>
      on(SocketEvents.orderItemCancelled).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onTableTransferred() =>
      on(SocketEvents.tableTransferred).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onWaiterAssigned() =>
      on(SocketEvents.waiterAssigned).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onUserChanged() =>
      on(SocketEvents.userChanged).map((d) => d as Map<String, dynamic>);

  Stream<Map<String, dynamic>> onPurchaseCreated() =>
      on(SocketEvents.purchaseCreated).map((d) => d as Map<String, dynamic>);

  // ── Emit (send event to server) ────────────────────────────
  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  // ── Disconnect (called on logout) ─────────────────────────
  void disconnect() {
    if (_currentBranchId != null) {
      leaveBranchRoom(_currentBranchId!);
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _currentBranchId = null;
    debugPrint('[SocketClient] Disconnected and disposed');
  }

  // ── Internal ───────────────────────────────────────────────
  void _emit(String event, dynamic data) {
    final controller = _eventControllers[event];
    if (controller != null && !controller.isClosed) {
      controller.add(data);
    }
  }

  void dispose() {
    for (final controller in _eventControllers.values) {
      controller.close();
    }
    _eventControllers.clear();
    disconnect();
  }

  static const List<String> _allEvents = [
    SocketEvents.kotNew,
    SocketEvents.kotUpdated,
    SocketEvents.kotStatusChanged,
    SocketEvents.tableStatusChanged,
    SocketEvents.sessionOpened,
    SocketEvents.sessionClosed,
    SocketEvents.orderItemAdded,
    SocketEvents.orderItemCancelled,
    SocketEvents.billGenerated,
    SocketEvents.billPaid,
    SocketEvents.inventoryLowStock,
    SocketEvents.notificationNew,
    SocketEvents.shiftClosed,
    SocketEvents.shiftApproved,
    SocketEvents.tableTransferred,
    SocketEvents.waiterAssigned,
    SocketEvents.userChanged,
    SocketEvents.purchaseCreated,
  ];
}
