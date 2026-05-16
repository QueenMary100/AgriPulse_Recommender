import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/prediction_service.dart';
import '../services/price_service.dart';
import '../widgets/app_card.dart';
import '../widgets/custom_scaffold.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(DateTime selectedDate)? onPredictionComplete;

  const DashboardScreen({super.key, this.onPredictionComplete});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _dbService = DatabaseService();
  final PredictionService _predictionService = PredictionService();
  final PriceService _priceService = PriceService();

  String _userName = 'Farmer';
  String _location = 'Loading...';
  int? _countyId;
  double _currentPrice = 0;

  bool _isLoading = true;
  bool _isPredicting = false;
  bool _showPredictions = false;
  bool _fromCache = false;
  DateTime? _predictionTime;
  // Day 1 = tomorrow (first selectable). Initialise there so the picker
  // opens on a valid date and the horizon calculation is always >= 1.
  DateTime _selectedDate = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 1)));

  // Prediction result fields
  double _predictedPrice = 0;
  int _horizon = 14;
  String? _model;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final profile = await _dbService.getUserProfile();
      final county = profile['counties']['id'] as int;
      final countyName = profile['counties']['name'] as String;

      // Fetch dataset price and cached prediction concurrently.
      double datasetPrice = 0;
      PredictionResult? cached;
      await Future.wait([
        _priceService
            .getCurrentPriceFromDataset(countyName)
            .then((p) { datasetPrice = p; })
            .catchError((_) {}),
        _predictionService
            .getCachedPredictionForCurrentWeek(countyId: county)
            .then((c) { cached = c; })
            .catchError((_) {}),
      ]);

      if (mounted) {
        setState(() {
          _userName = profile['full_name'].toString().split(' ')[0];
          _location = countyName;
          _countyId = county;
          // Dataset price is the source of truth; fall back to cached value.
          _currentPrice = datasetPrice > 0
              ? datasetPrice
              : (cached?.currentPrice ?? 0);
          if (cached != null) {
            _predictedPrice = cached!.predictedPrice;
            _horizon = cached!.horizon;
            _model = cached!.model;
            _showPredictions = true;
            _fromCache = true;
            _predictionTime = cached!.createdAt;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePrediction() async {
    setState(() => _isPredicting = true);
    try {
      if (_countyId == null) throw Exception('County is not loaded yet.');

      // Fetch dataset price; fall back to last known price if backend offline.
      final datasetPrice =
          await _priceService.getCurrentPriceFromDataset(_location);
      final priceToUse = datasetPrice > 0 ? datasetPrice : _currentPrice;
      if (priceToUse <= 0) {
        throw Exception(
            'Current market price is unavailable for this county.');
      }

      // Day offset: tomorrow = Day 1, max = Day 14.
      final diff =
          _selectedDate.difference(DateUtils.dateOnly(DateTime.now())).inDays;

      final prediction = await _predictionService.predictForCurrentWeek(
        countyId: _countyId!,
        countyName: _location,
        currentPrice: priceToUse,
        dateRange: diff,
      );

      if (mounted) {
        setState(() {
          // currentPrice in PredictionResult now comes from the dataset via API.
          _currentPrice = prediction.currentPrice;
          _predictedPrice = prediction.predictedPrice;
          _horizon = prediction.horizon;
          _model = prediction.model;
          _showPredictions = true;
          _fromCache = prediction.fromCache;
          _predictionTime = prediction.createdAt;
          _isPredicting = false;
        });
        widget.onPredictionComplete?.call(_selectedDate);
      }
    } catch (e) {
      setState(() => _isPredicting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Prediction Error: $e')),
        );
      }
    }
  }

  // Day 0 = today (not selectable).  Day 1 = tomorrow (min).  Day 14 = max.
  DateTime get _firstSelectableDate =>
      DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
  DateTime get _maxSelectableDate =>
      DateUtils.dateOnly(DateTime.now().add(const Duration(days: 14)));

  Future<void> _pickForecastDate() async {
    final first = _firstSelectableDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(first) ? first : _selectedDate,
      firstDate: first,
      lastDate: _maxSelectableDate,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = DateUtils.dateOnly(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.green));
    }

    return CustomScaffold(
      showAppBar: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello $_userName!',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // ── Current price card ──────────────────────────────────────────
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current Maize Price',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      Text(
                        formatBagPrice(_currentPrice),
                        style: const TextStyle(
                          color: kGreen,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text('per 90 kg bag',
                          style:
                              TextStyle(color: Colors.black45, fontSize: 12)),
                    ],
                  ),
                  Image.asset('assets/images/dashboardimage.png', width: 100),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // ── Date picker card ────────────────────────────────────────────
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Forecast Date',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _pickForecastDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  color: kGreen, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(_selectedDate),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'Day ${_selectedDate.difference(DateUtils.dateOnly(DateTime.now())).inDays}',
                                style: const TextStyle(
                                    color: kGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Day 1 (tomorrow) to Day 14 from today.',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // ── Forecast card ───────────────────────────────────────────────
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Price Forecast',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  if (_showPredictions) ...[
                    const SizedBox(height: 6),
                    Text(
                      _fromCache
                          ? "Loaded from this week's cache"
                          : 'Fresh result from model API',
                      style: TextStyle(
                        color: _fromCache ? Colors.orange : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                    if (_predictionTime != null)
                      Text(
                        'Saved at ${_predictionTime!.toLocal()}',
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 11),
                      ),
                  ],
                  const SizedBox(height: 15),
                  if (_isPredicting)
                    const Center(child: CircularProgressIndicator())
                  else if (_showPredictions) ...[
                    PriceDataRow(
                      label: 'Predicted Price in +$_horizon days:',
                      pricePerKg: _predictedPrice,
                      fontSize: 15,
                    ),
                    if (_model != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Model: $_model',
                        style: const TextStyle(
                            color: Colors.black38, fontSize: 11),
                      ),
                    ],
                  ] else
                    const Center(
                      child: Column(
                        children: [
                          Icon(Icons.auto_graph,
                              size: 40, color: Colors.black12),
                          SizedBox(height: 6),
                          Text(
                            "Click 'Predict' to run regression model",
                            style: TextStyle(color: Colors.black38),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isPredicting
                    ? null
                    : () {
                        if (_currentPrice <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Current market price is unavailable for this county.',
                              ),
                            ),
                          );
                          return;
                        }
                        _handlePrediction();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  _showPredictions ? 'RE-PREDICT' : 'PREDICT',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
