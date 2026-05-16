import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class PredictionCacheService {
  static const _databaseName = 'agripulse_cache.db';
  static const _weeklyCacheTable = 'prediction_weekly_cache';
  static const _forecastTable = 'price_forecast';
  static const _databaseVersion = 4;

  Database? _db;
  static final List<Map<String, dynamic>> _webWeeklyCache = [];
  static final List<Map<String, dynamic>> _webForecastStore = [];

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _databaseName),
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_weeklyCacheTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        county_id INTEGER NOT NULL,
        county_name TEXT NOT NULL,
        cache_week_key TEXT NOT NULL,
        current_price REAL NOT NULL,
        horizon INTEGER NOT NULL DEFAULT 14,
        predicted_price REAL NOT NULL DEFAULT 0,
        model TEXT,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        forecast_json TEXT,
        selected_date TEXT,
        recommendation_action TEXT,
        UNIQUE(user_id, county_id, cache_week_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE $_forecastTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        county_id INTEGER NOT NULL,
        county_name TEXT NOT NULL,
        cache_week_key TEXT NOT NULL,
        current_price REAL NOT NULL,
        horizon INTEGER NOT NULL DEFAULT 14,
        predicted_price REAL NOT NULL DEFAULT 0,
        model TEXT,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        forecast_json TEXT,
        selected_date TEXT,
        recommendation_action TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE prediction_history RENAME TO $_weeklyCacheTable',
      );
      await db.execute('''
        CREATE TABLE prediction_history(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL, county_id INTEGER NOT NULL,
          county_name TEXT NOT NULL, cache_week_key TEXT NOT NULL,
          current_price REAL NOT NULL, week_1 REAL NOT NULL,
          week_2 REAL NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO prediction_history
          (user_id, county_id, county_name, cache_week_key,
           current_price, week_1, week_2, source, created_at)
        SELECT user_id, county_id, county_name, cache_week_key,
               current_price, week_1, week_2, source, created_at
        FROM $_weeklyCacheTable
      ''');
    }
    if (oldVersion < 3) {
      for (final t in [_weeklyCacheTable, 'prediction_history']) {
        try { await db.execute('ALTER TABLE $t ADD COLUMN forecast_json TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE $t ADD COLUMN selected_date TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE $t ADD COLUMN recommendation_action TEXT'); } catch (_) {}
      }
    }
    if (oldVersion < 4) {
      // Add new columns to weekly cache
      for (final sql in [
        'ALTER TABLE $_weeklyCacheTable ADD COLUMN horizon INTEGER DEFAULT 14',
        'ALTER TABLE $_weeklyCacheTable ADD COLUMN predicted_price REAL DEFAULT 0',
        'ALTER TABLE $_weeklyCacheTable ADD COLUMN model TEXT',
      ]) {
        try { await db.execute(sql); } catch (_) {}
      }
      // Back-fill predicted_price from week_2 for existing rows
      try {
        await db.execute(
          'UPDATE $_weeklyCacheTable SET predicted_price = week_2 '
          'WHERE predicted_price = 0 AND week_2 IS NOT NULL',
        );
      } catch (_) {}

      // Create price_forecast table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_forecastTable(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL, county_id INTEGER NOT NULL,
          county_name TEXT NOT NULL, cache_week_key TEXT NOT NULL,
          current_price REAL NOT NULL,
          horizon INTEGER NOT NULL DEFAULT 14,
          predicted_price REAL NOT NULL DEFAULT 0,
          model TEXT, source TEXT NOT NULL, created_at TEXT NOT NULL,
          forecast_json TEXT, selected_date TEXT, recommendation_action TEXT
        )
      ''');
      // Migrate old prediction_history into price_forecast
      try {
        await db.execute('''
          INSERT INTO $_forecastTable
            (user_id, county_id, county_name, cache_week_key, current_price,
             horizon, predicted_price, model, source, created_at,
             forecast_json, selected_date, recommendation_action)
          SELECT user_id, county_id, county_name, cache_week_key, current_price,
                 14, COALESCE(week_2, week_1, 0), NULL, source, created_at,
                 forecast_json, selected_date, recommendation_action
          FROM prediction_history
        ''');
      } catch (_) {}
    }
  }

  // ── week key ────────────────────────────────────────────────────────────────

  String weekKey(DateTime now) {
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}'
        '-${monday.day.toString().padLeft(2, '0')}';
  }

  // ── weekly cache ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> findPredictionForWeek({
    required String userId,
    required int countyId,
    required String weekKey,
  }) async {
    if (kIsWeb) {
      return _webWeeklyCache.where((r) =>
          r['user_id'] == userId &&
          r['county_id'] == countyId &&
          r['cache_week_key'] == weekKey).firstOrNull;
    }
    final db = await _database();
    final rows = await db.query(
      _weeklyCacheTable,
      where: 'user_id = ? AND county_id = ? AND cache_week_key = ?',
      whereArgs: [userId, countyId, weekKey],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<void> upsertWeeklyPrediction({
    required String userId,
    required int countyId,
    required String countyName,
    required String cacheWeekKey,
    required double currentPrice,
    required int horizon,
    required double predictedPrice,
    String? model,
    required String source,
    required DateTime createdAt,
    String? forecastJson,
    String? selectedDate,
    String? recommendationAction,
  }) async {
    final row = _buildRow(
      userId: userId, countyId: countyId, countyName: countyName,
      cacheWeekKey: cacheWeekKey, currentPrice: currentPrice,
      horizon: horizon, predictedPrice: predictedPrice, model: model,
      source: source, createdAt: createdAt, forecastJson: forecastJson,
      selectedDate: selectedDate, recommendationAction: recommendationAction,
    );
    if (kIsWeb) {
      _webWeeklyCache.removeWhere((r) =>
          r['user_id'] == userId &&
          r['county_id'] == countyId &&
          r['cache_week_key'] == cacheWeekKey);
      _webWeeklyCache.add(row);
      return;
    }
    final db = await _database();
    await db.insert(_weeklyCacheTable, row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePredictionForWeek({
    required String userId,
    required int countyId,
    required String weekKey,
  }) async {
    if (kIsWeb) {
      _webWeeklyCache.removeWhere((r) =>
          r['user_id'] == userId &&
          r['county_id'] == countyId &&
          r['cache_week_key'] == weekKey);
      return;
    }
    final db = await _database();
    await db.delete(_weeklyCacheTable,
        where: 'user_id = ? AND county_id = ? AND cache_week_key = ?',
        whereArgs: [userId, countyId, weekKey]);
  }

  // ── forecast history ────────────────────────────────────────────────────────

  Future<void> insertForecast({
    required String userId,
    required int countyId,
    required String countyName,
    required String cacheWeekKey,
    required double currentPrice,
    required int horizon,
    required double predictedPrice,
    String? model,
    required String source,
    required DateTime createdAt,
    String? forecastJson,
    String? selectedDate,
    String? recommendationAction,
  }) async {
    final row = _buildRow(
      userId: userId, countyId: countyId, countyName: countyName,
      cacheWeekKey: cacheWeekKey, currentPrice: currentPrice,
      horizon: horizon, predictedPrice: predictedPrice, model: model,
      source: source, createdAt: createdAt, forecastJson: forecastJson,
      selectedDate: selectedDate, recommendationAction: recommendationAction,
    );
    if (kIsWeb) {
      _webForecastStore.add(row);
      return;
    }
    final db = await _database();
    await db.insert(_forecastTable, row);
  }

  Future<List<Map<String, dynamic>>> listForecasts(String userId) async {
    if (kIsWeb) {
      final rows = _webForecastStore
          .where((r) => r['user_id'] == userId)
          .map((r) => Map<String, dynamic>.from(r))
          .toList()
        ..sort((a, b) => (b['created_at'] as String)
            .compareTo(a['created_at'] as String));
      return rows;
    }
    final db = await _database();
    return db.query(_forecastTable,
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at DESC');
  }

  // ── helper ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildRow({
    required String userId,
    required int countyId,
    required String countyName,
    required String cacheWeekKey,
    required double currentPrice,
    required int horizon,
    required double predictedPrice,
    String? model,
    required String source,
    required DateTime createdAt,
    String? forecastJson,
    String? selectedDate,
    String? recommendationAction,
  }) =>
      {
        'user_id': userId,
        'county_id': countyId,
        'county_name': countyName,
        'cache_week_key': cacheWeekKey,
        'current_price': currentPrice,
        'horizon': horizon,
        'predicted_price': predictedPrice,
        'model': ?model,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'forecast_json': ?forecastJson,
        'selected_date': ?selectedDate,
        'recommendation_action': ?recommendationAction,
      };
}
