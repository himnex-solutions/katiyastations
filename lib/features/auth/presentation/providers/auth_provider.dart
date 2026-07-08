// ============================================================
// KATIYA STATION RMS — AUTH PROVIDER
// JWT-based authentication against NestJS backend
// Replaces all Supabase Auth calls
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/user_profile.dart';

// ── Auth Notifier State ─────────────────────────────────────
class AuthState {
  final UserProfile? profile;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get isAuthenticated => profile != null;
  String? get role => profile?.role;

  AuthState copyWith({
    UserProfile? profile,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool clearProfile = false,
  }) {
    return AuthState(
      profile: clearProfile ? null : (profile ?? this.profile),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Auth Notifier ───────────────────────────────────────────
class AuthNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  AuthNotifier() : super(const AsyncValue.loading()) {
    _loadCurrentProfile();
  }

  // ── Load stored session on app start ──────────────────────
  Future<void> _loadCurrentProfile() async {
    try {
      final hasSession = await SecureStorage.instance.hasValidSession();
      if (!hasSession) {
        state = const AsyncValue.data(null);
        return;
      }

      // Validate token by fetching profile from /auth/me
      final response = await ApiClient.instance.get(ApiConstants.me);

      if (response.statusCode == 200 && response.data != null) {
        final profile = UserProfile.fromJson(
          response.data as Map<String, dynamic>,
        );

        if (!profile.isActive) {
          await SecureStorage.instance.clearSession();
          state = const AsyncValue.data(null);
          return;
        }

        state = AsyncValue.data(profile);

        // Connect socket for realtime after restoring session
        if (profile.branchId != null) {
          await SocketClient.instance.connect();
          SocketClient.instance.joinBranchRoom(profile.branchId!);
        }
      } else {
        // Token invalid or expired — clear and require login
        await SecureStorage.instance.clearSession();
        state = const AsyncValue.data(null);
      }
    } catch (e) {
      // Network error on startup — stay logged in with cached data if possible
      final userId = await SecureStorage.instance.getUserId();
      final role = await SecureStorage.instance.getUserRole();
      final name = await SecureStorage.instance.getUserFullName();
      final branchId = await SecureStorage.instance.getBranchId();

      if (userId != null && role != null && name != null) {
        // Restore from cached user data for offline mode
        state = AsyncValue.data(UserProfile(
          id: userId,
          fullName: name,
          role: role,
          branchId: branchId,
          isActive: true,
          createdAt: DateTime.now(),
        ));
      } else {
        state = const AsyncValue.data(null);
      }
    }
  }

  // ── Sign In ────────────────────────────────────────────────
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();

    try {
      final response = await ApiClient.instance.post(
        ApiConstants.login,
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        // Extract tokens
        final accessToken = data['accessToken'] as String?;
        final refreshToken = data['refreshToken'] as String?;

        if (accessToken == null || refreshToken == null) {
          state = AsyncValue.error(
            'Invalid server response. Please contact support.',
            StackTrace.current,
          );
          return;
        }

        // Extract user profile from response
        final userData = data['user'] as Map<String, dynamic>?;
        if (userData == null) {
          state = AsyncValue.error(
            'User data not received. Please contact support.',
            StackTrace.current,
          );
          return;
        }

        final profile = UserProfile.fromJson(userData);

        if (!profile.isActive) {
          state = AsyncValue.error(
            'Your account has been deactivated. Contact your administrator.',
            StackTrace.current,
          );
          return;
        }

        // Save tokens + session
        await SecureStorage.instance.saveAccessToken(accessToken);
        await SecureStorage.instance.saveRefreshToken(refreshToken);
        await SecureStorage.instance.saveUserSession(
          userId: profile.id,
          role: profile.role,
          fullName: profile.fullName,
          branchId: profile.branchId,
        );

        state = AsyncValue.data(profile);

        // Connect WebSocket after login
        await SocketClient.instance.connect();
        if (profile.branchId != null) {
          SocketClient.instance.joinBranchRoom(profile.branchId!);
        }
      } else {
        final data = response.data as Map<String, dynamic>?;
        final message = data?['message'] as String? ?? 'Login failed.';
        state = AsyncValue.error(message, StackTrace.current);
      }
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
    } on NetworkException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
    } on ApiException catch (e) {
      String message;
      if (e.statusCode == 401) {
        message = 'Invalid email or password. Please try again.';
      } else if (e.statusCode == 403) {
        message = 'Your account has been deactivated. Contact your administrator.';
      } else if (e.statusCode == 429) {
        message = 'Too many login attempts. Please wait and try again.';
      } else {
        message = e.message;
      }
      state = AsyncValue.error(message, StackTrace.current);
    } catch (e) {
      state = AsyncValue.error(
        'An unexpected error occurred. Please try again.',
        StackTrace.current,
      );
    }
  }

  // ── Sign Out ───────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      // Notify server to invalidate refresh token
      await ApiClient.instance.post(ApiConstants.logout);
    } catch (_) {
      // Ignore errors on logout — clean up client side regardless
    } finally {
      // Disconnect socket
      SocketClient.instance.disconnect();

      // Clear all local storage
      await SecureStorage.instance.clearSession();

      state = const AsyncValue.data(null);
    }
  }

  // ── Change Password ────────────────────────────────────────
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await ApiClient.instance.post(
      ApiConstants.changePassword,
      data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  // ── Refresh profile ────────────────────────────────────────
  Future<void> refreshProfile() async {
    try {
      final response = await ApiClient.instance.get(ApiConstants.me);
      if (response.statusCode == 200) {
        final profile = UserProfile.fromJson(
          response.data as Map<String, dynamic>,
        );
        state = AsyncValue.data(profile);
      }
    } catch (_) {}
  }
}

// ── Providers ──────────────────────────────────────────────

/// Primary auth state provider — replaces all Supabase auth providers
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserProfile?>>(
  (ref) => AuthNotifier(),
);

/// Convenience provider for the current user profile
final currentProfileProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authNotifierProvider).value;
});

/// Role provider
final userRoleProvider = Provider<String?>((ref) {
  return ref.watch(currentProfileProvider)?.role;
});

/// Branch ID provider
final currentBranchIdProvider = Provider<String?>((ref) {
  return ref.watch(currentProfileProvider)?.branchId;
});

/// Is authenticated check
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentProfileProvider) != null;
});
