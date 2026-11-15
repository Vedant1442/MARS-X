import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/mission_repo.dart';
import '../../domain/routing/astar.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../shared/widgets/data_badge.dart';

class EnvironmentAndSavedScreen extends ConsumerStatefulWidget {
  const EnvironmentAndSavedScreen({super.key});

  @override
  ConsumerState<EnvironmentAndSavedScreen> createState() => _EnvironmentAndSavedScreenState();
}

class _EnvironmentAndSavedScreenState extends ConsumerState<EnvironmentAndSavedScreen> {
  late Future<List<SavedMission>> _missionsFuture;

  @override
  void initState() {
    super.initState();
    _missionsFuture = ref.read(missionRepoProvider).listMissions();
  }

  void _reload() {
    setState(() {
      _missionsFuture = ref.read(missionRepoProvider).listMissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(terrainGridProvider).valueOrNull;

    return Column(
      children: [
        const HonestyBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ENVIRONMENT · ARCHIVED, NOT LIVE', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                          DataBadge(DataType.unknown),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Perseverance MEDA & Curiosity RAD: archived mission subsets are not yet bundled in this build. Spatial pressure is SIMULATED from HiRISE elevation using P(h) = P0 * exp(-(h - h0) / 11100 m). Radiation is HISTORICAL (Gale Crater, other location).',
                        style: TextStyle(fontSize: 12, color: MarsTheme.dim),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 15 Jezero Features Catalog
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('15 EXPEDITION LANDMARKS & CATALOGUE', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                          DataBadge(DataType.observed),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Official Mars 2020 Perseverance exploration features mapped on the HiRISE grid:', style: TextStyle(fontSize: 11, color: MarsTheme.dim)),
                      const Divider(),
                      for (final t in kDemoTargets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.asset(
                                  t.imagePath,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(width: 48, height: 48, color: MarsTheme.line, child: const Icon(Icons.image_not_supported, size: 16)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${t.name} (${t.x}, ${t.y})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    Text('${t.type} · Significance: ${t.significance}', style: const TextStyle(fontSize: 10, color: MarsTheme.dim)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SAVED MISSIONS (SQLITE OFFLINE)', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _reload),
                ],
              ),
              FutureBuilder<List<SavedMission>>(
                future: _missionsFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No saved missions yet. Plan a route on the Map tab and tap SAVE MISSION OFFLINE.'),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final m in items)
                        Card(
                          child: ListTile(
                            title: Text(m.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                            subtitle: Text('${(m.distanceM / 1000).toStringAsFixed(2)} km · Risk ${m.riskScore}/100 · (${m.startX},${m.startY}) → (${m.endX},${m.endY})'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                if (m.id != null) {
                                  await ref.read(missionRepoProvider).deleteMission(m.id!);
                                  _reload();
                                }
                              },
                            ),
                            onTap: grid == null
                                ? null
                                : () {
                                    final notifier = ref.read(plannerProvider.notifier);
                                    notifier.tapCell(grid, GridPoint(m.startX, m.startY));
                                    notifier.tapCell(grid, GridPoint(m.endX, m.endY));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Loaded ${m.name}.')),
                                    );
                                  },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
