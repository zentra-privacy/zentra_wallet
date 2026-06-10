import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/transfer_pagination.dart';
import '../../core/ui_format.dart';
import '../../models/wallet_models.dart';
import '../../providers/wallet_provider.dart' show WalletProvider;
import '../../theme/zentra_theme.dart';
import '../widgets/zentra_ui.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  static const _maxFilteredAutoLoadRounds = 20;

  int _filter = 0;
  int _filteredAutoLoadRounds = 0;
  late final ScrollController _scrollController;
  WalletProvider? _wallet;

  List<WalletTransfer>? _filterCacheSource;
  List<WalletTransfer> _incomingCache = const [];
  List<WalletTransfer> _outgoingCache = const [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().ensureRecentTransfersLoaded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wallet = context.read<WalletProvider>();
    if (_wallet == wallet) return;
    _wallet?.removeListener(_onWalletUpdated);
    _wallet = wallet;
    wallet.addListener(_onWalletUpdated);
    wallet.ensureRecentTransfersLoaded();
    _scheduleContentChecks();
  }

  @override
  void dispose() {
    _wallet?.removeListener(_onWalletUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _invalidateFilterCache() {
    _filterCacheSource = null;
    _incomingCache = const [];
    _outgoingCache = const [];
  }

  void _onWalletUpdated() {
    final wallet = _wallet;
    if (wallet == null || !mounted) return;
    if (identical(_filterCacheSource, wallet.transfers)) return;
    _invalidateFilterCache();
    _scheduleContentChecks();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMoreIfNeeded();
    }
  }

  void _scheduleContentChecks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeAutoLoadFiltered();
      _maybeFillViewport();
    });
  }

  void _maybeAutoLoadFiltered() {
    final wallet = _wallet;
    if (wallet == null || !mounted) return;
    if (wallet.isLoadingMoreTransfers || !wallet.hasMoreTransfers) return;
    if (_filteredAutoLoadRounds >= _maxFilteredAutoLoadRounds) return;

    final list = _filteredList(wallet);
    final needsMoreForFilter = _filter != 0 && list.length < kTransferPageSize;
    final showEmptyFiltered = _filter != 0 && list.isEmpty;
    if (!showEmptyFiltered && !needsMoreForFilter) return;

    _filteredAutoLoadRounds++;
    wallet.loadMoreTransfers();
  }

  void _maybeFillViewport() {
    if (!_scrollController.hasClients) return;
    final wallet = _wallet;
    if (wallet == null) return;
    if (_scrollController.position.maxScrollExtent > 48) return;
    if (wallet.hasMoreTransfers && !wallet.isLoadingMoreTransfers) {
      wallet.loadMoreTransfers();
    }
  }

  void _loadMoreIfNeeded() {
    final wallet = _wallet ?? context.read<WalletProvider>();
    if (wallet.hasMoreTransfers && !wallet.isLoadingMoreTransfers) {
      wallet.loadMoreTransfers();
    }
  }

  List<WalletTransfer> _filteredList(WalletProvider wallet) {
    final all = wallet.transfers;
    if (_filterCacheSource != all) {
      _filterCacheSource = all;
      _incomingCache = all.where((t) => t.isIncoming).toList(growable: false);
      _outgoingCache = all.where((t) => !t.isIncoming).toList(growable: false);
    }
    return switch (_filter) {
      1 => _incomingCache,
      2 => _outgoingCache,
      _ => all,
    };
  }

  void _onFilterChanged(Set<int> selection) {
    final next = selection.first;
    if (next == _filter) return;
    setState(() {
      _filter = next;
      _filteredAutoLoadRounds = 0;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _scheduleContentChecks();
  }

  EdgeInsets _listBottomPadding(BuildContext context) {
    return EdgeInsets.only(bottom: ZentraTheme.navBarHeight + MediaQuery.paddingOf(context).bottom + 24);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<WalletProvider, _HistoryViewState>(
      selector: (_, wallet) => _HistoryViewState(
        transfers: wallet.transfers,
        isRefreshing: wallet.isRefreshing,
        isLoadingMore: wallet.isLoadingMoreTransfers,
        hasMore: wallet.hasMoreTransfers,
        totalCount: wallet.transferTotalCount,
      ),
      builder: (context, viewState, _) {
        final wallet = context.read<WalletProvider>();
        final list = _filteredList(wallet);
        final showLoaderTail = viewState.hasMore &&
            (viewState.isLoadingMore || list.isNotEmpty);

        if (_filter != 0 && list.isEmpty && viewState.hasMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoLoadFiltered());
        }

        final listBody = list.isEmpty && !viewState.isLoadingMore && !viewState.hasMore
            ? RefreshIndicator(
                color: ZentraTheme.accent,
                onRefresh: wallet.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _listBottomPadding(context),
                  children: [
                    Center(
                      child: ZentraEmptyState(
                        icon: Icons.history,
                        title: 'No transactions',
                        subtitle: _filter == 0
                            ? 'Your incoming and outgoing transfers will appear here.'
                            : 'Nothing in this filter yet.',
                      ),
                    ),
                  ],
                ),
              )
            : _buildLazyList(
                context,
                wallet,
                list,
                showLoaderTail: showLoaderTail,
                loadedCount: viewState.transfers.length,
                totalCount: viewState.totalCount,
              );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.embedded)
              ZentraDashboardHeader(
                title: 'History',
                isRefreshing: viewState.isRefreshing,
                onRefresh: wallet.refresh,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('All')),
                  ButtonSegment(value: 1, label: Text('Received')),
                  ButtonSegment(value: 2, label: Text('Sent')),
                ],
                selected: {_filter},
                onSelectionChanged: _onFilterChanged,
              ),
            ),
            Expanded(child: listBody),
          ],
        );

        if (widget.embedded) return content;

        return ZentraScaffold(
          appBar: zentraAppBar(
            context,
            title: 'History',
            actions: [
              zentraAppBarAction(
                icon: Icons.refresh,
                onPressed: viewState.isRefreshing ? null : wallet.refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: content,
        );
      },
    );
  }

  Widget _buildLazyList(
    BuildContext context,
    WalletProvider wallet,
    List<WalletTransfer> list, {
    required bool showLoaderTail,
    required int loadedCount,
    required int totalCount,
  }) {
    final itemCount = list.length + (showLoaderTail ? 1 : 0);

    return RefreshIndicator(
      color: ZentraTheme.accent,
      onRefresh: wallet.refresh,
      child: Padding(
        padding: ZentraTheme.pagePadding,
        child: DecoratedBox(
          decoration: ZentraTheme.gradientCard(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ZentraTheme.radiusLg),
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: _listBottomPadding(context),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index >= list.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Column(
                        children: [
                          if (wallet.isLoadingMoreTransfers)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ZentraTheme.accent,
                              ),
                            )
                          else
                            Text(
                              'Loaded $loadedCount of $totalCount',
                              style: const TextStyle(
                                color: ZentraTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                return _row(
                  context,
                  list[index],
                  wallet.formatAmount,
                  index < list.length - 1,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WalletTransfer t, String Function(int) format, bool showDivider) {
    final incoming = t.isIncoming;
    return ZentraTxRow(
      title: incoming ? 'Received' : 'Sent',
      subtitle: '${UiFormat.truncateMiddle(t.txid, head: 8, tail: 6)} · ${UiFormat.relativeTime(t.timestamp)}',
      amount: '${incoming ? '+' : '-'}${format(t.amountAtomic)} ZTRA',
      isIncoming: incoming,
      pending: t.pending,
      showDivider: showDivider,
      onTap: () => showZentraTxDetailSheet(context, transfer: t, formatAmount: format),
    );
  }
}

class _HistoryViewState {
  const _HistoryViewState({
    required this.transfers,
    required this.isRefreshing,
    required this.isLoadingMore,
    required this.hasMore,
    required this.totalCount,
  });

  final List<WalletTransfer> transfers;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasMore;
  final int totalCount;

  @override
  bool operator ==(Object other) {
    return other is _HistoryViewState &&
        identical(transfers, other.transfers) &&
        isRefreshing == other.isRefreshing &&
        isLoadingMore == other.isLoadingMore &&
        hasMore == other.hasMore &&
        totalCount == other.totalCount;
  }

  @override
  int get hashCode => Object.hash(transfers, isRefreshing, isLoadingMore, hasMore, totalCount);
}
