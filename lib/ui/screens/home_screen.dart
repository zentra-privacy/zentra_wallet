import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/transfer_pagination.dart';
import '../../core/ui_format.dart';
import '../../models/wallet_models.dart';
import '../../providers/wallet_provider.dart' show WalletProvider;
import '../../theme/zentra_theme.dart';
import '../widgets/zentra_ui.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ZentraScaffold(
      body: IndexedStack(
        index: _tab,
        sizing: StackFit.expand,
        children: [
          _DashboardTab(
            onSeeAllTx: () => setState(() => _tab = 2),
            onOpenSettings: () => setState(() => _tab = 3),
          ),
          const _AssetsTab(),
          TickerMode(
            enabled: _tab == 2,
            child: const TransactionsScreen(embedded: true),
          ),
          TickerMode(
            enabled: _tab == 3,
            child: const SettingsScreen(embedded: true),
          ),
        ],
      ),
      bottomNavigationBar: ZentraBottomNav(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _DashboardViewState {
  const _DashboardViewState({
    required this.walletFilename,
    required this.networkLabel,
    required this.isRefreshing,
    required this.balance,
    required this.lockedBalanceAtomic,
    required this.address,
    required this.transfers,
    required this.canTransact,
    required this.isSynced,
  });

  final String? walletFilename;
  final String? networkLabel;
  final bool isRefreshing;
  final WalletBalance? balance;
  final int lockedBalanceAtomic;
  final String address;
  final List<WalletTransfer> transfers;
  final bool canTransact;
  final bool isSynced;

  @override
  bool operator ==(Object other) {
    return other is _DashboardViewState &&
        walletFilename == other.walletFilename &&
        networkLabel == other.networkLabel &&
        isRefreshing == other.isRefreshing &&
        balance?.balanceAtomic == other.balance?.balanceAtomic &&
        balance?.unlockedAtomic == other.balance?.unlockedAtomic &&
        lockedBalanceAtomic == other.lockedBalanceAtomic &&
        address == other.address &&
        identical(transfers, other.transfers) &&
        canTransact == other.canTransact &&
        isSynced == other.isSynced;
  }

  @override
  int get hashCode => Object.hash(
        walletFilename,
        networkLabel,
        isRefreshing,
        balance?.balanceAtomic,
        balance?.unlockedAtomic,
        lockedBalanceAtomic,
        address,
        transfers,
        canTransact,
        isSynced,
      );
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.onSeeAllTx,
    required this.onOpenSettings,
  });

  final VoidCallback onSeeAllTx;
  final VoidCallback onOpenSettings;

  void _openReceive(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiveScreen()));
  }

  void _openSend(BuildContext context, _DashboardViewState state) {
    if (!state.canTransact) {
      final msg = !state.isSynced
          ? 'Wait for sync to finish before sending'
          : 'Wait until the wallet is connected';
      zentraSnack(context, msg, isError: true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SendScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Selector<WalletProvider, _DashboardViewState>(
      selector: (_, wallet) => _DashboardViewState(
        walletFilename: wallet.walletFilename,
        networkLabel: wallet.networkConfig?.label,
        isRefreshing: wallet.isRefreshing,
        balance: wallet.balance,
        lockedBalanceAtomic: wallet.lockedBalanceAtomic,
        address: wallet.primaryAddress?.address ?? '',
        transfers: wallet.transfers,
        canTransact: wallet.canTransact,
        isSynced: wallet.isSynced,
      ),
      builder: (context, state, _) {
        final wallet = context.read<WalletProvider>();
        final balance = state.balance;
        final recent = state.transfers.take(kHomeRecentTransferCount).toList(growable: false);

        return RefreshIndicator(
          color: ZentraTheme.accent,
          onRefresh: wallet.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: ZentraTheme.navBarHeight + MediaQuery.paddingOf(context).bottom + 24),
            children: [
              ZentraHomeTopBar(
                walletName: state.walletFilename,
                networkLabel: state.networkLabel,
                isRefreshing: state.isRefreshing,
                onRefresh: wallet.refresh,
                onSettings: onOpenSettings,
              ),
              ZentraHeroBalanceCard(
                amountZtr: balance != null
                    ? '${wallet.formatAmount(balance.balanceAtomic)} ZTRA'
                    : '— ZTRA',
                unlockedZtr: balance != null
                    ? '${wallet.formatAmount(balance.unlockedAtomic)} ZTRA'
                    : null,
                lockedZtr: state.lockedBalanceAtomic > 0
                    ? '${wallet.formatAmount(state.lockedBalanceAtomic)} ZTRA'
                    : null,
                secondaryLabel: state.networkLabel,
              ),
              if (state.address.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Center(child: ZentraAddressChip(address: state.address)),
                ),
              ZentraQuickActionsRow(
                actions: [
                  ZentraQuickActionItem(
                    icon: Icons.arrow_outward_rounded,
                    label: 'Send',
                    onTap: () => _openSend(context, state),
                  ),
                  ZentraQuickActionItem(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Receive',
                    onTap: () => _openReceive(context),
                  ),
                ],
              ),
              ZentraSectionHeader(title: 'Recent activity', actionLabel: 'See all', onAction: onSeeAllTx),
              if (recent.isEmpty)
                ZentraEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  subtitle: 'Receive ZTRA to this wallet to see activity here.',
                  actionLabel: 'Receive',
                  onAction: () => _openReceive(context),
                )
              else
                Container(
                  margin: ZentraTheme.pagePadding,
                  decoration: ZentraTheme.gradientCard(),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++)
                        _txRow(context, recent[i], wallet.formatAmount, showDivider: i < recent.length - 1),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _txRow(
    BuildContext context,
    WalletTransfer t,
    String Function(int) format, {
    required bool showDivider,
  }) {
    final incoming = t.isIncoming;
    final id = UiFormat.truncateMiddle(t.txid, head: 8, tail: 6);
    return ZentraTxRow(
      title: incoming ? 'Received' : 'Sent',
      subtitle: '$id · ${UiFormat.relativeTime(t.timestamp)}',
      amount: '${incoming ? '+' : '-'}${format(t.amountAtomic)} ZTRA',
      isIncoming: incoming,
      pending: t.pending,
      showDivider: showDivider,
      onTap: () => showZentraTxDetailSheet(context, transfer: t, formatAmount: format),
    );
  }
}

class _AssetsViewState {
  const _AssetsViewState({
    required this.balance,
    required this.lockedBalanceAtomic,
  });

  final WalletBalance? balance;
  final int lockedBalanceAtomic;

  @override
  bool operator ==(Object other) {
    return other is _AssetsViewState &&
        balance?.balanceAtomic == other.balance?.balanceAtomic &&
        balance?.unlockedAtomic == other.balance?.unlockedAtomic &&
        lockedBalanceAtomic == other.lockedBalanceAtomic;
  }

  @override
  int get hashCode => Object.hash(
        balance?.balanceAtomic,
        balance?.unlockedAtomic,
        lockedBalanceAtomic,
      );
}

class _AssetsTab extends StatelessWidget {
  const _AssetsTab();

  @override
  Widget build(BuildContext context) {
    return Selector<WalletProvider, _AssetsViewState>(
      selector: (_, wallet) => _AssetsViewState(
        balance: wallet.balance,
        lockedBalanceAtomic: wallet.lockedBalanceAtomic,
      ),
      builder: (context, state, _) {
        final wallet = context.read<WalletProvider>();
        final balance = state.balance;

        return RefreshIndicator(
          color: ZentraTheme.accent,
          onRefresh: wallet.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: ZentraTheme.navBarHeight + MediaQuery.paddingOf(context).bottom + 24),
            children: [
              const ZentraDashboardHeader(title: 'Assets'),
              ZentraHeroBalanceCard(
                amountZtr: balance != null
                    ? '${wallet.formatAmount(balance.balanceAtomic)} ZTRA'
                    : '— ZTRA',
                unlockedZtr: balance != null
                    ? '${wallet.formatAmount(balance.unlockedAtomic)} ZTRA'
                    : null,
                lockedZtr: state.lockedBalanceAtomic > 0
                    ? '${wallet.formatAmount(state.lockedBalanceAtomic)} ZTRA'
                    : null,
              ),
              const SizedBox(height: 12),
              Container(
                margin: ZentraTheme.pagePadding,
                decoration: ZentraTheme.gradientCard(),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: ZentraTheme.iconCircle(),
                    child: const ZentraLogo(size: 32),
                  ),
                  title: const Text('Zentra', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  subtitle: const Text('Native coin · ZTRA', style: TextStyle(color: ZentraTheme.textMuted, fontSize: 12)),
                  trailing: Text(
                    balance != null ? '${wallet.formatAmount(balance.balanceAtomic)} ZTRA' : '0',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ZentraTheme.primary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
