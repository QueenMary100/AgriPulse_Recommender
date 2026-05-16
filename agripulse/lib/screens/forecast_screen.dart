import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/app_card.dart';
import '../widgets/custom_scaffold.dart';
import '../services/database_service.dart';
import '../services/prediction_service.dart';
import '../services/price_service.dart';
import 'recommendation_screen.dart';

class ForecastScreen extends StatefulWidget {
  final int countyId;
  final String countyName;
  final double currentPrice;
  final DateTime? initialSelectedDate;
  final int refreshToken;
  final Future<void> Function(int countyId, String countyName)? onCountyChanged;

  const ForecastScreen({
    super.key,
    required this.countyId,
    required this.countyName,
    required this.currentPrice,
    this.initialSelectedDate,
    this.refreshToken = 0,
    this.onCountyChanged,
  });

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {

  final DatabaseService _dbService = DatabaseService();
  final PredictionService _predictionService = PredictionService();
  final PriceService _priceService = PriceService();

  bool _isLoading = false;
  bool _fromCache = false;
  DateTime? _predictedAt;

  late int _selectedCountyId;
  late String _selectedCountyName;
  double _currentPrice = 0;
  List<Map<String, dynamic>> _counties = [];

  late DateTime _selectedDate;
  List<ForecastPoint> _forecastPoints = [];
  List<HistoricalPoint> _historicalPoints = [];
  Map<String, dynamic>? _recommendation;
  int _historyDays = 7;

  @override
  void initState() {
    super.initState();
    _selectedCountyId = widget.countyId;
    _selectedCountyName = widget.countyName;
    _currentPrice = widget.currentPrice;
    _selectedDate = widget.initialSelectedDate ??
        DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 14));
    _loadCountiesAndCache();
  }

  @override
  void didUpdateWidget(covariant ForecastScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.countyId != oldWidget.countyId ||
        widget.countyName != oldWidget.countyName ||
        widget.currentPrice != oldWidget.currentPrice) {
      _selectedCountyId = widget.countyId;
      _selectedCountyName = widget.countyName;
      _currentPrice = widget.currentPrice;
      _loadCachedPrediction();
      return;
    }
    // Dashboard ran a new prediction — sync date and reload cache.
    if (widget.refreshToken != oldWidget.refreshToken) {
      if (widget.initialSelectedDate != null) {
        _selectedDate = widget.initialSelectedDate!;
      }
      _loadCachedPrediction();
    }
  }

  // ── data loading ────────────────────────────────────────────────────────────

  Future<void> _loadCountiesAndCache() async {
    setState(() => _isLoading = true);
    try {
      final counties = await _dbService.getCounties();
      final valid = counties.where((r) => _countyIdOf(r) != null).toList();
      if (!mounted) return;
      if (valid.isNotEmpty &&
          !valid.any((r) => _countyIdOf(r) == _selectedCountyId)) {
        _selectedCountyId = _countyIdOf(valid.first)!;
        _selectedCountyName = valid.first['name']?.toString() ?? '';
      }
      setState(() => _counties = valid);
      await _loadCachedPrediction(showLoader: false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCachedPrediction({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      final cached = await _predictionService.getCachedPredictionForCurrentWeek(
        countyId: _selectedCountyId,
      );
      if (!mounted) return;
      if (cached != null && cached.forecastPoints.isNotEmpty) {
        final horizonDays = (cached.selectedDate ?? _selectedDate)
            .difference(DateUtils.dateOnly(DateTime.now()))
            .inDays;
        setState(() {
          // Use dataset price stored in the cache (set by the API, not Supabase).
          _currentPrice = cached.currentPrice > 0 ? cached.currentPrice : _currentPrice;
          _forecastPoints = cached.forecastPoints;
          _historicalPoints = cached.historicalPoints;
          _recommendation = cached.recommendation;
          if (cached.selectedDate != null) _selectedDate = cached.selectedDate!;
          _fromCache = true;
          _predictedAt = cached.createdAt;
          _isLoading = false;
          // Short horizons need more history for context.
          if (horizonDays < 5 && _historyDays < 7) _historyDays = 7;
        });
      } else {
        setState(() {
          _forecastPoints = [];
          _fromCache = false;
          _predictedAt = null;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runPrediction({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final datasetPrice = await _priceService.getCurrentPriceFromDataset(_selectedCountyName);
      final priceToUse = datasetPrice > 0 ? datasetPrice : _currentPrice;
      if (priceToUse <= 0) throw Exception('Current price unavailable for this county.');

      final result = await _predictionService.predictRange(
        countyId: _selectedCountyId,
        countyName: _selectedCountyName,
        currentPrice: priceToUse,
        selectedDate: _selectedDate,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      final horizonDays = _selectedDate
          .difference(DateUtils.dateOnly(DateTime.now()))
          .inDays;
      setState(() {
        _currentPrice = result.currentPrice;
        _forecastPoints = result.forecastPoints;
        _historicalPoints = result.historicalPoints;
        _recommendation = result.recommendation;
        _fromCache = result.fromCache;
        _predictedAt = result.createdAt;
        _isLoading = false;
        if (horizonDays < 5 && _historyDays < 7) _historyDays = 7;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Forecast error: $e')),
      );
    }
  }

  Future<void> _onCountyChanged(int? countyId) async {
    if (countyId == null || countyId == _selectedCountyId) return;
    final county = _counties.firstWhere(
      (r) => _countyIdOf(r) == countyId,
      orElse: () => {'id': countyId, 'name': _selectedCountyName},
    );
    setState(() {
      _selectedCountyId = countyId;
      _selectedCountyName = county['name']?.toString() ?? _selectedCountyName;
      _forecastPoints = [];
      _fromCache = false;
      _predictedAt = null;
    });
    await widget.onCountyChanged?.call(_selectedCountyId, _selectedCountyName);
    await _loadCachedPrediction();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = today.add(const Duration(days: 1));
    final last = today.add(const Duration(days: 14));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(first) ? first : _selectedDate,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = DateUtils.dateOnly(picked));
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  int? _countyIdOf(Map<String, dynamic> row) {
    final raw = row['id'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  String _decisionLabel(String? decision) {
    switch (decision) {
      case 'wait': return 'WAIT';
      case 'sell_soon': return 'SELL SOON';
      default: return 'SELL NOW';
    }
  }

  Color _decisionColor(String? decision) {
    switch (decision) {
      case 'wait': return const Color(0xFF2E7D32);
      case 'sell_soon': return Colors.orange;
      default: return Colors.redAccent;
    }
  }

  // ── chart ───────────────────────────────────────────────────────────────────

  String _shortDate(DateTime date) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[date.month - 1]} ${date.day}';
  }

  Widget _buildChart() {
    final today = DateUtils.dateOnly(DateTime.now());
    final horizonDays = _selectedDate.difference(today).inDays;

    // Historical series filtered to _historyDays prior
    final List<FlSpot> histSpots = [];
    for (final h in _historicalPoints) {
      final date = DateTime.tryParse(h.date);
      if (date == null) continue;
      final offset = date.difference(today).inDays.toDouble();
      if (offset < -_historyDays) continue;
      histSpots.add(FlSpot(offset, bagPrice(h.price)));
    }
    histSpots.add(FlSpot(0, bagPrice(_currentPrice)));

    // Forecast series clipped to selected date
    final List<FlSpot> foreSpots = [FlSpot(0, bagPrice(_currentPrice))];
    final List<FlSpot> lowSpots = [FlSpot(0, bagPrice(_currentPrice))];
    final List<FlSpot> highSpots = [FlSpot(0, bagPrice(_currentPrice))];

    for (final p in _forecastPoints) {
      if (p.day > horizonDays) break;
      foreSpots.add(FlSpot(p.day.toDouble(), bagPrice(p.predictedPrice)));
      lowSpots.add(FlSpot(p.day.toDouble(), bagPrice(p.low)));
      highSpots.add(FlSpot(p.day.toDouble(), bagPrice(p.high)));
    }

    final allPrices = [
      ...histSpots.map((s) => s.y),
      ...foreSpots.map((s) => s.y),
    ];
    if (allPrices.isEmpty) return const SizedBox.shrink();
    final minY = allPrices.reduce((a, b) => a < b ? a : b) - 200;
    final maxY = allPrices.reduce((a, b) => a > b ? a : b) + 200;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          getDrawingVerticalLine: (v) => FlLine(
            color: v == 0 ? Colors.grey.shade400 : Colors.grey.shade100,
            strokeWidth: v == 0 ? 1.5 : 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            axisNameWidget: const RotatedBox(
              quarterTurns: 1,
              child: Text(
                'Price (KES / 90 kg bag)',
                style: TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ),
            axisNameSize: 32,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, _) => Text(
                '${(v / 1000).toStringAsFixed(1)}K',
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text(
              'Days from today',
              style: TextStyle(fontSize: 9, color: Colors.black45),
            ),
            axisNameSize: 16,
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 32,
              getTitlesWidget: (v, _) {
                final int d = v.toInt();
                if (d == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Today',
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.black54,
                          fontWeight: FontWeight.bold),
                    ),
                  );
                }
                if (d == horizonDays) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Target',
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold),
                    ),
                  );
                }
                if (d > 0 && d % 3 == 0 && d < horizonDays) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _shortDate(today.add(Duration(days: d))),
                      style: const TextStyle(fontSize: 8, color: Colors.black38),
                    ),
                  );
                }
                if (d < 0 && d >= -_historyDays && (d == -_historyDays || (-d) % 3 == 0)) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _shortDate(today.add(Duration(days: d))),
                      style: const TextStyle(fontSize: 8, color: Colors.black38),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        betweenBarsData: foreSpots.length > 1
            ? [
                BetweenBarsData(
                  fromIndex: 2,
                  toIndex: 3,
                  color: Colors.orange.withValues(alpha: 0.12),
                ),
              ]
            : [],
        lineBarsData: [
          LineChartBarData(
            spots: histSpots,
            isCurved: true,
            color: const Color(0xFF1565C0),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: foreSpots,
            isCurved: true,
            color: Colors.orange,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: spot.x.toInt() == horizonDays ? 5 : 2.5,
                color: Colors.orange,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            dashArray: [6, 3],
            belowBarData: BarAreaData(show: false),
          ),
          LineChartBarData(
            spots: lowSpots,
            isCurved: true,
            color: Colors.orange.withValues(alpha: 0.3),
            barWidth: 1,
            dotData: const FlDotData(show: false),
            dashArray: [3, 5],
          ),
          LineChartBarData(
            spots: highSpots,
            isCurved: true,
            color: Colors.orange.withValues(alpha: 0.3),
            barWidth: 1,
            dotData: const FlDotData(show: false),
            dashArray: [3, 5],
          ),
        ],
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const CustomScaffold(
        showAppBar: false,
        child: Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32))),
      );
    }

    return CustomScaffold(
      showAppBar: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCountySelectorCard(),
            const SizedBox(height: 14),
            _buildDatePickerCard(),
            const SizedBox(height: 14),
            if (_forecastPoints.isEmpty) _buildEmptyState() else ...[
              _buildMetaCard(),
              const SizedBox(height: 14),
              _buildChartCard(),
              const SizedBox(height: 14),
              _buildPriceSummaryCard(),
              const SizedBox(height: 14),
              if (_recommendation != null) _buildRecommendationPreviewCard(),
              const SizedBox(height: 14),
              _buildActionButtons(),
            ],
            if (_forecastPoints.isEmpty) ...[
              const SizedBox(height: 20),
              _buildRunButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountySelectorCard() {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          if (_counties.isEmpty)
            Text(_selectedCountyName,
                style: const TextStyle(fontWeight: FontWeight.w500))
          else
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _selectedCountyId,
                  items: _counties
                      .map((c) => DropdownMenuItem<int>(
                            value: _countyIdOf(c)!,
                            child: Text(c['name']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w500)),
                          ))
                      .toList(),
                  onChanged: _onCountyChanged,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDatePickerCard() {
    final horizonDays =
        _selectedDate.difference(DateUtils.dateOnly(DateTime.now())).inDays;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Forecast Target Date',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: Color(0xFF2E7D32), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(_selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Text('+$horizonDays day${horizonDays == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.black45, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard() {
    return AppCard(
      child: Row(
        children: [
          Icon(
            _fromCache ? Icons.inventory_2_outlined : Icons.cloud_done_outlined,
            color: _fromCache ? Colors.orange : const Color(0xFF2E7D32),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fromCache ? "Cached forecast" : "Live model forecast",
                  style: TextStyle(
                    color: _fromCache ? Colors.orange : const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (_predictedAt != null)
                  Text(
                    "Generated: ${_predictedAt!.toLocal()}",
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Price Forecast Chart',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Row(
            children: [
              _legendDot(const Color(0xFF1565C0), 'Historical (actual)'),
              const SizedBox(width: 16),
              _legendDot(Colors.orange, 'Predicted', dashed: true),
            ],
          ),
          const SizedBox(height: 10),
          // Prior history range selector
          Row(
            children: [
              const Text(
                'Prior history:',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(width: 8),
              ...[3, 7, 14].map((days) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$days d',
                          style: const TextStyle(fontSize: 11)),
                      selected: _historyDays == days,
                      onSelected: (_) =>
                          setState(() => _historyDays = days),
                      selectedColor:
                          const Color(0xFF2E7D32).withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _historyDays == days
                            ? const Color(0xFF2E7D32)
                            : Colors.black54,
                        fontWeight: _historyDays == days
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 250, child: _buildChart()),
          const SizedBox(height: 6),
          const Text(
            'Shaded band = confidence range.',
            style: TextStyle(color: Colors.black38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSummaryCard() {
    final horizonDays =
        _selectedDate.difference(DateUtils.dateOnly(DateTime.now())).inDays;
    final targetPoint = _forecastPoints.isNotEmpty
        ? _forecastPoints.reduce((a, b) =>
            (a.day - horizonDays).abs() < (b.day - horizonDays).abs() ? a : b)
        : null;
    final week7 = _forecastPoints.where((p) => p.day <= 7).isNotEmpty
        ? _forecastPoints.lastWhere((p) => p.day <= 7)
        : null;

    return AppCard(
      child: Column(
        children: [
          PriceDataRow(label: 'Current price', pricePerKg: _currentPrice, color: Colors.grey, fontSize: 13),
          const Divider(height: 20),
          if (week7 != null) ...[
            PriceDataRow(label: 'In 7 days', pricePerKg: week7.predictedPrice, color: Colors.orange, fontSize: 13),
            const Divider(height: 20),
          ],
          if (targetPoint != null)
            PriceDataRow(
              label: 'On ${MaterialLocalizations.of(context).formatMediumDate(_selectedDate)} (Target)',
              pricePerKg: targetPoint.predictedPrice,
              fontSize: 13,
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendationPreviewCard() {
    final rec = _recommendation!;
    final decision = rec['decision'] as String?;
    final action = rec['action'] as String? ?? '';
    final color = _decisionColor(decision);
    final label = _decisionLabel(decision);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text('Advisory',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            action,
            style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orange),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'AI predictions may be inaccurate. Verify with local market data before making decisions.',
                  style: TextStyle(fontSize: 11, color: Colors.black45, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 30),
          const Icon(Icons.auto_graph, size: 60, color: Colors.black12),
          const SizedBox(height: 12),
          const Text('No forecast yet.',
              style: TextStyle(fontSize: 16, color: Colors.black45)),
          const SizedBox(height: 6),
          const Text('Pick a target date and tap Predict.',
              style: TextStyle(color: Colors.black38)),
        ],
      ),
    );
  }

  Widget _buildRunButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () => _runPrediction(),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('PREDICT',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () => _runPrediction(forceRefresh: true),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF2E7D32)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('REFRESH FORECAST',
                style: TextStyle(
                    color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _recommendation == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecommendationScreen(
                          forecastPoints: _forecastPoints,
                          historicalPoints: _historicalPoints,
                          recommendation: _recommendation!,
                          currentPrice: _currentPrice,
                          selectedDate: _selectedDate,
                          countyName: _selectedCountyName,
                        ),
                      ),
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('VIEW FULL RECOMMENDATION',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label, {bool dashed = false}) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 2.5,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : color,
            border: dashed ? Border(bottom: BorderSide(color: color, width: 2)) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }

}
