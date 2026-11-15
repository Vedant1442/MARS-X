import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../shared/widgets/data_badge.dart';

class MissionReportScreen extends ConsumerWidget {
  const MissionReportScreen({super.key});

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final st = ref.read(plannerProvider);
    final route = st.activeRoute;
    final risk = ref.read(riskProvider);
    final lms = ref.read(landmarksProvider);
    if (route == null || risk == null) return;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('MARS-X CANDIDATE MISSION REPORT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text('Mode: ${route.mode.name.toUpperCase()}  |  Safety: NOT CERTIFIED'),
            pw.Divider(),
            pw.Text('Distance: ${(route.distanceM / 1000).toStringAsFixed(2)} km'),
            pw.Text('Max slope: ${route.maxSlopeDeg.toStringAsFixed(1)} deg (DERIVED from CTX DTM at 100 m grid spacing)'),
            pw.Text('Elevation gain: ${route.elevGainM.toStringAsFixed(0)} m (DERIVED)'),
            pw.Text('Simulated risk score: ${risk.score}/100 (${risk.level})'),
            pw.Text('Simulated science score: ${risk.scienceScore}/100'),
            pw.Text('Simulated time: ${risk.estimatedTimeMin.toStringAsFixed(0)} min'),
            pw.SizedBox(height: 12),
            pw.Text('Landmarks (${lms.length}):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            for (final l in lms)
              pw.Text('${l.n}. ${l.name} — ${l.desc}'),
            pw.SizedBox(height: 12),
            pw.Text('Limitations: Terrain is aggregated from USGS CTX 20 m DEM to 100 m route cells. Small rocks and other sub-cell hazards are unknown. Risk, time, targets, and pressure are simulated.'),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mars_x_mission_report.pdf');
    await file.writeAsBytes(await doc.save());
    await Share.shareXFiles([XFile(file.path)], text: 'MARS-X Candidate Mission Report');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(plannerProvider);
    final route = st.activeRoute;
    final risk = ref.watch(riskProvider);
    final lms = ref.watch(landmarksProvider);

    if (route == null || risk == null) {
      return const Column(
        children: [
          HonestyBanner(),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Generate a route on the Map tab to view the mission report.'),
              ),
            ),
          ),
        ],
      );
    }

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
                  Text('REPORT · ${route.mode.name.toUpperCase()}', style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600)),
                  const DataBadge(DataType.modeled),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _MetricRow('Distance', '${(route.distanceM / 1000).toStringAsFixed(2)} km', DataType.derived),
                      _MetricRow('Max slope', '${route.maxSlopeDeg.toStringAsFixed(1)}°', DataType.derived),
                      _MetricRow('Elevation gain', '${route.elevGainM.toStringAsFixed(0)} m', DataType.derived),
                      _MetricRow('Est. duration', '${risk.estimatedTimeMin.toStringAsFixed(0)} min', DataType.simulated),
                      _MetricRow('Data confidence', route.confidence, DataType.modeled),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('RISK SCORE: ${risk.score}/100 (${risk.level})', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                          const DataBadge(DataType.simulated),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final p in risk.parts) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(p.label, style: const TextStyle(fontSize: 12)),
                            Text('${(p.value * 100).toStringAsFixed(0)}% × ${p.weight}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.dim)),
                          ],
                        ),
                        LinearProgressIndicator(value: p.value, color: MarsTheme.mars, backgroundColor: MarsTheme.line),
                        const SizedBox(height: 6),
                      ],
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
                      const Text('LANDMARKS & PROVENANCE', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                      const Divider(),
                      for (final l in lms)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('${l.n}. ${l.name} — ${l.desc}', style: const TextStyle(fontSize: 12)),
                        ),
                      const Divider(),
                      const Text(
                        'Limitations: Terrain is aggregated from the USGS M20 Jezero CTX 20 m DEM to 100 m route cells. Sub-cell rocks and sand traps are UNKNOWN. Candidate route only; safety is NOT CERTIFIED.',
                        style: TextStyle(fontSize: 12, color: MarsTheme.dim),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _exportPdf(context, ref),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('EXPORT & SHARE PDF REPORT'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String k;
  final String v;
  final DataType type;

  const _MetricRow(this.k, this.v, this.type);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 13, color: MarsTheme.dim)),
          Row(
            children: [
              Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              const SizedBox(width: 8),
              DataBadge(type),
            ],
          ),
        ],
      ),
    );
  }
}
