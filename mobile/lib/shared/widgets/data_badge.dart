import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../domain/terrain/terrain_grid.dart';
export '../../domain/terrain/terrain_grid.dart' show DataType;

class DataBadge extends StatelessWidget {
  final DataType type;

  const DataBadge(this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      DataType.observed => ('OBSERVED', MarsTheme.atmosDeep),
      DataType.derived => ('DERIVED', const Color(0xFF80601A)),
      DataType.modeled => ('MODELED', const Color(0xFF56655D)),
      DataType.unknown => ('UNKNOWN', MarsTheme.dim),
      DataType.simulated => ('SIMULATED', MarsTheme.marsDeep),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 1.0,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class HonestyBanner extends StatelessWidget {
  const HonestyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MarsTheme.mars.withOpacity(0.08),
        border: const Border(bottom: BorderSide(color: MarsTheme.line)),
      ),
      child: const Text(
        'OFFLINE · HiRISE DTM (DERIVED) · RISK, TIME & TARGETS ARE SIMULATED · SAFETY NOT CERTIFIED',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 0.7,
          color: MarsTheme.marsDeep,
        ),
      ),
    );
  }
}
