import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/hydration_providers.dart';
import 'presentation/screens/main_tab_shell.dart';

Future<void> initializeHydroChimeRuntime() async {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeHydroChimeRuntime();
  runApp(
    const ProviderScope(
      child: HydroChimeApp(),
    ),
  );
}

class HydroChimeApp extends ConsumerStatefulWidget {
  final DateTime Function()? nowProvider;

  const HydroChimeApp({super.key, this.nowProvider});

  @override
  ConsumerState<HydroChimeApp> createState() => _HydroChimeAppState();
}

class _HydroChimeAppState extends ConsumerState<HydroChimeApp>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;

  DateTime _currentNow() => (widget.nowProvider ?? DateTime.now)();

  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = _currentNow();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final delay = nextMidnight.difference(now);
    _midnightTimer = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      () async {
        if (!mounted) return;
        await ref
            .read(hydrationNotifierProvider.notifier)
            .refreshIfNewDay(now: _currentNow());
        if (!mounted) return;
        _scheduleMidnightRollover();
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRollover();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref
          .read(hydrationNotifierProvider.notifier)
          .refreshIfNewDay(now: _currentNow());
      _scheduleMidnightRollover();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final isDarkMode = switch (profileAsync) {
      AsyncData(:final value) => value.isDarkMode,
      _ => true,
    };

    return MaterialApp(
      title: 'HydroChime',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MainTabShell(),
    );
  }
}
