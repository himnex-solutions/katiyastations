// ============================================================
// KATIYA STATION RMS — CURRENT BRANCH INFO
// Branch identity (name, address, phone, tax reg. no.) for anything
// that needs to print it — bill receipts, KOT tickets, etc.
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final currentBranchProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final branchId = ref.watch(authNotifierProvider).value?.branchId;
  if (branchId == null) return null;
  final response = await ApiClient.instance.get(ApiConstants.branchById(branchId));
  return response.data as Map<String, dynamic>?;
});
