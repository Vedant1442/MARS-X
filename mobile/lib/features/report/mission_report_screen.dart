import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/routing/astar.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../shared/widgets/data_badge.dart';

class RouteTradeoffData {
  final RouteMode mode;
  final String title;
  final String advantageSummary;
  final List<String> advantages;
  final String compromiseSummary;
  final List<String> compromises;
  final Color color;

  const RouteTradeoffData({
    required this.mode,
    required this.title,
    required this.advantageSummary,
    required this.advantages,
    required this.compromiseSummary,
    required this.compromises,
    required this.color,
  });
}

const List<RouteTradeoffData> kRouteTradeoffs = [
  RouteTradeoffData(
    mode: RouteMode.safest,
    title: 'SAFEST ROUTE PROFILE',
    advantageSummary: 'Minimises terrain hazards & physical spacesuit strain.',
    advantages: [
      'Lowest simulated terrain risk (< 25/100, Low Hazard rating).',
      'Hard slope ceiling of 18.0° prevents dangerous scree slips and rollover hazards.',
      'Gentle gradients minimise spacesuit mechanical bearing torque and astronaut cardiovascular strain.',
      'Leaves the highest consumable reserve margin (> 30% life-support safety buffer).',
    ],
    compromiseSummary: 'Longer traverse distance and bypassed scientific targets.',
    compromises: [
      'Requires a 25% to 40% detour around natural obstacles, increasing total distance.',
      'Extended surface exposure time compared to the direct path.',
      'Completely bypasses high-yield geological outcrops situated along steep delta scarps.',
    ],
    color: MarsTheme.sage,
  ),
  RouteTradeoffData(
    mode: RouteMode.fastest,
    title: 'QUICKEST ROUTE PROFILE',
    advantageSummary: 'Minimises travel time and baseline life-support power draw.',
    advantages: [
      'Shortest physical distance and fastest elapsed time between waypoints.',
      'Minimises total passive electrical power consumption of spacesuit avionics.',
      'Direct Euclidean path simplifies visual dead-reckoning and landmark alignment.',
    ],
    compromiseSummary: 'Maximum slope exposure, fatigue, and minimal science sampling.',
    compromises: [
      'Traverses peak slopes up to 25.0°, escalating slip risks and physical fatigue.',
      'Steep uphill ascents dramatically spike metabolic rate and oxygen consumption per minute.',
      'Ignores geological richness; collects minimal scientific value along the way.',
    ],
    color: MarsTheme.atmos,
  ),
  RouteTradeoffData(
    mode: RouteMode.science,
    title: 'MOST SCIENTIFIC ROUTE PROFILE',
    advantageSummary: 'Maximises scientific return and peer-reviewed target sampling.',
    advantages: [
      'Maximises scientific discovery score (85–95/100).',
      'Directly visits verified Mars 2020 formations: Kodiak Butte (delta beds), Séítah (olivine basement), Hawksbill Gap (organic mudstones).',
      'Enforces an automatic detour cap (<= 1.5x quickest) to keep total travel bounded.',
      'Highest sample cache diversity for potential Mars Sample Return (MSR).',
    ],
    compromiseSummary: 'Moderate terrain risk, extra rest breaks, and higher consumable usage.',
    compromises: [
      'Moderate terrain exposure due to routing near cliff edges and rocky outcrop boundaries.',
      'Longer duration requires mandatory 10-minute rest intervals every hour.',
      'Elevated total oxygen (O2) and sublimation cooling water consumption.',
    ],
    color: MarsTheme.mars,
  ),
];

class MissionReportScreen extends ConsumerWidget {
  const MissionReportScreen({super.key});

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final st = ref.read(plannerProvider);
    final route = st.activeRoute;
    final risk = ref.read(riskProvider);
    final lms = ref.read(landmarksProvider);
    if (route == null || risk == null) return;

    final tradeoff = kRouteTradeoffs.firstWhere((t) => t.mode == route.mode);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('MARS-X EXCURSION MISSION REPORT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('JEZERO CRATER DTM', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Selected Mode: ${route.mode.name.toUpperCase()}  |  Evaluation Status: RESEARCH SIMULATION (NOT CERTIFIED)', style: const pw.TextStyle(fontSize: 10, color: PdfColors.red800)),
          pw.Divider(thickness: 1),

