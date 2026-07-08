// ============================================================
// KATIYA STATION RMS — SECURE STORAGE SERVICE
// Replaces Supabase session management with JWT tokens
// stored in flutter_secure_storage (encrypted on-device)
// ============================================================

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  SecureStorage._();
  static final SecureStorage instance = SecureStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    wOptions: WindowsOptions(),
  );

  // ── Key Names ──────────────────────────────────────────────
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kUserRole = 'user_role';
  static const _kBranchId = 'branch_id';
  static const _kUserFullName = 'user_full_name';
  static const _kFcmToken = 'fcm_token';

  // ── Access Token ───────────────────────────────────────────
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _kAccessToken, value: token);
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: _kAccessToken);
  }

  // ── Refresh Token ──────────────────────────────────────────
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _kRefreshToken, value: token);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _kRefreshToken);
  }

  // ── User Info ──────────────────────────────────────────────
  Future<void> saveUserSession({
    required String userId,
    required String role,
    required String fullName,
    String? branchId,
  }) async {
    await Future.wait([
      _storage.write(key: _kUserId, value: userId),
      _storage.write(key: _kUserRole, value: role),
      _storage.write(key: _kUserFullName, value: fullName),
      if (branchId != null)
        _storage.write(key: _kBranchId, value: branchId),
    ]);
  }

  Future<String?> getUserId() => _storage.read(key: _kUserId);
  Future<String?> getUserRole() => _storage.read(key: _kUserRole);
  Future<String?> getUserFullName() => _storage.read(key: _kUserFullName);
  Future<String?> getBranchId() => _storage.read(key: _kBranchId);

  // ── FCM Token ──────────────────────────────────────────────
  Future<void> saveFcmToken(String token) async {
    await _storage.write(key: _kFcmToken, value: token);
  }

  Future<String?> getFcmToken() => _storage.read(key: _kFcmToken);

  // ── Session Check ──────────────────────────────────────────
  Future<bool> hasValidSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Clear All (Logout) ─────────────────────────────────────
  Future<void> clearSession() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
      _storage.delete(key: _kUserRole),
      _storage.delete(key: _kUserFullName),
      _storage.delete(key: _kBranchId),
    ]);
  }

  /// Clears everything including FCM token (full device wipe)
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
