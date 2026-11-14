import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/theme.dart';
import 'features/environment/environment_screen.dart';
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

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _tab = 0;

  static const _screens = [
    TerrainMapScreen(),
    FollowScreen(),
    MissionReportScreen(),
    EnvironmentAndSavedScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MARS-X · JEZERO', style: TextStyle(fontFamily: 'monospace', fontSize: 15, letterSpacing: 2)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MarsTheme.line),
        ),
      ),
      body: _screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: MarsTheme.paper,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.terrain_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), label: 'Follow'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.storage_outlined), label: 'Data & Saved'),
        ],
      ),
    );
  }
}
