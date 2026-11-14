import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../shared/widgets/data_badge.dart';

class FollowScreen extends ConsumerStatefulWidget {
  const FollowScreen({super.key});

  @override
  ConsumerState<FollowScreen> createState() => _FollowScreenState();
}

class _FollowScreenState extends ConsumerState<FollowScreen> {
  bool _showLost = false;
  Timer? _flyTimer;
  int? _flyIdx;

  @override
  void dispose() {
    _flyTimer?.cancel();
    super.dispose();
  }

  void _toggleFlyover(int pathLen) {
    if (_flyTimer != null) {
      _flyTimer?.cancel();
      setState(() {
        _flyTimer = null;
        _flyIdx = null;
      });
      return;
    }
    setState(() => _flyIdx = 0);
    _flyTimer = Timer.periodic(const Duration(milliseconds: 90), (t) {
      if (!mounted) return;
      setState(() {
        if ((_flyIdx ?? 0) + 1 >= pathLen) {
          t.cancel();
          _flyTimer = null;
          _flyIdx = null;
        } else {
          _flyIdx = (_flyIdx ?? 0) + 1;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(terrainGridProvider).valueOrNull;
    final st = ref.watch(plannerProvider);
    final lms = ref.watch(landmarksProvider);
    final notifier = ref.read(plannerProvider.notifier);
    final route = st.activeRoute;

    if (grid == null || route == null || lms.isEmpty) {
      return const Column(
        children: [
          HonestyBanner(),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No active route. Open the Map tab, tap Start & Destination (or Practice Route), then return here to navigate landmark-to-landmark without GPS.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final step = st.landmarkStep.clamp(0, lms.length - 1);
    final cur = lms[step];
    final nxt = step + 1 < lms.length ? lms[step + 1] : null;
    final hereIdx = _flyIdx ?? cur.pathIdx;

    final spots = <FlSpot>[];
    for (var k = 0; k < route.path.length; k++) {
      final p = route.path[k];
      spots.add(FlSpot(k.toDouble(), grid.elev[p.y * grid.w + p.x]));
    }

    final nearest = [...lms]
      ..removeWhere((l) => l.n == cur.n)
      ..sort((a, b) => (a.sM - cur.sM).abs().compareTo((b.sM - cur.sM).abs()));

    return Column(
      children: [
        const HonestyBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('LANDMARK ${cur.n} OF ${lms.length}', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  DataBadge(cur.target != null ? DataType.simulated : DataType.derived),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cur.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(cur.desc, style: const TextStyle(fontSize: 13)),
                      const Divider(),
                      const Text('WHY IT MATTERS', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.dim)),
                      const SizedBox(height: 4),
                      Text(cur.why, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (nxt != null && cur.next != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Transform.rotate(
                          angle: cur.next!.bearingDeg * math.pi / 180.0,
                          child: const Icon(Icons.navigation, size: 36, color: MarsTheme.marsDeep),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NEXT: ${nxt.n}. ${nxt.name}',
                                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                              Text(
                                '${cur.next!.bearingDeg.toStringAsFixed(0)}° ${cur.next!.cardinal} · ${(cur.next!.distM / 1000).toStringAsFixed(2)} km · '
                                '${cur.next!.dElevM >= 0 ? "+" : ""}${cur.next!.dElevM.toStringAsFixed(0)} m · '
                                '${cur.next!.slopeMinDeg.toStringAsFixed(0)}–${cur.next!.slopeMaxDeg.toStringAsFixed(0)}° · '
                                '~${cur.next!.timeMin.toStringAsFixed(0)} min (SIM)',
                                style: const TextStyle(fontSize: 12, color: MarsTheme.dim),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ELEVATION PROFILE (m)', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.dim)),
                          DataBadge(DataType.derived),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 140,
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: true, drawVerticalLine: false),
                            titlesData: const FlTitlesData(show: false),
                            borderData: FlBorderData(show: true, border: Border.all(color: MarsTheme.line)),
                            extraLinesData: ExtraLinesData(
                              verticalLines: [
                                VerticalLine(x: hereIdx.toDouble(), color: MarsTheme.gold, strokeWidth: 2.5),
                              ],
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: false,
                                color: MarsTheme.marsDeep,
                                barWidth: 2.2,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: true, color: MarsTheme.mars.withOpacity(0.15)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: step > 0 ? () => notifier.setStep(step - 1) : null,
                      child: const Text('BACK'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: step < lms.length - 1 ? () => notifier.setStep(step + 1) : null,
                      child: const Text('NEXT LANDMARK'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleFlyover(route.path.length),
                      icon: Icon(_flyTimer != null ? Icons.stop : Icons.play_arrow, size: 18),
                      label: Text(_flyTimer != null ? 'STOP FLYOVER' : 'SIMULATED FLYOVER'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _showLost = !_showLost),
                    child: const Text("I'M LOST"),
                  ),
                ],
              ),
              if (_showLost)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NEAREST LANDMARKS TO RE-ANCHOR', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.dim)),
                        for (final l in nearest.take(3))
                          ListTile(
                            dense: true,
                            title: Text('${l.n}. ${l.name}'),
                            trailing: Text('${(l.sM - cur.sM).abs().toStringAsFixed(0)} m'),
                            onTap: () {
                              notifier.setStep(l.n - 1);
                              setState(() => _showLost = false);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
