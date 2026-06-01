import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui_format.dart';
import '../../core/zentra_assets.dart';
import '../../models/wallet_models.dart';
import '../../theme/zentra_theme.dart';

/// Non-empty provider error text for status banners (connect or refresh failures).
String? zentraStatusErrorMessage(String? errorMessage) {
  final msg = errorMessage?.trim();
  if (msg == null || msg.isEmpty) return null;
  return msg;
}

void zentraSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? ZentraTheme.danger : ZentraTheme.card,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class ZentraLogo extends StatelessWidget {
  const ZentraLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).round().clamp(1, 1024);

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        ZentraAssets.logo,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        semanticLabel: 'Zentra',
      ),
    );
  }
}

/// Primary action with inline spinner — fixed height, no layout jump while loading.
class ZentraLoadingButton extends StatelessWidget {
  const ZentraLoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: loading
            ? Row(
                key: const ValueKey('loading'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(loadingLabel ?? label),
                ],
              )
            : Text(label, key: const ValueKey('idle')),
      ),
    );
  }
}

/// Tappable card for onboarding choices (create / restore / open).
class ZentraChoiceCard extends StatelessWidget {
  const ZentraChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  /// Single-line row: icon + short label only.
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ZentraTheme.radiusLg),
      side: BorderSide(
        color: selected ? ZentraTheme.primary : ZentraTheme.border,
        width: selected ? 1.5 : 1,
      ),
    );

    if (compact) {
      return Material(
        color: selected ? ZentraTheme.primary.withValues(alpha: 0.12) : ZentraTheme.surfaceContainer,
        shape: border,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(ZentraTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: !enabled
                      ? ZentraTheme.textMuted.withValues(alpha: 0.5)
                      : selected
                          ? ZentraTheme.primary
                          : ZentraTheme.textMuted,
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: !enabled
                        ? ZentraTheme.textMuted.withValues(alpha: 0.5)
                        : selected
                            ? ZentraTheme.textPrimary
                            : ZentraTheme.textMuted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: selected ? ZentraTheme.accent.withValues(alpha: 0.12) : ZentraTheme.card,
      shape: border,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(ZentraTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? ZentraTheme.accent.withValues(alpha: 0.2)
                      : ZentraTheme.surface,
                  borderRadius: BorderRadius.circular(ZentraTheme.radiusSm),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? ZentraTheme.accent : ZentraTheme.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 12, color: ZentraTheme.textMuted, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? ZentraTheme.accent : ZentraTheme.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bordered card surface; use for groups of [ListTile] / [RadioListTile] children.
class ZentraCard extends StatelessWidget {
  const ZentraCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: ZentraTheme.flatCard(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: ZentraTheme.card,
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}

/// Groups onboarding form fields in a single card.
class ZentraFormCard extends StatelessWidget {
  const ZentraFormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ZentraTheme.flatCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Full-screen gradient (Cake Wallet surface → surfaceDim).
class ZentraGradientBackground extends StatelessWidget {
  const ZentraGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ZentraTheme.background, ZentraTheme.backgroundDeep],
        ),
      ),
      child: child,
    );
  }
}

class ZentraScaffold extends StatelessWidget {
  const ZentraScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.gradient = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    // Gradient must fill the viewport — wrapping only the scroll child leaves a
    // solid scaffold color band below short pages (Send, Receive, etc.).
    final Widget bodyChild;
    if (gradient) {
      bodyChild = Stack(
        fit: StackFit.expand,
        children: [
          const ZentraGradientBackground(child: SizedBox.expand()),
          body,
        ],
      );
    } else {
      bodyChild = body;
    }

    return Scaffold(
      backgroundColor: gradient ? ZentraTheme.backgroundDeep : ZentraTheme.background,
      extendBody: bottomNavigationBar != null,
      appBar: appBar,
      body: SafeArea(
        top: appBar == null,
        bottom: bottomNavigationBar == null,
        child: bodyChild,
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Standard secondary-screen app bar (send, receive, node setup, etc.).
PreferredSizeWidget zentraAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: ZentraTheme.background,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    leading: zentraAppBarBackButton(context),
    title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    actions: actions,
  );
}

Widget zentraAppBarBackButton(BuildContext context) {
  return IconButton(
    tooltip: 'Back',
    icon: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ZentraTheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(ZentraTheme.radiusMd),
        border: Border.all(color: ZentraTheme.border.withValues(alpha: 0.5)),
      ),
      child: const Icon(Icons.arrow_back, size: 20),
    ),
    onPressed: () => Navigator.maybePop(context),
  );
}

