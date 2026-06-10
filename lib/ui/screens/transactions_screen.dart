import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  static const _initialPageSize = 25;
  static const _loadMorePageSize = 25;

  int _filter = 0;
  int _visibleCount = _initialPageSize;
  late final ScrollController _scrollController;
  WalletProvider? _wallet;
  bool _viewportFillQueued = false;
  List<WalletTransfer>? _filterCacheSource;
  List<WalletTransfer> _incomingCache = const [];
  List<WalletTransfer> _outgoingCache = const [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wallet = context.read<WalletProvider>();
    if (_wallet == wallet) return;
    _wallet?.removeListener(_onWalletUpdated);
    _wallet = wallet;
    wallet.addListener(_onWalletUpdated);
    _queueViewportFill();
  }

  void _queueViewportFill() {
    if (_viewportFillQueued) return;
    _viewportFillQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportFillQueued = false;
      final wallet = _wallet;
      if (!mounted || wallet == null) return;
      _scheduleFillViewportIfNeeded(_filteredList(wallet).length);
    });
  }

  @override
  void dispose() {
    _wallet?.removeListener(_onWalletUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _onWalletUpdated() {
    final wallet = _wallet;
    if (wallet == null || !mounted) return;
    if (identical(_filterCacheSource, wallet.transfers)) return;

    final list = _filteredList(wallet);
    if (_visibleCount > list.length) {
      setState(() => _visibleCount = list.length);
    }
    _scheduleFillViewportIfNeeded(list.length);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMoreIfNeeded();
    }
  }

  void _scheduleFillViewportIfNeeded(int total) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_visibleCount >= total) return;
      if (_scrollController.position.maxScrollExtent > 48) return;

      final before = _visibleCount;
      setState(() {
        _visibleCount = (_visibleCount + _loadMorePageSize).clamp(0, total);
      });
      if (_visibleCount > before && _visibleCount < total) {
        _scheduleFillViewportIfNeeded(total);
      }
    });
  }

  void _loadMoreIfNeeded() {
    final wallet = _wallet ?? context.read<WalletProvider>();
    final total = _filteredList(wallet).length;
    if (_visibleCount >= total) return;
    setState(() {
      _visibleCount = (_visibleCount + _loadMorePageSize).clamp(0, total);
    });
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
      _visibleCount = _initialPageSize;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _queueViewportFill();
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
      ),
      builder: (context, viewState, _) {
        final wallet = context.read<WalletProvider>();
        final list = _filteredList(wallet);

        final listBody = list.isEmpty
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
            : _buildLazyList(context, wallet, list);

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

  Widget _buildLazyList(BuildContext context, WalletProvider wallet, List<WalletTransfer> list) {
    final displayCount = _visibleCount.clamp(0, list.length);

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
              itemCount: displayCount,
              itemBuilder: (context, index) => _row(
                context,
                list[index],
                wallet.formatAmount,
                index < displayCount - 1,
              ),
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
  });

  final List<WalletTransfer> transfers;
  final bool isRefreshing;

  @override
  bool operator ==(Object other) {
    return other is _HistoryViewState &&
        identical(transfers, other.transfers) &&
        isRefreshing == other.isRefreshing;
  }

  @override
  int get hashCode => Object.hash(transfers, isRefreshing);
}
