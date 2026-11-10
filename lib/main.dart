import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/hydration_providers.dart';
import 'presentation/screens/main_tab_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: HydroChimeApp(),
    ),
  );
}

class HydroChimeApp extends ConsumerWidget {
  const HydroChimeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
