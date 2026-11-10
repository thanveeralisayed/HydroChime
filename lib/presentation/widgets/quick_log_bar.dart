import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/beverage_type.dart';

class QuickLogBar extends StatelessWidget {
  final void Function(int amountMl, BeverageType type) onLog;
  final VoidCallback onCustomAdd;

  const QuickLogBar({
    super.key,
    required this.onLog,
    required this.onCustomAdd,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);

    return Row(
      children: [
        Expanded(child: _buildPill(amount: 250, palette: palette)),
        const SizedBox(width: 8),
        Expanded(child: _buildPill(amount: 500, palette: palette)),
        const SizedBox(width: 8),
        Expanded(child: _buildPill(amount: 750, palette: palette)),
        const SizedBox(width: 8),
        _buildCustomButton(palette: palette),
      ],
    );
  }

  Widget _buildPill({
    required int amount,
    required HydroChimeColors palette,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onLog(amount, BeverageType.water),
        borderRadius: BorderRadius.circular(9999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }

  Widget _buildCustomButton({required HydroChimeColors palette}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('custom_log_button'),
        onTap: onCustomAdd,
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
