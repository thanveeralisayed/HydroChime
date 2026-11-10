import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/services/local_notification_service.dart';
import '../../data/services/vault_transfer_service.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/services/notification_scheduler.dart';
import '../providers/analytics_provider.dart';
import '../providers/hydration_providers.dart';
import '../widgets/location_picker_section.dart';
import '../widgets/profile_calibration_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _editBaselineDialog(UserProfile profile) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditBaselineDialog(
        initialWeight: profile.weightKg,
        initialCustomBaseline: profile.customBaselineMl,
        onSave: (weightKg, customBaselineMl) async {
          final repo = await ref.read(userProfileRepositoryProvider.future);
          await repo.updateWeight(weightKg);
          await repo.updateCustomBaseline(customBaselineMl);
          ref.invalidate(userProfileProvider);
          ref.invalidate(hydrationNotifierProvider);
          await ref.read(userProfileProvider.future);
          await ref.read(hydrationNotifierProvider.future);
        },
      ),
    );
  }

  Future<void> _editActiveWindowDialog(UserProfile profile) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ActiveWindowDialog(
        initialStart: profile.activeWindowStartHour,
        initialEnd: profile.activeWindowEndHour,
        onSave: (startHour, endHour) async {
          final repo = await ref.read(userProfileRepositoryProvider.future);
          await repo.updateActiveWindow(startHour, endHour);
          ref.invalidate(userProfileProvider);
          ref.invalidate(hydrationNotifierProvider);
          ref.invalidate(analyticsProvider);
          ref.invalidate(pacingScheduleProvider);
          await ref.read(userProfileProvider.future);
          await ref.read(hydrationNotifierProvider.future);
        },
      ),
    );
  }

  void _openLocationSheet(UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsLocationSheet(
        profile: profile,
        rootRef: ref,
      ),
    );
  }

  void _showPrivacyDialog() {
    final palette = HydroChimeColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surfaceElevated,
        title: Text(
          'On-Device Zero-Knowledge Vault',
          style: AppTypography.headlineMedium(color: palette.textPrimary),
        ),
        content: Text(
          'HydroChime stores your intake logs, body metrics, and pacing preferences strictly inside local encrypted-grade SQLite storage on your device.\n\n'
          'No account, telemetry SDK, or cloud sync is used. Weather fetches anonymize coordinates to 2 decimal places (~1.1 km).',
          style: TextStyle(color: palette.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Close',
              style: TextStyle(color: palette.primaryAtmosphere),
            ),
          ),
        ],
      ),
    );
  }

  void _showEfficiencyDetail(String title, String ratio, String description) {
    final palette = HydroChimeColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surfaceElevated,
        title: Text(
          '$title ($ratio)',
          style: AppTypography.headlineMedium(color: palette.textPrimary),
        ),
        content: Text(
          description,
          style: TextStyle(color: palette.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Got it',
              style: TextStyle(color: palette.primaryAtmosphere),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExportVaultDialog() async {
    final vault = await ref.read(vaultExportServiceProvider.future);
    final jsonBackup = await vault.exportToJson();
    String? savedPath;

    if (!mounted) return;
    final palette = HydroChimeColors.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: palette.surfaceElevated,
          title: Text(
            'Vault JSON Backup',
            style: AppTypography.headlineMedium(color: palette.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (savedPath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Saved locally to: $savedPath',
                      style: TextStyle(
                        color: palette.primaryAtmosphere,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Container(
                  width: double.maxFinite,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonBackup,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              key: const Key('export_save_json_button'),
              onPressed: () async {
                try {
                  final path = await ref
                      .read(vaultTransferServiceProvider)
                      .saveTextWithPicker(
                        content: jsonBackup,
                        fileName: 'hydrochime_vault_backup.json',
                        mimeType: 'application/json',
                        dialogTitle: 'Save HydroChime Vault Backup',
                      );
                  if (path != null) {
                    try {
                      await vault.saveJsonBackupToDocuments();
                    } catch (_) {}
                    if (!dialogCtx.mounted) return;
                    setDialogState(() => savedPath = path);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Backup saved to $path')),
                    );
                  }
                } catch (e) {
                  if (!dialogCtx.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Unable to save backup: $e')),
                  );
                }
              },
              icon: Icon(
                Icons.save_alt,
                size: 16,
                color: palette.primaryAtmosphere,
              ),
              label: Text(
                'Save JSON',
                style: TextStyle(color: palette.primaryAtmosphere),
              ),
            ),
            Builder(
              builder: (shareCtx) => TextButton.icon(
                key: const Key('export_share_json_button'),
                onPressed: () async {
                  try {
                    final box = shareCtx.findRenderObject() as RenderBox?;
                    final shareOrigin =
                        (box != null && box.hasSize && !box.size.isEmpty)
                            ? (box.localToGlobal(Offset.zero) & box.size)
                            : null;
                    await ref.read(vaultTransferServiceProvider).shareTextAsFile(
                          content: jsonBackup,
                          fileName: 'hydrochime_vault_backup.json',
                          mimeType: 'application/json',
                          subject: 'HydroChime Privacy Vault Backup',
                          sharePositionOrigin: shareOrigin,
                        );
                  } on VaultTransferUnsupportedException catch (e) {
                    if (!dialogCtx.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  } catch (e) {
                    if (!dialogCtx.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Unable to share backup: $e')),
                    );
                  }
                },
                icon: Icon(
                  Icons.ios_share,
                  size: 16,
                  color: palette.primaryAtmosphere,
                ),
                label: Text(
                  'Share',
                  style: TextStyle(color: palette.primaryAtmosphere),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jsonBackup));
                if (!dialogCtx.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Vault JSON copied to clipboard')),
                );
              },
              child: Text(
                'Copy JSON',
                style: TextStyle(color: palette.primaryAtmosphere),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Close',
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRestoreVaultDialog() async {
    final vault = await ref.read(vaultExportServiceProvider.future);
    final transfer = ref.read(vaultTransferServiceProvider);
    if (!mounted) return;

    final restoredCount = await showDialog<int>(
      context: context,
      builder: (ctx) => _RestoreVaultDialog(
        onRestoreJson: (jsonText) => vault.restoreFromJson(jsonText),
        onRestoreSavedFile: () => vault.restoreFromDocumentsFile(),
        onPickBackupFile: () => transfer.pickBackupJsonContent(),
      ),
    );

    if (restoredCount != null && mounted) {
      ref.invalidate(userProfileProvider);
      ref.invalidate(hydrationNotifierProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(weatherSyncProvider);
      ref.invalidate(pacingScheduleProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restored profile & $restoredCount intake logs cleanly'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final climate = ref.watch(currentClimateProvider);
    final hydrationAsync = ref.watch(hydrationNotifierProvider);
    final pacingAsync = ref.watch(pacingScheduleProvider);
    final versionAsync = ref.watch(appVersionProvider);

    final hydrationState = switch (hydrationAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final pacingState = switch (pacingAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final appVersion = switch (versionAsync) {
      AsyncData(:final value) => value,
      _ => 'v1.0.0',
    };

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: profileAsync.when(
          data: (profile) {
            final climateDeltaMl = hydrationState?.breakdown.climateDeltaMl ?? 0;
            final deltaLabel = profile.weatherAdaptationEnabled
                ? '(+$climateDeltaMl ml today)'
                : '(Adaptation paused)';

            String pacingSubtext;
            final osSchedulingSupported =
                pacingState?.osSchedulingSupported ?? true;
            if (!profile.mindfulPacingEnabled) {
              pacingSubtext = 'Daytime reminders paused';
            } else if ((hydrationState?.remainingMl ?? 1) <= 0) {
              pacingSubtext = "Today's goal completed — chimes paused";
            } else if (!osSchedulingSupported) {
              if (pacingState?.nextChime != null) {
                final next = pacingState!.nextChime!;
                pacingSubtext =
                    'In-app pacing: next ${DateFormat('h:mm a').format(next.scheduledTime)} (~${next.recommendedVolumeMl} ml) • OS background chimes unavailable on this platform';
              } else {
                pacingSubtext =
                    'In-app pacing active • OS background chimes unavailable on this platform';
              }
            } else if (pacingState?.nextChime != null) {
              final next = pacingState!.nextChime!;
              pacingSubtext =
                  'Next chime ${DateFormat('h:mm a').format(next.scheduledTime)} (~${next.recommendedVolumeMl} ml)';
            } else {
              pacingSubtext = 'Gentle daytime reminders';
            }

            final weightText = formatWeightKg(profile.weightKg);

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HydroChime',
                            style: AppTypography.headlineMedium(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: palette.primaryAtmosphere,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${profile.cityName} • ${climate.temperatureCelsius.round()}°C',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: palette.isDark
                            ? Colors.white.withOpacity(0.03)
                            : palette.surfaceCard,
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: palette.borderSubtle),
                      ),
                      child: Text(
                        'SETTINGS',
                        style: AppTypography.labelMicro(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Section 1: Baseline Goal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Baseline Target',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMicro(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      key: const Key('edit_baseline_button'),
                      onTap: () => _editBaselineDialog(profile),
                      child: Row(
                        children: [
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: palette.primaryAtmosphere,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.north_east,
                            size: 13,
                            color: palette.primaryAtmosphere,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _editBaselineDialog(profile),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${profile.effectiveBaselineMl}',
                              style: TextStyle(
                                fontFamily: AppTypography.headlineFontFamily,
                                fontSize: 38,
                                fontWeight: FontWeight.w300,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ml / day',
                              style: TextStyle(
                                color: palette.primaryAtmosphere,
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.customBaselineMl != null
                            ? 'Custom baseline active • $weightText profile'
                            : 'Adaptive pacing calibrated for $weightText',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildDivider(palette),
                const SizedBox(height: 24),
                // Section 2: Climate & Adaptation
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weather Adaptation',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            children: [
                              Text(
                                'Auto-adjusts for heat & humidity ',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                deltaLabel,
                                style: TextStyle(
                                  color: palette.primaryAtmosphere,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: profile.weatherAdaptationEnabled,
                      activeColor: palette.primaryAtmosphere,
                      onChanged: (val) async {
                        final repo = await ref
                            .read(userProfileRepositoryProvider.future);
                        await repo.setWeatherAdaptation(val);
                        ref.invalidate(userProfileProvider);
                        ref.invalidate(hydrationNotifierProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  key: const Key('settings_location_row'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openLocationSheet(profile),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Weather location',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  profile.cityName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.my_location,
                                size: 13,
                                color: palette.primaryAtmosphere,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildDivider(palette),
                const SizedBox(height: 24),
                // Section 3: Mindful Pacing
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mindful Pacing',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pacingSubtext,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: profile.mindfulPacingEnabled,
                      activeColor: palette.primaryAtmosphere,
                      onChanged: (val) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final repo = await ref
                            .read(userProfileRepositoryProvider.future);
                        await repo.setMindfulPacing(val);
                        if (val) {
                          final granted = await ref
                              .read(notificationServiceProvider)
                              .requestPermissions();
                          if (!granted && mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Notification permission not granted — chimes remain visible in-app.',
                                ),
                              ),
                            );
                          }
                        }
                        ref.invalidate(userProfileProvider);
                        ref.invalidate(pacingScheduleProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  key: const Key('active_window_row'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _editActiveWindowDialog(profile),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Active window',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  '${formatHour12(profile.activeWindowStartHour)} – ${formatHour12(profile.activeWindowEndHour)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.edit_outlined,
                                size: 13,
                                color: palette.primaryAtmosphere,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  key: const Key('test_chime_button'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final status = await ref
                        .read(notificationServiceProvider)
                        .showTestChime();
                    if (!context.mounted) return;
                    final message = switch (status) {
                      TestChimeStatus.sent => 'Sent test Mindful Hydration chime',
                      TestChimeStatus.permissionDenied =>
                        'Notification permission not granted — test chime could not be delivered.',
                      TestChimeStatus.unavailable =>
                        'Notifications unavailable on this platform',
                    };
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(message),
                        ),
                      );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Notification chime check',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Send test chime',
                              style: TextStyle(
                                color: palette.primaryAtmosphere,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.notifications_active_outlined,
                              size: 13,
                              color: palette.primaryAtmosphere,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildDivider(palette),
                const SizedBox(height: 20),
                // Appearance Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dark Obsidian Theme',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile.isDarkMode
                                ? 'True Black & Electric Cyan'
                                : 'Soft Parchment & Botanical Green',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: profile.isDarkMode,
                      activeColor: palette.primaryAtmosphere,
                      onChanged: (val) async {
                        final repo = await ref
                            .read(userProfileRepositoryProvider.future);
                        await repo.setDarkMode(val);
                        ref.invalidate(userProfileProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDivider(palette),
                const SizedBox(height: 24),
                // Section 4: Beverage Efficiencies
                Text(
                  'BEVERAGE EFFICIENCIES',
                  style: AppTypography.labelMicro(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildEfficiencyRow(
                  palette,
                  'Pure Water',
                  '1.0x',
                  false,
                  () => _showEfficiencyDetail(
                    'Pure Water',
                    '1.0x',
                    'Standard biological absorption baseline. 250 ml ingested equals 250 ml net hydration credit.',
                  ),
                ),
                const SizedBox(height: 12),
                _buildEfficiencyRow(
                  palette,
                  'Electrolytes & Minerals',
                  '1.45x',
                  true,
                  () => _showEfficiencyDetail(
                    'Electrolytes & Minerals',
                    '1.45x',
                    'Sodium and potassium co-transport accelerates intestinal water retention during heat or exertion.',
                  ),
                ),
                const SizedBox(height: 12),
                _buildEfficiencyRow(
                  palette,
                  'Herbal Tea',
                  '1.0x',
                  false,
                  () => _showEfficiencyDetail(
                    'Herbal Tea',
                    '1.0x',
                    'Caffeine-free infusions hydrate equivalently to spring water.',
                  ),
                ),
                const SizedBox(height: 12),
                _buildEfficiencyRow(
                  palette,
                  'Coffee & Black Tea',
                  '0.8x',
                  false,
                  () => _showEfficiencyDetail(
                    'Coffee & Black Tea',
                    '0.8x',
                    'Mild diuretic scalar adjusts net retention slightly while still contributing positively to daily hydration.',
                  ),
                ),
                const SizedBox(height: 28),
                _buildDivider(palette),
                const SizedBox(height: 24),
                // Section 5: Data & Privacy Vault
                InkWell(
                  key: const Key('privacy_vault_row'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showPrivacyDialog,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: palette.primaryAtmosphere,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'All data stays strictly on device.',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.info_outline,
                          color: palette.textTertiary,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('settings_export_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          side: BorderSide(color: palette.borderSubtle),
                          foregroundColor: palette.textPrimary,
                        ),
                        onPressed: _openExportVaultDialog,
                        icon: Icon(
                          Icons.download,
                          color: palette.primaryAtmosphere,
                          size: 16,
                        ),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Export',
                            maxLines: 1,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('settings_restore_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          side: BorderSide(color: palette.borderSubtle),
                          foregroundColor: palette.textPrimary,
                        ),
                        onPressed: _openRestoreVaultDialog,
                        icon: Icon(
                          Icons.settings_backup_restore,
                          color: palette.textSecondary,
                          size: 16,
                        ),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Restore',
                            maxLines: 1,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Center(
                  child: Text(
                    'HYDROCHIME • $appVersion',
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 11,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            );
          },
          loading: () => Center(
            child: CircularProgressIndicator(color: palette.primaryVital),
          ),
          error: (err, _) => Center(
            child: Text('Error: $err',
                style: const TextStyle(color: Colors.red)),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(HydroChimeColors palette) {
    return Container(
      height: 1,
      color: palette.borderSubtle,
    );
  }

  Widget _buildEfficiencyRow(
    HydroChimeColors palette,
    String name,
    String factor,
    bool isHighlighted,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? palette.primaryAtmosphere
                          : palette.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight:
                            isHighlighted ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              factor,
              style: TextStyle(
                color: isHighlighted
                    ? palette.primaryAtmosphere
                    : palette.textSecondary,
                fontSize: 12,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsLocationSheet extends StatefulWidget {
  final UserProfile profile;
  final WidgetRef rootRef;

  const _SettingsLocationSheet({
    required this.profile,
    required this.rootRef,
  });

  @override
  State<_SettingsLocationSheet> createState() => _SettingsLocationSheetState();
}

class _SettingsLocationSheetState extends State<_SettingsLocationSheet> {
  late LocationSelection _selected;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = kDefaultCityPresets.firstWhere(
      (c) => c.name == widget.profile.cityName,
      orElse: () => LocationSelection(
        widget.profile.cityName,
        widget.profile.latitude,
        widget.profile.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: palette.borderSubtle),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weather Location Calibration',
                  style: AppTypography.headlineMedium(color: palette.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quantized to 0.01° (~1.1 km) for on-device weather privacy.',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                LocationPickerSection(
                  selected: _selected,
                  rootRef: widget.rootRef,
                  onSelected: (loc) => setState(() {
                    _selected = loc;
                    _error = null;
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryVital,
                      foregroundColor:
                          palette.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() {
                              _isSaving = true;
                              _error = null;
                            });
                            try {
                              final oldProfile = await widget.rootRef
                                  .read(userProfileProvider.future);
                              final locationChanged =
                                  (oldProfile.latitude - _selected.latitude)
                                          .abs() >
                                      0.001 ||
                                  (oldProfile.longitude - _selected.longitude)
                                          .abs() >
                                      0.001 ||
                                  oldProfile.cityName != _selected.name;

                              final repo = await widget.rootRef
                                  .read(userProfileRepositoryProvider.future);
                              await repo.updateLocation(
                                _selected.name,
                                _selected.latitude,
                                _selected.longitude,
                              );
                              widget.rootRef.invalidate(userProfileProvider);
                              await widget.rootRef
                                  .read(userProfileProvider.future);
                              if (locationChanged) {
                                await widget.rootRef
                                    .read(weatherSyncProvider.future);
                              }
                              widget.rootRef
                                  .invalidate(hydrationNotifierProvider);
                              await widget.rootRef
                                  .read(hydrationNotifierProvider.future);
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (mounted) {
                                setState(
                                  () => _error = 'Unable to save location: $e',
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isSaving = false);
                              }
                            }
                          },
                    child: _isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  palette.isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : const Text('Save Location'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditBaselineDialog extends StatefulWidget {
  final double initialWeight;
  final int? initialCustomBaseline;
  final Future<void> Function(double weightKg, int? customBaselineMl) onSave;

  const _EditBaselineDialog({
    required this.initialWeight,
    required this.initialCustomBaseline,
    required this.onSave,
  });

  @override
  State<_EditBaselineDialog> createState() => _EditBaselineDialogState();
}

class _EditBaselineDialogState extends State<_EditBaselineDialog> {
  late final TextEditingController _weightController;
  late final TextEditingController _baselineController;
  String? _error;
  bool _isSaving = false;

  String _initialWeightText(double w) {
    final rounded1 = double.parse(w.toStringAsFixed(1));
    if (rounded1 == rounded1.roundToDouble()) {
      return rounded1.toInt().toString();
    }
    return rounded1.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: _initialWeightText(widget.initialWeight),
    );
    _baselineController = TextEditingController(
      text: widget.initialCustomBaseline?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _baselineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    return AlertDialog(
      backgroundColor: palette.surfaceElevated,
      title: Text(
        'Calibrate Baseline Target',
        style: TextStyle(color: palette.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              labelText: 'Body Weight (kg)',
              labelStyle: TextStyle(color: palette.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.primaryVital),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baselineController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              labelText: 'Custom Baseline Override (ml, optional)',
              hintText: 'Leave empty for weight × 35',
              hintStyle: TextStyle(color: palette.textTertiary, fontSize: 12),
              labelStyle: TextStyle(color: palette.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.primaryVital),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: palette.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primaryVital,
            foregroundColor: palette.isDark ? Colors.black : Colors.white,
          ),
          onPressed: _isSaving
              ? null
              : () async {
                  final weight = double.tryParse(_weightController.text.trim());
                  if (weight == null || weight < 25 || weight > 250) {
                    setState(
                      () => _error = 'Enter weight between 25 and 250 kg',
                    );
                    return;
                  }
                  final rawBase = _baselineController.text.trim();
                  int? customBase;
                  if (rawBase.isNotEmpty) {
                    customBase = int.tryParse(rawBase);
                    if (customBase == null ||
                        customBase < 800 ||
                        customBase > 8000) {
                      setState(
                        () => _error = 'Custom baseline must be 800–8000 ml',
                      );
                      return;
                    }
                  }

                  setState(() {
                    _isSaving = true;
                    _error = null;
                  });
                  try {
                    await widget.onSave(weight, customBase);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => _error = 'Unable to save baseline: $e',
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isSaving = false);
                    }
                  }
                },
          child: _isSaving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.isDark ? Colors.black : Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _ActiveWindowDialog extends StatefulWidget {
  final int initialStart;
  final int initialEnd;
  final Future<void> Function(int startHour, int endHour) onSave;

  const _ActiveWindowDialog({
    required this.initialStart,
    required this.initialEnd,
    required this.onSave,
  });

  @override
  State<_ActiveWindowDialog> createState() => _ActiveWindowDialogState();
}

class _ActiveWindowDialogState extends State<_ActiveWindowDialog> {
  late int _startHour;
  late int _endHour;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startHour = widget.initialStart;
    _endHour = widget.initialEnd;
  }

  void _stepStart(int delta) {
    if (_isSaving) return;
    setState(() {
      var next = (_startHour + delta + 24) % 24;
      if (next == _endHour) {
        next = (next + delta + 24) % 24;
      }
      _startHour = next;
    });
  }

  void _stepEnd(int delta) {
    if (_isSaving) return;
    setState(() {
      var next = (_endHour + delta + 24) % 24;
      if (next == _startHour) {
        next = (next + delta + 24) % 24;
      }
      _endHour = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    final spanHours =
        NotificationScheduler.resolveWindowHours(_startHour, _endHour);
    final isOvernight = _endHour < _startHour;

    return AlertDialog(
      backgroundColor: palette.surfaceElevated,
      title: Text(
        'Active Hydration Window',
        style: TextStyle(color: palette.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Wake: ${formatHour12(_startHour)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      key: const Key('start_hour_dec'),
                      tooltip: 'Earlier start hour',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSaving ? null : () => _stepStart(-1),
                      icon: Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: palette.primaryAtmosphere,
                      ),
                    ),
                    IconButton(
                      key: const Key('start_hour_inc'),
                      tooltip: 'Later start hour',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSaving ? null : () => _stepStart(1),
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: palette.primaryAtmosphere,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [5, 6, 7, 8, 9, 10].map((h) {
                final selected = _startHour == h;
                return ChoiceChip(
                  label: Text(
                    formatHour12(h),
                    style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? (palette.isDark ? Colors.black : Colors.white)
                          : palette.textPrimary,
                    ),
                  ),
                  selected: selected,
                  selectedColor: palette.primaryVital,
                  backgroundColor: palette.surfaceCard,
                  onSelected: _isSaving
                      ? null
                      : (_) {
                          if (h != _endHour) {
                            setState(() => _startHour = h);
                          }
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sleep: ${formatHour12(_endHour)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      key: const Key('end_hour_dec'),
                      tooltip: 'Earlier sleep hour',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSaving ? null : () => _stepEnd(-1),
                      icon: Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: palette.primaryAtmosphere,
                      ),
                    ),
                    IconButton(
                      key: const Key('end_hour_inc'),
                      tooltip: 'Later sleep hour',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSaving ? null : () => _stepEnd(1),
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: palette.primaryAtmosphere,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [19, 20, 21, 22, 23].map((h) {
                final selected = _endHour == h;
                return ChoiceChip(
                  label: Text(
                    formatHour12(h),
                    style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? (palette.isDark ? Colors.black : Colors.white)
                          : palette.textPrimary,
                    ),
                  ),
                  selected: selected,
                  selectedColor: palette.primaryVital,
                  backgroundColor: palette.surfaceCard,
                  onSelected: _isSaving
                      ? null
                      : (_) {
                          if (h != _startHour) {
                            setState(() => _endHour = h);
                          }
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              isOvernight
                  ? 'Active span: ${spanHours}h (Overnight shift)'
                  : 'Active span: ${spanHours}h',
              style: TextStyle(
                color: palette.primaryAtmosphere,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: palette.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primaryVital,
            foregroundColor: palette.isDark ? Colors.black : Colors.white,
          ),
          onPressed: _isSaving
              ? null
              : () async {
                  setState(() {
                    _isSaving = true;
                    _error = null;
                  });
                  try {
                    await widget.onSave(_startHour, _endHour);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => _error = 'Unable to save active window: $e',
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isSaving = false);
                    }
                  }
                },
          child: _isSaving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.isDark ? Colors.black : Colors.white,
                  ),
                )
              : const Text('Save Window'),
        ),
      ],
    );
  }
}

class _RestoreVaultDialog extends StatefulWidget {
  final Future<int> Function(String jsonText) onRestoreJson;
  final Future<int> Function() onRestoreSavedFile;
  final Future<String?> Function() onPickBackupFile;

  const _RestoreVaultDialog({
    required this.onRestoreJson,
    required this.onRestoreSavedFile,
    required this.onPickBackupFile,
  });

  @override
  State<_RestoreVaultDialog> createState() => _RestoreVaultDialogState();
}

class _RestoreVaultDialogState extends State<_RestoreVaultDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _isBusy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);
    return AlertDialog(
      backgroundColor: palette.surfaceElevated,
      title: Text(
        'Restore Privacy Vault',
        style: TextStyle(color: palette.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('restore_json_input'),
              controller: _controller,
              maxLines: 5,
              enabled: !_isBusy,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: 'Paste exported HydroChime JSON backup...',
                hintStyle: TextStyle(color: palette.textTertiary, fontSize: 12),
                errorText: _error,
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.primaryVital),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('restore_pick_file_button'),
              onPressed: _isBusy
                  ? null
                  : () async {
                      setState(() {
                        _isBusy = true;
                        _error = null;
                      });
                      try {
                        final picked = await widget.onPickBackupFile();
                        if (picked == null) return;
                        final count = await widget.onRestoreJson(picked);
                        if (context.mounted) Navigator.pop(context, count);
                      } on FormatException catch (e) {
                        if (mounted) setState(() => _error = e.message);
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => _error = 'Failed to pick backup file: $e',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isBusy = false);
                      }
                    },
              icon: Icon(
                Icons.upload_file,
                size: 16,
                color: palette.primaryAtmosphere,
              ),
              label: Text(
                'Pick Backup File (.json)...',
                style: TextStyle(color: palette.primaryAtmosphere, fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: _isBusy
                  ? null
                  : () async {
                      setState(() {
                        _isBusy = true;
                        _error = null;
                      });
                      try {
                        final count = await widget.onRestoreSavedFile();
                        if (context.mounted) Navigator.pop(context, count);
                      } on FormatException catch (e) {
                        if (mounted) setState(() => _error = e.message);
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => _error = 'Failed to load backup file: $e',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isBusy = false);
                      }
                    },
              icon: Icon(
                Icons.folder_open,
                size: 16,
                color: palette.textSecondary,
              ),
              label: Text(
                'Load Latest Local Backup File',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: palette.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.primaryVital,
            foregroundColor: palette.isDark ? Colors.black : Colors.white,
          ),
          onPressed: _isBusy
              ? null
              : () async {
                  final raw = _controller.text.trim();
                  if (raw.isEmpty) {
                    setState(
                      () => _error = 'Paste backup JSON or choose a file above',
                    );
                    return;
                  }
                  setState(() {
                    _isBusy = true;
                    _error = null;
                  });
                  try {
                    final count = await widget.onRestoreJson(raw);
                    if (context.mounted) Navigator.pop(context, count);
                  } on FormatException catch (e) {
                    if (mounted) setState(() => _error = e.message);
                  } catch (e) {
                    if (mounted) {
                      setState(() => _error = 'Failed to restore backup: $e');
                    }
                  } finally {
                    if (mounted) setState(() => _isBusy = false);
                  }
                },
          child: _isBusy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.isDark ? Colors.black : Colors.white,
                  ),
                )
              : const Text('Restore Backup'),
        ),
      ],
    );
  }
}
