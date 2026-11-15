import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'features/environment/environment_screen.dart';
import 'features/globe/mars_globe_screen.dart';
import 'features/map/terrain_map_screen.dart';
import 'features/report/mission_report_screen.dart';
import 'features/stepper/follow_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MarsXApp()));
}

class MarsXApp extends StatelessWidget {
  const MarsXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MARS-X',
      debugShowCheckedModeBanner: false,
      theme: MarsTheme.light(),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends ConsumerWidget {
  const _HomeShell();

  static const _screens = [
    MarsGlobeScreen(),
    TerrainMapScreen(),
    FollowScreen(),
    MissionReportScreen(),
    EnvironmentAndSavedScreen(),
  ];

  static const _titles = [
    'MARS-X · USGS GLOBE',
    'MARS-X · JEZERO MAP',
    'MARS-X · NAVIGATION',
    'MARS-X · REPORT',
    'MARS-X · DATA & SAVED',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(tabIndexProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[activeTab.clamp(0, _titles.length - 1)],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 2),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MarsTheme.line),
        ),
      ),
      body: IndexedStack(
        index: activeTab.clamp(0, _screens.length - 1),
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeTab.clamp(0, _screens.length - 1),
        onDestinationSelected: (i) => ref.read(tabIndexProvider.notifier).state = i,
        backgroundColor: MarsTheme.paper,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Globe'),
          NavigationDestination(icon: Icon(Icons.terrain_outlined), selectedIcon: Icon(Icons.terrain), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Follow'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.storage_outlined), selectedIcon: Icon(Icons.storage), label: 'Data'),
        ],
      ),
    );
  }
}
