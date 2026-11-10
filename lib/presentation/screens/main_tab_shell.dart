import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../providers/hydration_providers.dart';
import 'analytics_screen.dart';
import 'climate_hydration_screen.dart';
import 'settings_screen.dart';
import 'today_dashboard_screen.dart';

class MainTabShell extends ConsumerWidget {
  const MainTabShell({super.key});

  static const List<Widget> _screens = [
    TodayDashboardScreen(),
    ClimateHydrationScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(mainTabIndexProvider);
    final palette = HydroChimeColors.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.black.withOpacity(0.92)
              : palette.surfaceCard.withOpacity(0.96),
          border: Border(
            top: BorderSide(
              color: palette.borderSubtle,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  ref: ref,
                  currentIndex: currentIndex,
                  palette: palette,
                  index: 0,
                  label: 'Today',
                  icon: Icons.water_drop_outlined,
                  activeIcon: Icons.water_drop,
                ),
                _buildNavItem(
                  ref: ref,
                  currentIndex: currentIndex,
                  palette: palette,
                  index: 1,
                  label: 'Climate',
                  icon: Icons.cloud_outlined,
                  activeIcon: Icons.cloud,
                ),
                _buildNavItem(
                  ref: ref,
                  currentIndex: currentIndex,
                  palette: palette,
                  index: 2,
                  label: 'Analytics',
                  icon: Icons.insights_outlined,
                  activeIcon: Icons.insights,
                ),
                _buildNavItem(
                  ref: ref,
                  currentIndex: currentIndex,
                  palette: palette,
                  index: 3,
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required WidgetRef ref,
    required int currentIndex,
    required HydroChimeColors palette,
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => ref.read(mainTabIndexProvider.notifier).setTab(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSelected ? activeIcon : icon,
            color: isSelected
                ? palette.primaryAtmosphere
                : palette.textSecondary.withOpacity(0.65),
            size: 22,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? palette.primaryAtmosphere
                  : palette.textSecondary.withOpacity(0.65),
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
