// Run just the routing demo:  flutter run -t lib/main_routing_demo.dart
import 'package:flutter/material.dart';

import 'features/planner/route_demo_screen.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RouteDemoScreen(),
    ));
