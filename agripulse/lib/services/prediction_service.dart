import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'prediction_cache_service.dart';
import 'price_service.dart';

class ForecastPoint {
  final String date;
  final int day;
  final double predictedPrice;
  final double low;
  final double high;

  const ForecastPoint({
    required this.date,
    required this.day,
    required this.predictedPrice,
    required this.low,
    required this.high,
  });

  factory ForecastPoint.fromJson(Map<String, dynamic> json) => ForecastPoint(
        date: json['date'] as String,
        day: (json['day'] as num).toInt(),
        predictedPrice: (json['predicted_price'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'day': day,
        'predicted_price': predictedPrice,
        'low': low,
        'high': high,
      };
}

class HistoricalPoint {
  final String date;
  final double price;

  const HistoricalPoint({required this.date, required this.price});

  factory HistoricalPoint.fromJson(Map<String, dynamic> json) =>
      HistoricalPoint(
        date: json['date'] as String,
        price: (json['price'] as num).toDouble(),
      );
}

class PredictionResult {
  final int horizon;           // days to the selected date
  final double predictedPrice; // KES/kg at that horizon
  final String? model;         // e.g. 'gbr_horizon_07'
  final double currentPrice;
  final bool fromCache;
  final String source;
  final DateTime createdAt;
  final String cacheWeekKey;
  final List<ForecastPoint> forecastPoints;
  final List<HistoricalPoint> historicalPoints;
  final DateTime? selectedDate;
  final Map<String, dynamic>? recommendation;

  const PredictionResult({
    required this.horizon,
    required this.predictedPrice,
    this.model,
    required this.currentPrice,
    required this.fromCache,
    required this.source,
    required this.createdAt,
    required this.cacheWeekKey,
    this.forecastPoints = const [],
    this.historicalPoints = const [],
    this.selectedDate,
    this.recommendation,
  });
}

class PredictionService {
  static const String _remoteForecastTable = 'price_forecast';
  final PriceService _priceService;
  final PredictionCacheService _cacheService;
  final _supabase = Supabase.instance.client;

  PredictionService({
    PriceService? priceService,
    PredictionCacheService? cacheService,
  }) : _priceService = priceService ?? PriceService(),
       _cacheService = cacheService ?? PredictionCacheService();

  /// Full range prediction: fetches all daily forecasts from today to selectedDate.
  Future<PredictionResult> predictRange({
    required int countyId,
    required String countyName,
    required double currentPrice,
    required DateTime selectedDate,
    bool forceRefresh = false,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    if (currentPrice <= 0) {
      throw Exception(
        'Current market price is unavailable. Please add a latest price for this county.',
      );
    }

    final now = DateTime.now();
    final weekKey = _cacheService.weekKey(now);
    final todayOnly = DateTime(now.year, now.month, now.day);
    final horizon = selectedDate.difference(todayOnly).inDays.clamp(1, 14);

    // Return cached result when date and forecast data match
    if (!forceRefresh) {
      final existing = await _cacheService.findPredictionForWeek(
        userId: userId,
        countyId: countyId,
        weekKey: weekKey,
      );
      if (existing != null) {
        final cachedPrice = _toDouble(existing['current_price']);
        final cachedSelectedDate = existing['selected_date'] as String?;
        final cachedForecastJson = existing['forecast_json'] as String?;
        if (cachedPrice > 0 &&
            cachedSelectedDate ==
                selectedDate.toIso8601String().substring(0, 10) &&
            cachedForecastJson != null) {
          final forecastPoints = _parseForecastJson(cachedForecastJson);
          // Support old rows (predicted_price=0) by falling back to week_2
          final cachedPredicted = _toDouble(existing['predicted_price']);
          final effectivePredicted = cachedPredicted > 0
              ? cachedPredicted
              : _toDouble(existing['week_2']);
          final cachedHorizon =
              (existing['horizon'] as int?) ?? horizon;
          return PredictionResult(
            horizon: cachedHorizon,
            predictedPrice: effectivePredicted,
            model: existing['model'] as String?,
            currentPrice: cachedPrice,
            fromCache: true,
            source: (existing['source'] as String?) ?? 'api',
            createdAt:
                DateTime.tryParse(existing['created_at'] as String? ?? '') ??
                    now,
            cacheWeekKey: (existing['cache_week_key'] as String?) ?? weekKey,
            forecastPoints: forecastPoints,
            selectedDate: selectedDate,
            recommendation:
                _parseRecommendationJson(existing['recommendation_action']),
          );
        }
      }
    }

    // Fresh API call
    final payload = await _priceService.getForecastRange(
      countyName: countyName,
      horizonDays: horizon,
      referenceDate: now.toIso8601String().substring(0, 10),
    );

    final forecastPoints = _extractForecastPoints(payload);
    final historicalPoints = _extractHistoricalPoints(payload);
    final recommendation = payload['recommendation'] as Map<String, dynamic>?;

    // Prefer the dataset price returned by the backend over the caller-supplied value
    final datasetPrice = (payload['current_price'] as num?)?.toDouble();
    final effectiveCurrentPrice =
        (datasetPrice != null && datasetPrice > 0) ? datasetPrice : currentPrice;

    final predictedPrice = forecastPoints.isNotEmpty
        ? forecastPoints.last.predictedPrice
        : effectiveCurrentPrice;
    final model = 'gbr_horizon_${horizon.toString().padLeft(2, '0')}';
    final forecastJson =
        jsonEncode(forecastPoints.map((p) => p.toJson()).toList());
    // Store full recommendation JSON so the Advisory tab can rebuild all fields.
    final recommendationAction =
        recommendation != null ? jsonEncode(recommendation) : null;
    final selectedDateStr = selectedDate.toIso8601String().substring(0, 10);

    await _cacheService.upsertWeeklyPrediction(
      userId: userId,
      countyId: countyId,
      countyName: countyName,
      cacheWeekKey: weekKey,
      currentPrice: effectiveCurrentPrice,
      horizon: horizon,
      predictedPrice: predictedPrice,
      model: model,
      source: 'api',
      createdAt: now,
      forecastJson: forecastJson,
      selectedDate: selectedDateStr,
      recommendationAction: recommendationAction,
    );
    await _cacheService.insertForecast(
      userId: userId,
      countyId: countyId,
      countyName: countyName,
      cacheWeekKey: weekKey,
      currentPrice: effectiveCurrentPrice,
      horizon: horizon,
      predictedPrice: predictedPrice,
      model: model,
      source: 'api',
      createdAt: now,
      forecastJson: forecastJson,
      selectedDate: selectedDateStr,
      recommendationAction: recommendationAction,
    );
    await _insertRemoteForecast(
      userId: userId,
      countyId: countyId,
      countyName: countyName,
      cacheWeekKey: weekKey,
      currentPrice: effectiveCurrentPrice,
      horizon: horizon,
      predictedPrice: predictedPrice,
      model: model,
      source: 'api',
      createdAt: now,
      forecastJson: forecastJson,
      selectedDate: selectedDateStr,
      recommendationAction: recommendationAction,
    );

    return PredictionResult(
      horizon: horizon,
      predictedPrice: predictedPrice,
      model: model,
      currentPrice: effectiveCurrentPrice,
      fromCache: false,
      source: 'api',
      createdAt: now,
      cacheWeekKey: weekKey,
      forecastPoints: forecastPoints,
      historicalPoints: historicalPoints,
      selectedDate: selectedDate,
      recommendation: recommendation,
    );
  }

  /// Convenience wrapper used by the Dashboard quick-predict button.
  Future<PredictionResult> predictForCurrentWeek({
    required int countyId,
    required String countyName,
    required double currentPrice,
    int? dateRange,
    bool forceRefresh = false,
  }) async {
    final selectedDate = DateTime.now().add(Duration(days: dateRange ?? 14));
    return predictRange(
      countyId: countyId,
      countyName: countyName,
      currentPrice: currentPrice,
      selectedDate: selectedDate,
      forceRefresh: forceRefresh,
    );
  }

  Future<PredictionResult?> getCachedPredictionForCurrentWeek({
    required int countyId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    final now = DateTime.now();
    final weekKey = _cacheService.weekKey(now);
    final existing = await _cacheService.findPredictionForWeek(
      userId: userId,
      countyId: countyId,
      weekKey: weekKey,
    );
    if (existing == null) return null;

    final cachedPrice = _toDouble(existing['current_price']);
    if (cachedPrice <= 0) {
      await _cacheService.deletePredictionForWeek(
        userId: userId,
        countyId: countyId,
        weekKey: weekKey,
      );
      return null;
    }

    final forecastPoints =
        _parseForecastJson(existing['forecast_json'] as String?);
    final selectedDateStr = existing['selected_date'] as String?;
    // Support old cache rows that only have week_2
    final cachedPredicted = _toDouble(existing['predicted_price']);
    final effectivePredicted =
        cachedPredicted > 0 ? cachedPredicted : _toDouble(existing['week_2']);

    return PredictionResult(
      horizon: (existing['horizon'] as int?) ?? 14,
      predictedPrice: effectivePredicted,
      model: existing['model'] as String?,
      currentPrice: cachedPrice,
      fromCache: true,
      source: (existing['source'] as String?) ?? 'api',
      createdAt:
          DateTime.tryParse(existing['created_at'] as String? ?? '') ?? now,
      cacheWeekKey: (existing['cache_week_key'] as String?) ?? weekKey,
      forecastPoints: forecastPoints,
      selectedDate:
          selectedDateStr != null ? DateTime.tryParse(selectedDateStr) : null,
      recommendation:
          _parseRecommendationJson(existing['recommendation_action']),
    );
  }

  Future<List<Map<String, dynamic>>> getUserHistory() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    final localRows = await _cacheService.listForecasts(userId);
    try {
      final List<dynamic> remoteRows = await _supabase
          .from(_remoteForecastTable)
          .select(
            'user_id, county_id, county_name, cache_week_key, current_price, '
            'horizon, predicted_price, model, source, created_at, '
            'selected_date, recommendation_action',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return _mergeHistory(
        List<Map<String, dynamic>>.from(remoteRows),
        localRows,
      );
    } catch (_) {
      return localRows;
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  List<ForecastPoint> _extractForecastPoints(Map<String, dynamic> payload) {
    final raw = payload['forecast'];
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map(ForecastPoint.fromJson).toList();
  }

  List<HistoricalPoint> _extractHistoricalPoints(Map<String, dynamic> payload) {
    final raw = payload['historical'];
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map(HistoricalPoint.fromJson).toList();
  }

  List<ForecastPoint> _parseForecastJson(String? json) {
    if (json == null) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().map(ForecastPoint.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic>? _parseRecommendationJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {'action': raw.toString()};
  }

  Future<void> _insertRemoteForecast({
    required String userId,
    required int countyId,
    required String countyName,
    required String cacheWeekKey,
    required double currentPrice,
    required int horizon,
    required double predictedPrice,
    required String model,
    required String source,
    required DateTime createdAt,
    String? forecastJson,
    String? selectedDate,
    String? recommendationAction,
  }) async {
    try {
      await _supabase.from(_remoteForecastTable).insert({
        'user_id': userId,
        'county_id': countyId,
        'county_name': countyName,
        'cache_week_key': cacheWeekKey,
        'current_price': currentPrice,
        'horizon': horizon,
        'predicted_price': predictedPrice,
        'model': model,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'selected_date': ?selectedDate,
        'recommendation_action': ?recommendationAction,
        'forecast_json': ?forecastJson,
      });
    } catch (_) {
      // Local cache is the offline source of truth.
    }
  }

  List<Map<String, dynamic>> _mergeHistory(
    List<Map<String, dynamic>> remoteRows,
    List<Map<String, dynamic>> localRows,
  ) {
    final combined = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addUnique(Map<String, dynamic> row) {
      final key =
          '${row['user_id']}_${row['county_id']}_${row['cache_week_key']}_${row['created_at']}';
      if (seen.add(key)) combined.add(row);
    }

    for (final row in remoteRows) {
      addUnique({...row, 'sync_status': 'synced'});
    }
    for (final row in localRows) {
      addUnique({...row, 'sync_status': 'local'});
    }

    combined.sort((a, b) {
      final left = a['created_at']?.toString() ?? '';
      final right = b['created_at']?.toString() ?? '';
      return right.compareTo(left);
    });

    return combined;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
