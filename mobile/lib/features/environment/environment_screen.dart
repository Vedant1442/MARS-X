import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/api_service.dart';
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
  MedaEnvironmentData? _liveMeda;
  BackendStatus? _backendStatus;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _missionsFuture = ref.read(missionRepoProvider).listMissions();
    _syncUplink();
  }

  Future<void> _syncUplink() async {
    setState(() => _isSyncing = true);
    final status = await MarsXApiService.checkHealth();
    MedaEnvironmentData? meda;
    if (status.isConnected) {
      meda = await MarsXApiService.fetchEnvironment(sol: 20);
    }
    if (mounted) {
      setState(() {
        _backendStatus = status;
        _liveMeda = meda;
        _isSyncing = false;
      });
    }
  }

  void _reload() {
    setState(() {
      _missionsFuture = ref.read(missionRepoProvider).listMissions();
    });
  }

  Future<void> _openMission(SavedMission mission, TerrainGrid grid) async {
    final georef = grid.georeference;
    if (georef == null) return;
    GridPoint? start;
    GridPoint? end;
    if (mission.gridId == grid.gridId) {
      if (mission.startX >= 0 && mission.startY >= 0 && mission.startX < grid.w && mission.startY < grid.h) {
        start = GridPoint(mission.startX, mission.startY);
      }
      if (mission.endX >= 0 && mission.endY >= 0 && mission.endX < grid.w && mission.endY < grid.h) {
        end = GridPoint(mission.endX, mission.endY);
      }
    } else if (mission.gridId == SavedMission.legacyPatchGridId) {
      final metadata = jsonDecode(await rootBundle.loadString('assets/terrain/jezero-dem.json')) as Map<String, dynamic>;
      final oldGrid = MarsGridReference(
        centerX: (metadata['gridCenterX'] as num).toDouble(),
        centerY: (metadata['gridCenterY'] as num).toDouble(),
        stepX: (metadata['gridStepXM'] as num).toDouble(),
        stepY: (metadata['gridStepYM'] as num).toDouble(),
        radiusM: (metadata['radiusM'] as num).toDouble(),
      );
      final oldStart = oldGrid.pointForCell(mission.startX, mission.startY, TerrainGrid.gridW, TerrainGrid.gridH);
      final oldEnd = oldGrid.pointForCell(mission.endX, mission.endY, TerrainGrid.gridW, TerrainGrid.gridH);
      final s = georef.cellFor(oldStart.longitudeEastDeg, oldStart.latitudePlanetocentricDeg, grid.w, grid.h);
      final e = georef.cellFor(oldEnd.longitudeEastDeg, oldEnd.latitudePlanetocentricDeg, grid.w, grid.h);
      if (s != null) start = GridPoint(s.x, s.y);
      if (e != null) end = GridPoint(e.x, e.y);
    }
    if (start == null || end == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This saved route does not match the installed Jezero map coverage.')),
        );
      }
      return;
    }
    final notifier = ref.read(plannerProvider.notifier);
    notifier.tapCell(grid, start);
    notifier.tapCell(grid, end);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Loaded ${mission.name} on the crater-wide map.')));
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
              // Earth Uplink / Live Railway Backend Card
              Card(
                color: const Color(0xFF1B232E),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (_backendStatus?.isConnected ?? false)
                                      ? const Color(0xFF4ADE80)
                                      : Colors.amber,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'EARTH UPLINK · RAILWAY CLOUD',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          _isSyncing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.sync, size: 18),
                                  tooltip: 'Sync telemetry with Railway',
                                  onPressed: _syncUplink,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (_backendStatus?.isConnected ?? false)
                            ? 'Connected to Mars-X API (${_backendStatus?.terrainSource ?? "HiRISE_DTM"})'
                            : 'Offline / Standalone mode · Local calculation active',
                        style: const TextStyle(fontSize: 11, color: MarsTheme.dim),
                      ),
                      if (_liveMeda != null) ...[
                        const Divider(height: 16, color: Colors.white12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'MEDA OBSERVATIONS (SOL ${_liveMeda!.sol})',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                            const DataBadge(DataType.observed),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricBox(
                                label: 'AIR TEMP (MEAN)',
                                value: '${_liveMeda!.airTempMean.toStringAsFixed(1)}°C',
                                sub: '${_liveMeda!.airTempMin.toStringAsFixed(0)}° / ${_liveMeda!.airTempMax.toStringAsFixed(0)}°',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MetricBox(
                                label: 'GROUND TEMP',
                                value: '${_liveMeda!.groundTempMean.toStringAsFixed(1)}°C',
                                sub: '${_liveMeda!.groundTempMin.toStringAsFixed(0)}° / ${_liveMeda!.groundTempMax.toStringAsFixed(0)}°',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'PDS4 Archive: ${_liveMeda!.sampleCount} samples from TIRS. ${_liveMeda!.citation}',
                          style: const TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Local/Simulated Environmental Baseline Card
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('LOCAL ENVIRONMENTAL BASELINE', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                          DataBadge(DataType.derived),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Atmospheric pressure is computed from HiRISE elevation via barometric law P(h) = P0 * exp(-(h - h0) / 11100 m). Radiation baseline is historical Gale Crater RAD benchmark.',
                        style: TextStyle(fontSize: 12, color: MarsTheme.dim),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

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
                            onTap: grid == null ? null : () => _openMission(m, grid),
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

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final String sub;

  const _MetricBox({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white54)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(sub, style: const TextStyle(fontSize: 9, color: Colors.white38)),
        ],
      ),
    );
  }
}