/// App bar action matching [zentraAppBarBackButton] surface style.
Widget zentraAppBarAction({
  required IconData icon,
  required VoidCallback? onPressed,
  String? tooltip,
}) {
  return IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ZentraTheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(ZentraTheme.radiusMd),
        border: Border.all(color: ZentraTheme.border.withValues(alpha: 0.5)),
      ),
      child: Icon(icon, size: 20, color: ZentraTheme.textMuted),
    ),
  );
}

/// Standard horizontal padding for scrollable secondary screens.
const EdgeInsets zentraPageScrollPadding = EdgeInsets.fromLTRB(20, 8, 20, 24);

/// Connection / sync status (Settings only — not shown on Home / History headers).
class ZentraWalletStatusBanner extends StatelessWidget {
  const ZentraWalletStatusBanner({
    super.key,
    this.errorMessage,
    this.isConnecting = false,
    this.isSyncing = false,
    this.syncSubtitle,
    this.syncProgress,
    this.compact = false,
  });

  final String? errorMessage;
  final bool isConnecting;
  final bool isSyncing;
  final String? syncSubtitle;
  final double? syncProgress;
  /// Tighter layout inside Settings status card (no page horizontal margin).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final margin = compact ? const EdgeInsets.only(top: 10) : null;
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return ZentraSyncBanner(
        message: errorMessage!,
        isError: true,
        subtitle: 'Check node settings or reconnect',
        margin: margin,
      );
    }
    if (isConnecting) {
      return ZentraSyncBanner(message: 'Opening wallet…', margin: margin);
    }
    if (isSyncing) {
      return ZentraSyncBanner(
        message: 'Syncing with network',
        subtitle: syncSubtitle ?? 'Scanning blocks in the background',
        progress: syncProgress,
        margin: margin,
      );
    }
    return const SizedBox.shrink();
  }
}

void showZentraTxDetailSheet(
  BuildContext context, {
  required WalletTransfer transfer,
  required String Function(int) formatAmount,
}) {
  final t = transfer;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ZentraTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZentraTheme.radiusLg)),
    ),
    builder: (ctx) {
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ZentraTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t.isIncoming ? 'Incoming transfer' : 'Outgoing transfer',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ZentraCopyField(label: 'Amount', value: '${formatAmount(t.amountAtomic)} ZTRA', maxLines: 1),
                const SizedBox(height: 12),
                ZentraCopyField(label: 'Transaction ID', value: t.txid),
                const SizedBox(height: 12),
                Text(
                  '${UiFormat.relativeTime(t.timestamp)} · ${t.confirmations} confirmations'
                  '${t.pending ? ' · Pending' : ''}',
                  style: const TextStyle(color: ZentraTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
            ),
          ),
        ),
      );
    },
  );
}

/// Back-compat name
typedef ZentraGradientScaffold = ZentraScaffold;

class ZentraPageHeader extends StatelessWidget {
  const ZentraPageHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Home tab top bar — wallet name + refresh (Cake-style).
class ZentraHomeTopBar extends StatelessWidget {
  const ZentraHomeTopBar({
    super.key,
    this.walletName,
    this.networkLabel,
    this.onRefresh,
    this.isRefreshing = false,
    this.onSettings,
  });

  final String? walletName;
  final String? networkLabel;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          const ZentraLogo(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  walletName ?? 'Zentra Wallet',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (networkLabel != null)
                  Text(
                    networkLabel!,
                    style: const TextStyle(fontSize: 12, color: ZentraTheme.textMuted),
                  ),
              ],
            ),
          ),
          if (isRefreshing)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: ZentraTheme.primary),
              ),
            )
          else if (onRefresh != null)
            _TopBarIconButton(icon: Icons.refresh, onPressed: onRefresh, tooltip: 'Refresh'),
          if (onSettings != null) ...[
            const SizedBox(width: 4),
            _TopBarIconButton(icon: Icons.settings_outlined, onPressed: onSettings, tooltip: 'Settings'),
          ],
        ],
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(ZentraTheme.minTouchTarget, ZentraTheme.minTouchTarget),
        backgroundColor: ZentraTheme.surfaceContainer.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZentraTheme.radiusMd),
          side: BorderSide(color: ZentraTheme.border.withValues(alpha: 0.5)),
        ),
      ),
      icon: Icon(icon, size: 20, color: ZentraTheme.textMuted),
    );
  }
}

