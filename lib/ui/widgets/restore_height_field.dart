import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/restore_height_utils.dart';
import '../../theme/zentra_theme.dart';

/// Block height for wallet sync (create / restore / settings).
class RestoreHeightField extends StatelessWidget {
  const RestoreHeightField({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.controller,
    this.showRestoreHint = false,
    this.compact = false,
    this.restoreOnly = false,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final TextEditingController controller;
  final bool showRestoreHint;
  /// Shorter labels for onboarding.
  final bool compact;
  /// Restore flow: required block hint. New wallet uses auto tip (no toggle).
  final bool restoreOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restoreOnly
                        ? 'Restore block'
                        : (compact ? 'Sync from block' : 'Custom sync height'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  if (restoreOnly || !compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      restoreOnly
                          ? 'Block of your first ZTRA receive (faster sync)'
                          : (showRestoreHint
                              ? 'Block when wallet was first used (restore) or scan start (new)'
                              : 'Start blockchain scan from a specific block'),
                      style: const TextStyle(color: ZentraTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onEnabledChanged,
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: compact || restoreOnly ? 'Block' : 'Block height',
              hintText: '2500000',
              helperText: (compact && !restoreOnly)
                  ? null
                  : restoreOnly
                      ? 'Wrong block may hide balance until fully scanned'
                      : showRestoreHint
                          ? 'For seed restore: first block you received ZTRA. Off = auto near chain tip.'
                          : 'Leave off to use estimated height. Must be below chain tip (not equal to daemon height).',
              helperMaxLines: restoreOnly ? 2 : (compact ? 1 : 3),
            ),
          ),
        ],
      ],
    );
  }

  /// Returns parsed height, or null if custom enabled but invalid.
  static int? resolveHeight({required bool enabled, required TextEditingController controller}) {
    if (!enabled) return 0;
    return RestoreHeightUtils.parse(controller.text);
  }
}
