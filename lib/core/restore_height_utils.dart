/// Parse and validate blockchain restore / scan-from heights.
class RestoreHeightUtils {
  /// Matches native `kScanHeightMargin` in zentra_wallet_ffi.cpp.
  static const int daemonTipMargin = 12;

  /// Scan start for a brand-new wallet (near chain tip, not genesis).
  static int scanHeightFromDaemonTip(int daemonHeight) {
    if (daemonHeight <= 0) return 0;
    return daemonHeight > daemonTipMargin ? daemonHeight - daemonTipMargin : 0;
  }

  /// Matches native [persist_scan_checkpoint] — never ahead of wallet scan progress.
  static int scanCheckpointFromProgress({
    required int walletHeight,
    required int daemonHeight,
  }) {
    if (walletHeight <= 0 || daemonHeight <= 0) return 0;
    if (walletHeight + daemonTipMargin >= daemonHeight) {
      return scanHeightFromDaemonTip(daemonHeight);
    }
    return walletHeight > daemonTipMargin ? walletHeight - daemonTipMargin : 0;
  }

  static int? parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final n = int.tryParse(t);
    if (n == null || n < 0) return null;
    return n;
  }

  static String format(int height) => height <= 0 ? '' : height.toString();

  /// Human label for the scan-from height stored in the wallet file.
  static String describeScanStart({
    required int scanHeight,
    required int walletHeight,
    required int daemonHeight,
    required bool isSynced,
  }) {
    if (scanHeight > 0) {
      return 'Block $scanHeight';
    }
    if (walletHeight <= 0 && daemonHeight <= 0) {
      return 'Waiting for node…';
    }
    if (walletHeight <= 0) {
      return 'First sync from genesis';
    }
    if (isSynced) {
      return 'Saving checkpoint…';
    }
    return 'Syncing from genesis (block 0)';
  }

  /// Settings list subtitle for restore / sync height.
  static String settingsSubtitle({
    required bool connected,
    required int scanHeight,
    required int walletHeight,
    required int defaultRestoreHeight,
    required bool isSynced,
  }) {
    if (connected) {
      if (scanHeight > 0) {
        return 'Wallet resumes from block $scanHeight';
      }
      if (walletHeight > 0 && isSynced) {
        return 'Synced to block $walletHeight';
      }
      if (walletHeight > 0) {
        return 'Syncing — scanned to block $walletHeight';
      }
      return 'Waiting for first sync';
    }
    if (defaultRestoreHeight > 0) {
      return 'Default for restore: block $defaultRestoreHeight';
    }
    return 'Scan start block & resync';
  }

  /// True when wallet is caught up but scan checkpoint was never written (legacy files).
  static bool needsScanCheckpointRepair({
    required int scanHeight,
    required int walletHeight,
    required int daemonHeight,
    required bool isSynced,
  }) {
    if (!isSynced || scanHeight > 0 || walletHeight <= 0 || daemonHeight <= 0) {
      return false;
    }
    return true;
  }
}
