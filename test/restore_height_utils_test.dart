import 'package:flutter_test/flutter_test.dart';
import 'package:zentra_wallet/core/restore_height_utils.dart';
import 'package:zentra_wallet/models/wallet_sync_status.dart';

void main() {
  group('RestoreHeightUtils', () {
    test('scanHeightFromDaemonTip subtracts margin', () {
      expect(RestoreHeightUtils.scanHeightFromDaemonTip(1000), 988);
      expect(RestoreHeightUtils.scanHeightFromDaemonTip(5), 0);
    });

    test('scanCheckpointFromProgress stays behind wallet height while syncing', () {
      expect(
        RestoreHeightUtils.scanCheckpointFromProgress(
          walletHeight: 999_950,
          daemonHeight: 1_000_000,
        ),
        999_938,
      );
    });

    test('scanCheckpointFromProgress uses tip when caught up', () {
      expect(
        RestoreHeightUtils.scanCheckpointFromProgress(
          walletHeight: 999_995,
          daemonHeight: 1_000_000,
        ),
        999_988,
      );
    });

    test('describeScanStart shows saved checkpoint', () {
      expect(
        RestoreHeightUtils.describeScanStart(
          scanHeight: 2500000,
          walletHeight: 2500100,
          daemonHeight: 2500100,
          isSynced: true,
        ),
        'Block 2500000',
      );
    });

    test('describeScanStart explains missing checkpoint while synced', () {
      expect(
        RestoreHeightUtils.describeScanStart(
          scanHeight: 0,
          walletHeight: 2500100,
          daemonHeight: 2500100,
          isSynced: true,
        ),
        'Saving checkpoint…',
      );
    });

    test('needsScanCheckpointRepair requires synced legacy wallet', () {
      expect(
        RestoreHeightUtils.needsScanCheckpointRepair(
          scanHeight: 0,
          walletHeight: 999_950,
          daemonHeight: 1_000_000,
          isSynced: 999_950 + kWalletSyncedBlocksThreshold >= 1_000_000,
        ),
        isTrue,
      );
      expect(
        RestoreHeightUtils.needsScanCheckpointRepair(
          scanHeight: 0,
          walletHeight: 999_000,
          daemonHeight: 1_000_000,
          isSynced: false,
        ),
        isFalse,
      );
      expect(
        RestoreHeightUtils.needsScanCheckpointRepair(
          scanHeight: 2500000,
          walletHeight: 2500100,
          daemonHeight: 2500100,
          isSynced: true,
        ),
        isFalse,
      );
    });

    test('settingsSubtitle prefers wallet scan height when connected', () {
      expect(
        RestoreHeightUtils.settingsSubtitle(
          connected: true,
          scanHeight: 2400000,
          walletHeight: 2500000,
          defaultRestoreHeight: 0,
          isSynced: true,
        ),
        'Wallet resumes from block 2400000',
      );
    });
  });
}
