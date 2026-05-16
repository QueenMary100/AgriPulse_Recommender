import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PriceService {
  final _supabase = Supabase.instance.client;

 
  // --dart-define=PREDICTION_API_URL=http://127.0.0.1:8000/api/predict/
  // For Android emulator,  http://10.0.2.2:8000/api/predict/
  static const String _defaultPredictionApiUrl =
      'https://agripulse-recommender.onrender.com/predict/';
  static const String _predictionApiUrl = String.fromEnvironment(
    'PREDICTION_API_URL',
    defaultValue: _defaultPredictionApiUrl,
  );
  static const String _predictionApiKey = String.fromEnvironment(
    'PREDICTION_API_KEY',
    defaultValue: '',
  );

  /// Fetch the latest maize price directly from the dataset (backend CSV).
  /// Falls back to 0.0 if the backend is unreachable.
  Future<double> getCurrentPriceFromDataset(String countyName) async {
    final baseUrl = _predictionApiUrl.replaceAll(RegExp(r'/predict/?$'), '');
    final url = '$baseUrl/current_price?county=${Uri.encodeComponent(countyName)}';
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              if (_predictionApiKey.isNotEmpty) ...{
                'X-API-Key': _predictionApiKey,
                'Authorization': 'Bearer $_predictionApiKey',
              },
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['price'] as num).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  /// Full range forecast: returns day-by-day predictions + historical + recommendation.
  /// Calls POST /predict/range on the FastAPI backend.
  Future<Map<String, dynamic>> getForecastRange({
    required String countyName,
    required int horizonDays,
    required String referenceDate,
  }) async {
    final payload = jsonEncode({
      'county': countyName,
      'horizon_days': horizonDays,
      'reference_date': referenceDate,
    });

    final baseUrl = _predictionApiUrl.replaceAll(RegExp(r'/predict/?$'), '');
    final rangeUrl = '$baseUrl/predict/range';

    Future<http.Response> post(Duration timeout) => http
        .post(
          Uri.parse(rangeUrl),
          headers: {
            'Content-Type': 'application/json',
            if (_predictionApiKey.isNotEmpty) ...{
              'X-API-Key': _predictionApiKey,
              'Authorization': 'Bearer $_predictionApiKey',
            },
          },
          body: payload,
        )
        .timeout(timeout);

    try {
      http.Response response;
      try {
        response = await post(const Duration(seconds: 25));
      } on TimeoutException {
        response = await post(const Duration(seconds: 80));
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        throw Exception('Unexpected response format from /predict/range.');
      }
      throw Exception('API Error ${response.statusCode}: ${response.body}');
    } catch (e) {
      throw Exception('Connection to forecast range API failed at $rangeUrl: $e');
    }
  }

  /// 1. Fetch forecast data from my hosted REGRESSION API
  /// This replaces fetching from a static table to get dynamic model results
  Future<Map<String, dynamic>> getRegressionForecast(
    // int countyId,
    // double currentPrice,
    String countyName,
    int? dateRange,
    String referenceDate,
  ) async {
    try {
      // final payload = jsonEncode({
      //   "county_id": countyId,
      //   "current_price": currentPrice,
      //   "request_timestamp": DateTime.now().toIso8601String(),
      // });
      // final payload = jsonEncode({
      //   "county": countyId,
      //   "current_price": currentPrice,
      //   "reference_date": DateTime.now().toIso8601String(),
      // });
      final payload = jsonEncode({
        "county": countyName,
        "horizon_days": dateRange,
        "reference_date": referenceDate,
      });

      final response = await _postPredictionRequest(
        payload: payload,
        timeout: const Duration(seconds: 25),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        throw Exception('Unexpected response format from prediction API.');
      } else {
        if (response.statusCode == 403) {
          throw Exception(
            "API Error 403: Invalid API key. "
            "Ensure PREDICTION_API_KEY matches backend API_AUTH_KEY.",
          );
        }
        throw Exception("API Error ${response.statusCode}: ${response.body}");
      }
    } on TimeoutException {
      // Render free-tier cold starts can exceed 20 seconds.
      // final retryPayload = jsonEncode({
      //   "county_id": countyId,
      //   "current_price": currentPrice,
      //   "request_timestamp": DateTime.now().toIso8601String(),
      // });
      final retryPayload = jsonEncode({
        "county": countyName,
        "horizon_days": dateRange,
        "reference_date": referenceDate,
      });
      final retryResponse = await _postPredictionRequest(
        payload: retryPayload,
        timeout: const Duration(seconds: 80),
      );
      if (retryResponse.statusCode == 200) {
        final decoded = jsonDecode(retryResponse.body);
        if (decoded is Map<String, dynamic>) return decoded;
        throw Exception('Unexpected response format from prediction API.');
      }
      if (retryResponse.statusCode == 403) {
        throw Exception(
          "API Error 403: Invalid API key. "
          "Ensure PREDICTION_API_KEY matches backend API_AUTH_KEY.",
        );
      }
      throw Exception(
        "API Error ${retryResponse.statusCode}: ${retryResponse.body}",
      );
    } catch (e) {
      throw Exception(
        "Connection to Regression Model failed at $_predictionApiUrl: $e",
      );
    }
  }

  Future<http.Response> _postPredictionRequest({
    required String payload,
    required Duration timeout,
  }) {
    return http
        .post(
          Uri.parse(_predictionApiUrl),
          headers: {
            "Content-Type": "application/json",
            if (_predictionApiKey.isNotEmpty) ...{
              "X-API-Key": _predictionApiKey,
              "Authorization": "Bearer $_predictionApiKey",
            },
          },
          body: payload,
        )
        .timeout(timeout);
  }

  /// 2. Fetch historical forecast data (for record keeping/auditing)
  Future<List<Map<String, dynamic>>> getForecastHistory(int countyId) async {
    final List<dynamic> data = await _supabase
        .from('price_forecasts')
        .select()
        .eq('county_id', countyId)
        .order('forecast_date', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  /// 3. Get forecast predictions (alias for getRegressionForecast for compatibility)
  // Future<Map<String, dynamic>> getForecast(
  //   int countyId,
  //   double currentPrice,
  // ) async {
  //   return await getRegressionForecast(countyId, currentPrice);
  // }

  /// 4. Get regression prediction data (alias for getRegressionForecast)
  // Future<Map<String, dynamic>> getRegressionPrediction(
  //   String countyId,
  //   double currentPrice,
  // ) async {
  //   return await getRegressionForecast(countyId, currentPrice);
  // }
  Future<Map<String, dynamic>> getRegressionPrediction(
    String countyName,
    int? dateRange,
    String referenceDate,
  ) async {
    return await getRegressionForecast(countyName, dateRange ?? 1, referenceDate);
  }



  (double, double) extractWeekPredictions(
    Map<String, dynamic> payload,
    double fallbackCurrentPrice,
  ) {
    // final forecastList = payload['forecast'];
    final forecastList = payload['predicted_price'];
    // if (forecastList is List && forecastList.length >= 2) {
    //   return (_toDouble(forecastList[0]), _toDouble(forecastList[1]));
    // }

    // final week1 = payload['week_1'] ?? payload['next_week'];
    // final week2 = payload['week_2'] ?? payload['two_weeks'];
    final week1 = forecastList;
    final week2 = forecastList;
    if (week1 != null && week2 != null) {
      return (_toDouble(week1), _toDouble(week2));
    }

    throw Exception(
      'Prediction payload missing expected keys. '
      'Expected forecast list or week_1/week_2 fields.',
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
}
