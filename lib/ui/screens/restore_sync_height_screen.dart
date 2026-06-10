import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/restore_height_utils.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/zentra_theme.dart';
import '../widgets/restore_height_field.dart';
import '../widgets/zentra_ui.dart';

/// Default restore height and apply resync to the open wallet file.
class RestoreSyncHeightScreen extends StatefulWidget {
  const RestoreSyncHeightScreen({super.key});

  @override
  State<RestoreSyncHeightScreen> createState() => _RestoreSyncHeightScreenState();
}

class _RestoreSyncHeightScreenState extends State<RestoreSyncHeightScreen> {
  late final TextEditingController _heightController;
  bool _customEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _heightController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = context.read<WalletProvider>().defaultRestoreHeight;
      setState(() {
        _customEnabled = h > 0;
        _heightController.text = RestoreHeightUtils.format(h);
      });
    });
  }

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _saveDefault() async {
    final height = RestoreHeightField.resolveHeight(
      enabled: _customEnabled,
      controller: _heightController,
    );
    if (_customEnabled && height == null) {
      zentraSnack(context, 'Enter a valid block height', isError: true);
      return;
    }
    setState(() => _saving = true);
    await context.read<WalletProvider>().updateDefaultRestoreHeight(height ?? 0);
    if (mounted) setState(() => _saving = false);
    if (mounted) {
      zentraSnack(
        context,
        _customEnabled
            ? 'Default restore height saved'
            : 'Default cleared — new wallets scan from chain tip',
      );
    }
  }

  Future<void> _applyToWallet() async {
    if (!_customEnabled) {
      zentraSnack(context, 'Turn on custom height and enter a block number', isError: true);
      return;
    }
    final height = RestoreHeightField.resolveHeight(
      enabled: true,
      controller: _heightController,
    );
    if (height == null) {
      zentraSnack(context, 'Enter a valid block height', isError: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<WalletProvider>().applyRestoreHeightToOpenWallet(height);
    if (mounted) setState(() => _saving = false);
    if (!mounted) return;
    final wallet = context.read<WalletProvider>();
    zentraSnack(
      context,
      ok ? 'Resyncing from block $height' : wallet.errorMessage ?? 'Failed',
      isError: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final connected = wallet.connectionState == WalletConnectionState.connected;
    final canApply = connected && wallet.nativeAvailable && _customEnabled;

    return ZentraScaffold(
      appBar: zentraAppBar(context, title: 'Restore / sync height'),
      body: ListView(
        padding: zentraPageScrollPadding,
        children: [
          if (connected) ...[
            _WalletScanStatusCard(
              scanHeight: wallet.walletScanHeight,
              walletHeight: wallet.walletHeight,
              daemonHeight: wallet.daemonBlockHeight,
              isSynced: wallet.isSynced,
            ),
            const SizedBox(height: 16),
          ] else
            Text(
              'Connect a wallet to see saved scan progress. Defaults below apply when you create or restore a wallet.',
              style: const TextStyle(fontSize: 13, color: ZentraTheme.textMuted, height: 1.45),
            ),
          const SizedBox(height: 4),
          Text(
            connected
                ? 'The wallet file remembers where to resume scanning. Change the default only if you restore from seed on a new device.'
                : 'Set a default block height for seed restore. New wallets automatically start near the chain tip.',
            style: const TextStyle(fontSize: 13, color: ZentraTheme.textMuted, height: 1.45),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: ZentraTheme.flatCard(),
            child: RestoreHeightField(
              enabled: _customEnabled,
              onEnabledChanged: (v) => setState(() => _customEnabled = v),
              controller: _heightController,
              showRestoreHint: true,
            ),
          ),
          const SizedBox(height: 20),
          if (_saving)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: ZentraTheme.primary),
              ),
            )
          else ...[
            FilledButton(
              onPressed: _saveDefault,
              child: Text(_customEnabled ? 'Save default height' : 'Save (auto near tip)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: canApply ? _applyToWallet : null,
              child: const Text('Apply to open wallet & resync'),
            ),
          ],
          if (!canApply) ...[
            const SizedBox(height: 12),
            Text(
              !connected
                  ? 'Connect a wallet to apply a custom scan height.'
                  : !_customEnabled
                      ? 'Enable custom height to resync the open wallet from a specific block.'
                      : 'Native wallet required to apply height to the current file.',
              style: const TextStyle(color: ZentraTheme.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _WalletScanStatusCard extends StatelessWidget {
  const _WalletScanStatusCard({
    required this.scanHeight,
    required this.walletHeight,
    required this.daemonHeight,
    required this.isSynced,
  });

  final int scanHeight;
  final int walletHeight;
  final int daemonHeight;
  final bool isSynced;

  @override
  Widget build(BuildContext context) {
    final scanLabel = RestoreHeightUtils.describeScanStart(
      scanHeight: scanHeight,
      walletHeight: walletHeight,
      daemonHeight: daemonHeight,
      isSynced: isSynced,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ZentraTheme.gradientCard(radius: ZentraTheme.radiusLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current wallet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _StatusRow(
            label: 'Scanned up to',
            value: walletHeight > 0 ? 'Block $walletHeight' : 'Not yet',
          ),
          const SizedBox(height: 8),
          _StatusRow(label: 'Next open starts from', value: scanLabel),
          if (daemonHeight > 0) ...[
            const SizedBox(height: 8),
            _StatusRow(label: 'Chain tip', value: 'Block $daemonHeight'),
          ],
          const SizedBox(height: 8),
          _StatusRow(
            label: 'Status',
            value: isSynced ? 'Synced' : 'Syncing',
            valueColor: isSynced ? ZentraTheme.accent : ZentraTheme.textMuted,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: ZentraTheme.textMuted),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? ZentraTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
