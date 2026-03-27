import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../api/proxy_channel.dart';

/// Certificate trust status.
enum CertStatus { none, installed, trusted, checking }

/// Manages CA certificate status, installation, and export.
class CertController extends GetxController {
  final status = CertStatus.checking.obs;
  final certPath = ''.obs;

  @override
  void onInit() {
    super.onInit();
    checkStatus();
  }

  /// Check current cert trust status via platform channel.
  Future<void> checkStatus() async {
    status.value = CertStatus.checking;
    try {
      final result = await ProxyChannel.getCertStatus();
      final s = result['status'] as String? ?? 'none';
      certPath.value = result['path'] as String? ?? '';
      status.value = switch (s) {
        'trusted' => CertStatus.trusted,
        'installed' => CertStatus.installed,
        _ => CertStatus.none,
      };
    } catch (e) {
      debugPrint('[Knot] Cert status check failed: $e');
      status.value = CertStatus.none;
    }
  }

  /// Install cert to Keychain and trust. Triggers system password dialog.
  Future<bool> install() async {
    try {
      final result = await ProxyChannel.installCert();
      final s = result['status'] as String? ?? '';
      if (s == 'trusted') {
        status.value = CertStatus.trusted;
        return true;
      } else if (s == 'installed') {
        status.value = CertStatus.installed;
        return false; // Installed but user cancelled trust
      }
    } catch (e) {
      debugPrint('[Knot] Cert install failed: $e');
    }
    return false;
  }

  /// Export CA cert DER to a user-chosen file.
  Future<bool> exportToFile(String savePath) async {
    try {
      final bytes = await ProxyChannel.exportCertDER();
      if (bytes == null || bytes.isEmpty) return false;
      await File(savePath).writeAsBytes(bytes);
      return true;
    } catch (e) {
      debugPrint('[Knot] Cert export failed: $e');
      return false;
    }
  }
}
