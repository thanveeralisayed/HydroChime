import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/calculators/hydration_calculator.dart';
import '../../domain/models/beverage_type.dart';
import '../../domain/models/intake_log.dart';

typedef BeverageLogFormResult = ({
  int volumeMl,
  BeverageType type,
  DateTime timestamp,
});

Future<BeverageLogFormResult?> showBeverageLogDialog(
  BuildContext context, {
  IntakeLog? initialLog,
  DateTime? targetDate,
}) {
  return showDialog<BeverageLogFormResult>(
    context: context,
    builder: (ctx) => _BeverageLogDialog(
      initialLog: initialLog,
      targetDate: targetDate,
    ),
  );
}

class _BeverageLogDialog extends StatefulWidget {
  final IntakeLog? initialLog;
  final DateTime? targetDate;

  const _BeverageLogDialog({
    this.initialLog,
    this.targetDate,
  });

  @override
  State<_BeverageLogDialog> createState() => _BeverageLogDialogState();
}

class _BeverageLogDialogState extends State<_BeverageLogDialog> {
  late final TextEditingController _controller;
  late BeverageType _selectedType;
  late DateTime _baseDate;
  late TimeOfDay _selectedTime;
  String? _errorText;

  bool get _isEditing => widget.initialLog != null;

  @override
  void initState() {
    super.initState();
    final log = widget.initialLog;
    final anchor = log?.timestamp ?? widget.targetDate ?? DateTime.now();
    _baseDate = DateTime(anchor.year, anchor.month, anchor.day);
    _selectedTime = log != null
        ? TimeOfDay.fromDateTime(log.timestamp)
        : TimeOfDay.fromDateTime(DateTime.now());
    _selectedType = log?.beverageType ?? BeverageType.water;
    _controller = TextEditingController(
      text: (log?.volumeMl ?? 250).toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime _combinedDateTime() {
    return DateTime(
      _baseDate.year,
      _baseDate.month,
      _baseDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final rawVal = int.tryParse(_controller.text.trim()) ?? 0;
    final effectiveVal =
        const HydrationCalculator().calculateEffectiveIntake(rawVal, _selectedType);
    final combinedTime = _combinedDateTime();
    final timeFormatted = DateFormat('h:mm a').format(combinedTime);
    final dateFormatted = DateFormat('MMM d').format(_baseDate);

    return AlertDialog(
      backgroundColor: palette.surfaceElevated,
      title: Text(
        _isEditing ? 'Edit Hydration Entry' : 'Log Beverage & Volume',
        style: AppTypography.headlineMedium(color: palette.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Beverage Type',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BeverageType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Text(
                    type.displayName,
                    style: TextStyle(
                      color: isSelected
                          ? (palette.isDark ? Colors.black : Colors.white)
                          : palette.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: palette.primaryVital,
                  backgroundColor: palette.surfaceCard,
                  side: BorderSide(color: palette.borderSubtle),
                  onSelected: (_) => setState(() => _selectedType = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('beverage_volume_input'),
              controller: _controller,
              keyboardType: TextInputType.number,
              style: TextStyle(color: palette.textPrimary),
              onChanged: (_) => setState(() => _errorText = null),
              decoration: InputDecoration(
                labelText: 'Volume (mL)',
                errorText: _errorText,
                labelStyle: TextStyle(color: palette.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.primaryVital),
                ),
                errorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
                focusedErrorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('beverage_time_picker_row'),
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: palette.primaryAtmosphere,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$dateFormatted • $timeFormatted',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              rawVal > 0
                  ? '$rawVal ml × ${_selectedType.multiplier}x = $effectiveVal ml effective'
                  : 'Efficiency multiplier: ${_selectedType.multiplier}x',
              style: TextStyle(
                color: palette.primaryAtmosphere,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primaryVital,
            foregroundColor: palette.isDark ? Colors.black : Colors.white,
          ),
          onPressed: () {
            final val = int.tryParse(_controller.text.trim());
            if (val == null || val <= 0 || val > 5000) {
              setState(
                () => _errorText = 'Enter a volume between 1 and 5000 ml',
              );
              return;
            }
            Navigator.pop<BeverageLogFormResult>(
              context,
              (
                volumeMl: val,
                type: _selectedType,
                timestamp: _combinedDateTime(),
              ),
            );
          },
          child: Text(_isEditing ? 'Save Changes' : 'Log'),
        ),
      ],
    );
  }
}