class ZentraDashboardHeader extends StatelessWidget {
  const ZentraDashboardHeader({
    super.key,
    required this.title,
    this.onRefresh,
    this.isRefreshing = false,
  });

  final String title;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    Widget? trailing;
    if (isRefreshing) {
      trailing = const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: ZentraTheme.primary),
        ),
      );
    } else if (onRefresh != null) {
      trailing = _TopBarIconButton(icon: Icons.refresh, onPressed: onRefresh, tooltip: 'Refresh');
    }
    return ZentraPageHeader(title: title, trailing: trailing);
  }
}

/// Explains why part of the balance is locked (confirmation / security delays).
void showZentraLockedBalanceInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Locked balance'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'For your security, not every ZTRA in your wallet can be spent immediately.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
            SizedBox(height: 16),
            Text(
              'Received funds',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Tokens you receive stay locked until the transaction has about 60 confirmations on the network. After that they move to your unlocked balance and you can send them.',
              style: TextStyle(fontSize: 13, color: ZentraTheme.textMuted, height: 1.45),
            ),
            SizedBox(height: 14),
            Text(
              'After you send',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'If you still see locked balance right after sending, that is usually change or outputs waiting to confirm. They typically unlock after about 10 blocks.',
              style: TextStyle(fontSize: 13, color: ZentraTheme.textMuted, height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class ZentraHeroBalanceCard extends StatelessWidget {
  const ZentraHeroBalanceCard({
    super.key,
    required this.amountZtr,
    this.unlockedZtr,
    this.lockedZtr,
    this.secondaryLabel,
  });

  final String amountZtr;
  final String? unlockedZtr;
  final String? lockedZtr;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: ZentraTheme.pagePadding,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: ZentraTheme.gradientCard(radius: ZentraTheme.radiusXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Total balance', style: TextStyle(color: ZentraTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (secondaryLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ZentraTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ZentraTheme.radiusPill),
                    border: Border.all(color: ZentraTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    secondaryLabel!,
                    style: const TextStyle(fontSize: 11, color: ZentraTheme.primary, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            amountZtr,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
          ),
          if (unlockedZtr != null || lockedZtr != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (unlockedZtr != null)
              Row(
                children: [
                  const Icon(Icons.lock_open_outlined, size: 16, color: ZentraTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Unlocked $unlockedZtr', style: const TextStyle(fontSize: 13, color: ZentraTheme.textMuted)),
                  ),
                ],
              ),
            if (lockedZtr != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 16, color: ZentraTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Locked $lockedZtr',
                      style: const TextStyle(fontSize: 13, color: ZentraTheme.textMuted, height: 1.35),
                    ),
                  ),
                  IconButton(
                    onPressed: () => showZentraLockedBalanceInfo(context),
                    icon: const Icon(Icons.help_outline, size: 18, color: ZentraTheme.textMuted),
                    tooltip: 'Why is balance locked?',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class ZentraQuickActionsRow extends StatelessWidget {
  const ZentraQuickActionsRow({super.key, required this.actions});

  final List<ZentraQuickActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ZentraTheme.pagePadding,
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: ZentraQuickActionButton(item: actions[i])),
          ],
        ],
      ),
    );
  }
}

class ZentraQuickActionItem {
  const ZentraQuickActionItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
}

class ZentraQuickActionButton extends StatelessWidget {
  const ZentraQuickActionButton({super.key, required this.item});

