import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/restore_height_utils.dart';
import '../../core/native_wallet_messages.dart';
import '../../models/wallet_models.dart';
import '../../providers/wallet_provider.dart' show WalletConnectionState, WalletProvider;
import '../../theme/zentra_theme.dart';
import '../network_ui.dart';
import '../widgets/zentra_ui.dart';
import 'node_setup_screen.dart';
import 'restore_sync_height_screen.dart';
import 'wallet_backup_screen.dart';
import 'wallets_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Selector<WalletProvider, _SettingsViewState>(
      selector: (_, wallet) => _SettingsViewState(
        connectionStatusLabel: wallet.connectionStatusLabel,
        connectionState: wallet.connectionState,
        showSyncBanner: wallet.showSyncBanner,
        isRefreshing: wallet.isRefreshing,
        errorMessage: wallet.errorMessage,
        isOpeningWallet: wallet.isOpeningWallet,
        syncBannerSubtitle: wallet.syncBannerSubtitle,
        syncProgressFraction: wallet.syncProgressFraction,
        primaryAddress: wallet.primaryAddress?.address,
        walletFilename: wallet.walletFilename,
        defaultRestoreHeight: wallet.defaultRestoreHeight,
        walletScanHeight: wallet.walletScanHeight,
        walletHeight: wallet.walletHeight,
        isSynced: wallet.isSynced,
        nodeSettings: wallet.nodeSettings,
        networkLabel: wallet.networkConfig?.label,
        nativeAvailable: wallet.nativeAvailable,
      ),
      builder: (context, state, _) {
        final wallet = context.read<WalletProvider>();

        final list = ListView(
          padding: EdgeInsets.only(bottom: ZentraTheme.navBarHeight + MediaQuery.paddingOf(context).bottom + 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: ZentraTheme.gradientCard(radius: ZentraTheme.radiusXl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ZentraConnectionChip(
                          label: state.connectionStatusLabel,
                          isError: state.connectionState == WalletConnectionState.error,
                          isSyncing: state.showSyncBanner,
                        ),
                        const Spacer(),
                        if (state.isRefreshing)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: ZentraTheme.primary),
                          ),
                      ],
                    ),
                    ZentraWalletStatusBanner(
                      compact: true,
                      errorMessage: zentraStatusErrorMessage(state.errorMessage),
                      isConnecting: state.isOpeningWallet,
                      isSyncing: state.showSyncBanner,
                      syncSubtitle: state.syncBannerSubtitle,
                      syncProgress: state.syncProgressFraction,
                    ),
                    if (state.primaryAddress != null) ...[
                      const SizedBox(height: 12),
                      ZentraAddressChip(address: state.primaryAddress!),
                    ],
                  ],
                ),
              ),
            ),
            ZentraSettingsSection(
              title: 'Wallet',
              children: [
                ZentraSettingsTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Wallets',
                  subtitle: state.walletFilename != null
                      ? 'Active: ${state.walletFilename}'
                      : 'Switch or add wallets',
                  showDivider: true,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletsScreen()),
                    );
                  },
                ),
                ZentraSettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Backup & seed phrase',
                  subtitle: state.connectionState == WalletConnectionState.connected
                      ? 'View address and seed to copy'
                      : 'Connect wallet first',
                  showDivider: true,
                  onTap: state.connectionState == WalletConnectionState.connected
                      ? () async {
                          final backup = await wallet.fetchBackupInfo();
                          if (!context.mounted) return;
                          if (backup == null) {
                            zentraSnack(context, 'Could not read wallet backup', isError: true);
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WalletBackupScreen(
                                backup: backup,
                                requireSeedAcknowledgement: false,
                                blockBack: false,
                              ),
                            ),
                          );
                        }
                      : null,
                ),
                ZentraSettingsTile(
                  icon: Icons.height_outlined,
                  title: 'Restore / sync height',
                  subtitle: RestoreHeightUtils.settingsSubtitle(
                    connected: state.connectionState == WalletConnectionState.connected,
                    scanHeight: state.walletScanHeight,
                    walletHeight: state.walletHeight,
                    defaultRestoreHeight: state.defaultRestoreHeight,
                    isSynced: state.isSynced,
                  ),
                  showDivider: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RestoreSyncHeightScreen()),
                  ),
                ),
              ],
            ),
            ZentraSettingsSection(
              title: 'Network',
              children: [
                ZentraSettingsTile(
                  icon: Icons.dns_outlined,
                  title: 'Node',
                  subtitle: NetworkUi.nodeSubtitle(state.nodeSettings),
                  showDivider: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NodeSetupScreen()),
                  ),
                ),
                ZentraSettingsTile(
                  icon: Icons.hub_outlined,
                  title: 'Network',
                  subtitle: state.networkLabel ?? 'Mainnet',
                  showDivider: !state.nativeAvailable,
                ),
                if (!state.nativeAvailable)
                  const ZentraSettingsTile(
                    icon: Icons.build_outlined,
                    title: NativeWalletMessages.title,
                    subtitle: NativeWalletMessages.subtitle,
                    showDivider: false,
                  ),
              ],
            ),
            ZentraSettingsSection(
              title: 'App',
              children: [
                ZentraSettingsTile(
                  icon: Icons.refresh_rounded,
                  title: 'Reconnect',
                  subtitle: 'Sync with daemon again',
                  showDivider: false,
                  onTap: () async {
                    final ok = await wallet.connect();
                    if (context.mounted) {
                      zentraSnack(
                        context,
                        ok ? 'Connected to node' : wallet.errorMessage ?? 'Reconnect failed',
                        isError: !ok,
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const ZentraLogo(size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Zentra Wallet',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ZentraTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        );

        if (embedded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZentraDashboardHeader(
                title: 'Settings',
                isRefreshing: state.isRefreshing,
                onRefresh: wallet.refresh,
              ),
              Expanded(child: list),
            ],
          );
        }

        return ZentraScaffold(
          appBar: zentraAppBar(context, title: 'Settings'),
          body: list,
        );
      },
    );
  }
}

class _SettingsViewState {
  const _SettingsViewState({
    required this.connectionStatusLabel,
    required this.connectionState,
    required this.showSyncBanner,
    required this.isRefreshing,
    required this.errorMessage,
    required this.isOpeningWallet,
    required this.syncBannerSubtitle,
    required this.syncProgressFraction,
    required this.primaryAddress,
    required this.walletFilename,
    required this.defaultRestoreHeight,
    required this.walletScanHeight,
    required this.walletHeight,
    required this.isSynced,
    required this.nodeSettings,
    required this.networkLabel,
    required this.nativeAvailable,
  });

  final String connectionStatusLabel;
  final WalletConnectionState connectionState;
  final bool showSyncBanner;
  final bool isRefreshing;
  final String? errorMessage;
  final bool isOpeningWallet;
  final String? syncBannerSubtitle;
  final double? syncProgressFraction;
  final String? primaryAddress;
  final String? walletFilename;
  final int defaultRestoreHeight;
  final int walletScanHeight;
  final int walletHeight;
  final bool isSynced;
  final NodeConnectionSettings? nodeSettings;
  final String? networkLabel;
  final bool nativeAvailable;

  @override
  bool operator ==(Object other) {
    return other is _SettingsViewState &&
        connectionStatusLabel == other.connectionStatusLabel &&
        connectionState == other.connectionState &&
        showSyncBanner == other.showSyncBanner &&
        isRefreshing == other.isRefreshing &&
        errorMessage == other.errorMessage &&
        isOpeningWallet == other.isOpeningWallet &&
        syncBannerSubtitle == other.syncBannerSubtitle &&
        syncProgressFraction == other.syncProgressFraction &&
        primaryAddress == other.primaryAddress &&
        walletFilename == other.walletFilename &&
        defaultRestoreHeight == other.defaultRestoreHeight &&
        walletScanHeight == other.walletScanHeight &&
        walletHeight == other.walletHeight &&
        isSynced == other.isSynced &&
        nodeSettings == other.nodeSettings &&
        networkLabel == other.networkLabel &&
        nativeAvailable == other.nativeAvailable;
  }

  @override
  int get hashCode => Object.hash(
        connectionStatusLabel,
        connectionState,
        showSyncBanner,
        isRefreshing,
        errorMessage,
        isOpeningWallet,
        syncBannerSubtitle,
        syncProgressFraction,
        primaryAddress,
        walletFilename,
        defaultRestoreHeight,
        walletScanHeight,
        walletHeight,
        isSynced,
        nodeSettings,
        networkLabel,
        nativeAvailable,
      );
}
