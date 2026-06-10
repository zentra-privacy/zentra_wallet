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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_filter != 0 || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMoreIfNeeded();
    }
  }

  /// When the first page is shorter than the viewport, there is nothing to scroll
  /// and [_onScroll] never runs — load more until the list scrolls or all items show.
  void _scheduleFillViewportIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _filter != 0 || !_scrollController.hasClients) return;
      final total = context.read<WalletProvider>().transfers.length;
      if (_visibleCount >= total) return;
      if (_scrollController.position.maxScrollExtent > 48) return;

      final before = _visibleCount;
      setState(() {
        _visibleCount = (_visibleCount + _loadMorePageSize).clamp(0, total);
      });
      if (_visibleCount > before && _visibleCount < total) {
        _scheduleFillViewportIfNeeded();
      }
    });
  }

  bool _loadMoreIfNeeded() {
    final total = context.read<WalletProvider>().transfers.length;
    if (_visibleCount >= total) return false;
    setState(() {
      _visibleCount = (_visibleCount + _loadMorePageSize).clamp(0, total);
    });
    return _visibleCount < total;
  }

  void _onFilterChanged(Set<int> selection) {
    final next = selection.first;
    if (next == _filter) return;
    setState(() {
      _filter = next;
      if (next == 0) _visibleCount = _initialPageSize;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  EdgeInsets _listBottomPadding(BuildContext context) {
    return EdgeInsets.only(bottom: ZentraTheme.navBarHeight + MediaQuery.paddingOf(context).bottom + 24);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    var list = wallet.transfers;
    if (_filter == 1) list = list.where((t) => t.isIncoming).toList();
    if (_filter == 2) list = list.where((t) => !t.isIncoming).toList();

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
        : _filter == 0
            ? _buildLazyAllList(context, wallet, list)
            : RefreshIndicator(
                color: ZentraTheme.accent,
                onRefresh: wallet.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _listBottomPadding(context),
                  children: [
                    Container(
                      margin: ZentraTheme.pagePadding,
                      decoration: ZentraTheme.gradientCard(),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < list.length; i++)
                            _row(context, list[i], wallet.formatAmount, i < list.length - 1),
                        ],
                      ),
                    ),
                  ],
                ),
              );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          ZentraDashboardHeader(
            title: 'History',
            isRefreshing: wallet.isRefreshing,
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
            onPressed: wallet.isRefreshing ? null : wallet.refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildLazyAllList(BuildContext context, WalletProvider wallet, List<WalletTransfer> list) {
    final displayCount = _visibleCount.clamp(0, list.length);
    if (displayCount < list.length) {
      _scheduleFillViewportIfNeeded();
    }

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