  final ZentraQuickActionItem item;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.enabled ? item.onTap : null,
          borderRadius: BorderRadius.circular(ZentraTheme.radiusLg),
          child: Column(
            children: [
              Container(
                width: ZentraTheme.quickActionSize,
                height: ZentraTheme.quickActionSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ZentraTheme.accent.withValues(alpha: 0.28),
                      ZentraTheme.card,
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: ZentraTheme.accent.withValues(alpha: 0.45)),
                ),
                child: Icon(item.icon, color: ZentraTheme.accent, size: ZentraTheme.navIconSize),
              ),
              const SizedBox(height: 10),
              Text(
                item.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ZentraTheme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ZentraSectionHeader extends StatelessWidget {
  const ZentraSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(color: ZentraTheme.accent, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}

class ZentraSyncBanner extends StatelessWidget {
  const ZentraSyncBanner({
    super.key,
    required this.message,
    this.isError = false,
    this.progress,
    this.subtitle,
    this.margin,
  });

  final String message;
  final bool isError;
  final double? progress;
  final String? subtitle;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final color = isError ? ZentraTheme.danger : ZentraTheme.accent;
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZentraTheme.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isError ? Icons.error_outline : Icons.sync, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: const TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.9))),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (progress != null && !isError) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: ZentraTheme.border,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ZentraConnectionChip extends StatelessWidget {
  const ZentraConnectionChip({super.key, required this.label, this.isError = false, this.isSyncing = false});

  final String label;
  final bool isError;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? ZentraTheme.danger
        : isSyncing
            ? ZentraTheme.accent
            : ZentraTheme.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class ZentraEmptyState extends StatelessWidget {
  const ZentraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: ZentraTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ZentraTheme.textMuted, fontSize: 13, height: 1.4),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class ZentraCopyField extends StatelessWidget {
  const ZentraCopyField({
    super.key,
    required this.label,
    required this.value,
    this.maxLines = 3,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: ZentraTheme.flatCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                value.isEmpty ? '—' : value,
                maxLines: maxLines,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      zentraSnack(context, '$label copied');
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ZentraAddressChip extends StatelessWidget {
  const ZentraAddressChip({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    if (address.isEmpty) return const SizedBox.shrink();
    final short = UiFormat.truncateMiddle(address);
    return Material(
      color: ZentraTheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: address));
          zentraSnack(context, 'Address copied');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ZentraTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 14, color: ZentraTheme.textMuted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(short, style: const TextStyle(fontSize: 12, color: ZentraTheme.textMuted)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.copy, size: 14, color: ZentraTheme.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class ZentraBottomNav extends StatelessWidget {
  const ZentraBottomNav({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Assets'),
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'History'),
      (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
    ];

    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad > 0 ? bottomPad : 8),
      child: Container(
        height: ZentraTheme.navBarHeight,
        decoration: BoxDecoration(
          color: ZentraTheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(ZentraTheme.radiusXl),
          border: Border.all(color: ZentraTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavItem(
                  label: items[i].$3,
                  icon: currentIndex == i ? items[i].$2 : items[i].$1,
                  selected: currentIndex == i,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? ZentraTheme.accent : ZentraTheme.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZentraTheme.radiusLg),
        child: SizedBox(
          height: ZentraTheme.navBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: ZentraTheme.navIconSize, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ZentraTheme.navLabelSize,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? ZentraTheme.textPrimary : color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clean list row for transactions.
class ZentraTxRow extends StatelessWidget {
  const ZentraTxRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isIncoming,
    this.showDivider = true,
    this.pending = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String amount;
  final bool isIncoming;
  final bool showDivider;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isIncoming ? ZentraTheme.success : ZentraTheme.textPrimary;
    final iconBg = isIncoming
        ? ZentraTheme.success.withValues(alpha: 0.15)
        : ZentraTheme.primary.withValues(alpha: 0.12);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: ZentraTheme.listLeadingSize,
            height: ZentraTheme.listLeadingSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(ZentraTheme.radiusMd),
            ),
            child: Icon(
              isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: ZentraTheme.navIconSize,
              color: isIncoming ? ZentraTheme.success : ZentraTheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    if (pending) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ZentraTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Pending', style: TextStyle(fontSize: 10, color: ZentraTheme.accent)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: ZentraTheme.textMuted)),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
    return Column(
      children: [
        if (onTap != null)
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: row),
          )
        else
          row,
        if (showDivider) const Divider(height: 1, indent: 74, endIndent: 20),
      ],
    );
  }
}

/// Grouped settings section (Cake-style card).
class ZentraSettingsSection extends StatelessWidget {
  const ZentraSettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZentraTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: ZentraTheme.gradientCard(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class ZentraSettingsTile extends StatelessWidget {
  const ZentraSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Column(
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
          color: Colors.transparent,
          child: ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              width: ZentraTheme.listLeadingSize,
              height: ZentraTheme.listLeadingSize,
              alignment: Alignment.center,
              decoration: ZentraTheme.iconCircle(),
              child: Icon(icon, color: ZentraTheme.primary, size: ZentraTheme.navIconSize),
            ),
            title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            subtitle: subtitle != null
                ? Text(subtitle!, style: const TextStyle(color: ZentraTheme.textMuted, fontSize: 12))
                : null,
            trailing: trailing ??
                (enabled ? const Icon(Icons.chevron_right_rounded, size: 22, color: ZentraTheme.textMuted) : null),
          ),
        ),
        ),
        if (showDivider) const Divider(height: 1, indent: 68, endIndent: 14),
      ],
    );
  }
}

typedef ZentraBalanceCard = ZentraHeroBalanceCard;
typedef ZentraActionButton = ZentraQuickActionButton;
