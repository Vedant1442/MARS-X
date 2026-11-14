import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SavedMission {
  final int? id;
  final String name;
  final String mode;
  final int startX;
  final int startY;
  final int endX;
  final int endY;
  final double distanceM;
  final int riskScore;
  final int currentStep;
  final String createdAt;

  const SavedMission({
    this.id,
    required this.name,
    required this.mode,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.distanceM,
    required this.riskScore,
    required this.currentStep,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'mode': mode,
        'start_x': startX,
        'start_y': startY,
        'end_x': endX,
        'end_y': endY,
        'distance_m': distanceM,
        'risk_score': riskScore,
        'current_step': currentStep,
        'created_at': createdAt,
      };

  factory SavedMission.fromMap(Map<String, dynamic> m) => SavedMission(
        id: m['id'] as int?,
        name: m['name'] as String,
        mode: m['mode'] as String,
        startX: m['start_x'] as int,
        startY: m['start_y'] as int,
        endX: m['end_x'] as int,
        endY: m['end_y'] as int,
        distanceM: (m['distance_m'] as num).toDouble(),
        riskScore: m['risk_score'] as int,
        currentStep: m['current_step'] as int,
        createdAt: m['created_at'] as String,
      );

  String toJson() => jsonEncode(toMap());
}

class MissionRepo {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), 'mars_x_missions.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE missions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            mode TEXT NOT NULL,
            start_x INTEGER NOT NULL,
            start_y INTEGER NOT NULL,
            end_x INTEGER NOT NULL,
            end_y INTEGER NOT NULL,
            distance_m REAL NOT NULL,
            risk_score INTEGER NOT NULL,
            current_step INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<int> saveMission(SavedMission mission) async {
    final database = await db;
    return database.insert('missions', mission.toMap());
  }

  Future<List<SavedMission>> listMissions() async {
    final database = await db;
    final rows = await database.query('missions', orderBy: 'id DESC');
    return rows.map(SavedMission.fromMap).toList();
  }

  Future<void> updateStep(int id, int step) async {
    final database = await db;
    await database.update(
      'missions',
      {'current_step': step},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMission(int id) async {
    final database = await db;
    await database.delete('missions', where: 'id = ?', whereArgs: [id]);
  }
}