          // 1. Traverse Metrics
          pw.Text('1. TRAVERSE METRICS & ESTIMATES', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Bullet(text: 'Total Distance: ${(route.distanceM / 1000).toStringAsFixed(2)} km (Planetocentric Mars R = 3,396.19 km)'),
          pw.Bullet(text: 'Max Terrain Slope: ${route.maxSlopeDeg.toStringAsFixed(1)} deg (Derived from USGS HiRISE DTM)'),
          pw.Bullet(text: 'Elevation Gain: ${route.elevGainM.toStringAsFixed(0)} m'),
          pw.Bullet(text: 'Simulated Risk Score: ${risk.score}/100 [Level: ${risk.level}]'),
          pw.Bullet(text: 'Simulated Science Return: ${risk.scienceScore}/100'),
          pw.Bullet(text: 'Total Duration: ${risk.consumables.activeWalkingMin.toStringAsFixed(0)}m walk + ${risk.consumables.restStopsMin.toStringAsFixed(0)}m mandatory rest = ${risk.consumables.totalEvaMin.toStringAsFixed(0)}m total'),

          pw.SizedBox(height: 12),

          // 2. Human EVA Consumables
          pw.Text('2. HUMAN EVA LIFE-SUPPORT CONSUMABLES (SIMULATED)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Bullet(text: 'Crew Configuration: 2 Astronauts (NASA Apollo/Artemis Buddy Protocol)'),
          pw.Bullet(text: 'Oxygen Depletion: ${risk.consumables.oxygenKg.toStringAsFixed(2)} kg O2 total'),
          pw.Bullet(text: 'Suit Battery Draw: ${risk.consumables.batteryKwh.toStringAsFixed(2)} kWh total'),
          pw.Bullet(text: 'Sublimator Cooling Water: ${risk.consumables.coolingWaterKg.toStringAsFixed(2)} kg H2O'),

          pw.SizedBox(height: 12),

          // 3. Trade-off Analysis: Advantages vs Compromises
          pw.Text('3. ROUTE TRADE-OFF ANALYSIS: ADVANTAGES VS COMPROMISES', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Selected: ${tradeoff.title}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 4),
          pw.Text('Key Advantages:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          for (final a in tradeoff.advantages) pw.Bullet(text: a),
          pw.SizedBox(height: 4),
          pw.Text('Operational Compromises:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          for (final c in tradeoff.compromises) pw.Bullet(text: c),

          pw.SizedBox(height: 12),

          // 4. Landmarks
          pw.Text('4. NO-GPS DEAD-RECKONING WAYPOINTS (${lms.length})', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final l in lms)
            pw.Text('${l.n}. ${l.name} (Coord: ${l.pt.x}, ${l.pt.y}) — ${l.desc} [${l.why}]', style: const pw.TextStyle(fontSize: 9)),

          pw.SizedBox(height: 16),
          pw.Divider(thickness: 0.5),
          pw.Text(
            'LIMITATIONS & PROVENANCE: Base elevation resampled from USGS HiRISE DTM DTEEC_045994_1985_046060_1985_U01 at 35.99 m/cell. Sub-cell boulders and dust drifts are unknown. Pressure, risk, and consumable models are SIMULATED.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mars_x_mission_report.pdf');
    await file.writeAsBytes(await doc.save());
    await Share.shareXFiles([XFile(file.path)], text: 'MARS-X Candidate Excursion Report');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(plannerProvider);
    final route = st.activeRoute;
    final risk = ref.watch(riskProvider);
    final lms = ref.watch(landmarksProvider);

    if (route == null || risk == null) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_late_outlined, size: 48, color: MarsTheme.dim),
                SizedBox(height: 12),
                Text(
                  'NO MISSION REPORT GENERATED',
                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Plan a route on the Map tab to view the comprehensive mission debrief, trade-off analysis, and export PDF.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: MarsTheme.dim),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeTradeoff = kRouteTradeoffs.firstWhere((t) => t.mode == route.mode);

    return Scaffold(
      backgroundColor: MarsTheme.bg,
      body: Column(
        children: [
          const HonestyBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('REPORT · ${route.mode.name.toUpperCase()}', style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold)),
                    const DataBadge(DataType.modeled),
                  ],
                ),
                const SizedBox(height: 8),

                // 1. PRIMARY TRADE-OFF CARD: ADVANTAGES VS COMPROMISES (USER REQUEST)
                _TradeoffCard(tradeoff: activeTradeoff),

                const SizedBox(height: 10),

                // 2. ALL 3 PROFILES COMPARATIVE MATRIX
                _ComparativeMatrixCard(activeMode: route.mode),

                const SizedBox(height: 10),

                // 3. TRAVERSE METRICS
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TRAVERSE METRICS & ESTIMATES', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                        const Divider(),
                        _MetricRow('Total Distance', '${(route.distanceM / 1000).toStringAsFixed(2)} km', DataType.derived),
                        _MetricRow('Max Terrain Slope', '${route.maxSlopeDeg.toStringAsFixed(1)}°', DataType.derived),
                        _MetricRow('Elevation Gain', '${route.elevGainM.toStringAsFixed(0)} m', DataType.derived),
                        _MetricRow('Est. Duration (with rests)', '${risk.estimatedTimeMin.toStringAsFixed(0)} min', DataType.simulated),
                        _MetricRow('Terrain Confidence', route.confidence, DataType.modeled),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // 4. HUMAN EVA LIFE-SUPPORT CONSUMABLES
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('HUMAN EVA CONSUMABLES (SIMULATED)', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                            DataBadge(DataType.simulated),
                          ],
                        ),
                        const Divider(),
                        _MetricRow('Crew Setup', '${risk.consumables.crewSize} Astronauts (Buddy System)', DataType.simulated),
                        _MetricRow('Active Walking Time', '${risk.consumables.activeWalkingMin.toStringAsFixed(0)} min', DataType.simulated),
                        _MetricRow('Mandatory Rest Stops', '${risk.consumables.restStopsMin.toStringAsFixed(0)} min (10m/hr + slope recovery)', DataType.simulated),
                        _MetricRow('Oxygen Depletion', '${risk.consumables.oxygenKg.toStringAsFixed(2)} kg O2', DataType.simulated),
                        _MetricRow('Suit System Power', '${risk.consumables.batteryKwh.toStringAsFixed(2)} kWh', DataType.simulated),
                        _MetricRow('Sublimator Cooling Water', '${risk.consumables.coolingWaterKg.toStringAsFixed(2)} kg H2O', DataType.simulated),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // 5. EXPLAINABLE RISK BREAKDOWN
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('SIMULATED RISK: ${risk.score}/100 (${risk.level})', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
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

                const SizedBox(height: 10),

                // 6. WAYPOINTS & SCIENTIFIC CITATIONS
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WAYPOINTS & SCIENTIFIC TARGET CITATIONS', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                        const Divider(),
                        for (final l in lms)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${l.n}. ${l.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(l.desc, style: const TextStyle(fontSize: 11, color: MarsTheme.dim)),
                                Text('Citation: ${l.why}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF6B5850))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // PDF Export Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: MarsTheme.mars,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _exportPdf(context, ref),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('EXPORT & SHARE PDF REPORT', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Trade-off Card displaying Advantages vs Compromises of the selected route
class _TradeoffCard extends StatelessWidget {
  final RouteTradeoffData tradeoff;

  const _TradeoffCard({required this.tradeoff});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MarsTheme.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tradeoff.color, width: 2.0),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.balance, size: 18, color: tradeoff.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'WHY SELECT ${tradeoff.title}?',
                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: tradeoff.color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Operational Trade-off Evaluation for Mars Excursion Planning:',
            style: const TextStyle(fontSize: 11, color: MarsTheme.dim),
          ),
          const Divider(height: 16),

          // Advantages
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF388E3C)),
              const SizedBox(width: 6),
              const Text('KEY ADVANTAGES:', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF2E7D32))),
            ],
          ),
          const SizedBox(height: 4),
          for (final adv in tradeoff.advantages)
            Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 4),
              child: Text('• $adv', style: const TextStyle(fontSize: 12, height: 1.3)),
            ),

          const SizedBox(height: 8),

          // Compromises
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              const Text('OPERATIONAL COMPROMISES:', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFB45309))),
            ],
          ),
          const SizedBox(height: 4),
          for (final comp in tradeoff.compromises)
            Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 4),
              child: Text('• $comp', style: const TextStyle(fontSize: 12, height: 1.3)),
            ),
        ],
      ),
    );
  }
}

/// Comparative Matrix across all 3 Profiles
class _ComparativeMatrixCard extends StatelessWidget {
  final RouteMode activeMode;

  const _ComparativeMatrixCard({required this.activeMode});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ROUTE PROFILES COMPARISON MATRIX',
              style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Comparative trade-offs between Safety, Speed, and Science return:',
              style: TextStyle(fontSize: 11, color: MarsTheme.dim),
            ),
            const Divider(),
            for (final t in kRouteTradeoffs) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.mode == activeMode ? t.color.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: t.mode == activeMode ? t.color : MarsTheme.line,
                    width: t.mode == activeMode ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t.title, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, color: t.color)),
                        if (t.mode == activeMode)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: t.color, borderRadius: BorderRadius.circular(3)),
                            child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Advantage: ${t.advantageSummary}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                    Text('Compromise: ${t.compromiseSummary}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
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
          Text(k, style: const TextStyle(fontSize: 12, color: MarsTheme.dim)),
          Row(
            children: [
              Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              DataBadge(type),
            ],
          ),
        ],
      ),
    );
  }
}
