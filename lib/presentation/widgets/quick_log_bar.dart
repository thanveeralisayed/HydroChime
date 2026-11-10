import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/models/beverage_type.dart';

class QuickLogBar extends StatefulWidget {
  final FutureOr<void> Function(int amountMl, BeverageType type) onLog;
  final VoidCallback onCustomAdd;

  const QuickLogBar({
    super.key,
    required this.onLog,
    required this.onCustomAdd,
  });

  @override
  State<QuickLogBar> createState() => _QuickLogBarState();
}

class _QuickLogBarState extends State<QuickLogBar> {
  bool _isSubmitting = false;

  Future<void> _submitLog(int amount, BeverageType type) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.onLog(amount, type);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showBeverageChooser(BuildContext context, int amount) async {
    if (_isSubmitting) return;
    final palette = HydroChimeColors.of(context);
    final chosen = await showModalBottomSheet<BeverageType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Material(
          color: palette.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            side: BorderSide(color: palette.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Log +$amount ml as',
                    style:
                        AppTypography.headlineMedium(color: palette.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ...BeverageType.values.map((type) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        type.displayName,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Text(
                        '${type.multiplier}x',
                        style: TextStyle(
                          color: palette.primaryAtmosphere,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, type),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (chosen != null) {
      await _submitLog(amount, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);

    return Row(
      children: [
        Expanded(child: _buildPill(context, amount: 250, palette: palette)),
        const SizedBox(width: 8),
        Expanded(child: _buildPill(context, amount: 500, palette: palette)),
        const SizedBox(width: 8),
        Expanded(child: _buildPill(context, amount: 750, palette: palette)),
        const SizedBox(width: 8),
        _buildCustomButton(palette: palette),
      ],
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required int amount,
    required HydroChimeColors palette,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSubmitting ? null : () => _submitLog(amount, BeverageType.water),
        onLongPress: _isSubmitting ? null : () => _showBeverageChooser(context, amount),
        borderRadius: BorderRadius.circular(9999),
        child: Opacity(
          opacity: _isSubmitting ? 0.6 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: palette.isDark
                  ? Colors.white.withOpacity(0.03)
                  : palette.surfaceCard,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(
                color: palette.borderSubtle,
                width: 1,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '+$amount',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'ml',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomButton({required HydroChimeColors palette}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('custom_log_button'),
        onTap: _isSubmitting ? null : widget.onCustomAdd,
        borderRadius: BorderRadius.circular(9999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.isDark
                ? Colors.white.withOpacity(0.03)
                : palette.surfaceCard,
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.borderSubtle,
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              color: palette.textSecondary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
