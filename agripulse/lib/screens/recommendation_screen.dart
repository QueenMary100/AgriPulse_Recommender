import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/prediction_service.dart';
import '../widgets/app_card.dart';
import '../widgets/custom_scaffold.dart';

// ── Tab wrapper: loads cached recommendation without needing a Scaffold ────────

class RecommendationTabScreen extends StatefulWidget {
  final int countyId;
  final String countyName;
  final int refreshToken;

  const RecommendationTabScreen({
    super.key,
    required this.countyId,
    required this.countyName,
    this.refreshToken = 0,
  });

  @override
  State<RecommendationTabScreen> createState() =>
      _RecommendationTabScreenState();
}

class _RecommendationTabScreenState extends State<RecommendationTabScreen> {
  final PredictionService _predictionService = PredictionService();
  bool _isLoading = true;
  PredictionResult? _cached;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  @override
  void didUpdateWidget(covariant RecommendationTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken ||
        widget.countyId != oldWidget.countyId) {
      _loadCache();
    }
  }

  Future<void> _loadCache() async {
    setState(() => _isLoading = true);
    try {
      final cached = await _predictionService.getCachedPredictionForCurrentWeek(
        countyId: widget.countyId,
      );
      if (mounted)
        setState(() {
          _cached = cached;
          _isLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
      );
    }

    if (_cached == null || _cached!.recommendation == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.tips_and_updates_outlined,
                size: 64,
                color: Colors.black12,
              ),
              const SizedBox(height: 16),
              const Text(
                'No recommendation yet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Run a forecast from the Analytics tab first, then come back here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black38, height: 1.5),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _loadCache,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rec = _cached!;
    return _RecommendationBody(
      forecastPoints: rec.forecastPoints,
      historicalPoints: rec.historicalPoints,
      recommendation: rec.recommendation!,
      currentPrice: rec.currentPrice,
      selectedDate:
          rec.selectedDate ?? DateTime.now().add(const Duration(days: 14)),
      countyName: widget.countyName,
      onRefresh: _loadCache,
    );
  }
}

// ── Shared content widget used by both push-screen and tab ────────────────────

class _RecommendationBody extends StatelessWidget {
  final List<ForecastPoint> forecastPoints;
  final List<HistoricalPoint> historicalPoints;
  final Map<String, dynamic> recommendation;
  final double currentPrice;
  final DateTime selectedDate;
  final String countyName;
  final VoidCallback? onRefresh; // non-null when shown as a tab

  const _RecommendationBody({
    required this.forecastPoints,
    required this.historicalPoints,
    required this.recommendation,
    required this.currentPrice,
    required this.selectedDate,
    required this.countyName,
    this.onRefresh,
  });

  // ── derived values ──────────────────────────────────────────────────────────

  String get _decision => recommendation['decision']?.toString() ?? 'sell_now';
  String get _action => recommendation['action']?.toString() ?? '';
  double get _slope => (recommendation['slope'] as num?)?.toDouble() ?? 0;
  double get _peakPrice =>
      (recommendation['peak_price'] as num?)?.toDouble() ?? currentPrice;
  int get _peakDay => (recommendation['peak_day'] as num?)?.toInt() ?? 0;
  String get _peakDate => recommendation['peak_date']?.toString() ?? '';
  double get _peakGainPerBag =>
      (recommendation['peak_gain_per_bag'] as num?)?.toDouble() ?? 0;
  List<String> get _factors {
    final raw = recommendation['factors'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  Color get _decisionColor {
    switch (_decision) {
      case 'wait':
        return const Color(0xFF2E7D32);
      case 'sell_soon':
        return Colors.orange;
      default:
        return Colors.redAccent;
    }
  }

  IconData get _decisionIcon {
    switch (_decision) {
      case 'wait':
        return Icons.schedule;
      case 'sell_soon':
        return Icons.trending_up;
      default:
        return Icons.point_of_sale;
    }
  }

  String get _decisionLabel {
    switch (_decision) {
      case 'wait':
        return 'WAIT';
      case 'sell_soon':
        return 'SELL SOON';
      default:
        return 'SELL NOW';
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Recommendation',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              countyName,
              style: const TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildDecisionHero(),
            const SizedBox(height: 16),
            _buildPriceComparisonCard(context),
            const SizedBox(height: 16),
            _buildTrendSummaryCard(),
            const SizedBox(height: 16),
            _buildFactorsSection(),
            const SizedBox(height: 16),
            if (forecastPoints.isNotEmpty) ...[
              _buildMiniChartCard(),
              const SizedBox(height: 16),
            ],
            // Price note
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF2E7D32),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'All prices shown are per 90 kg bag. '
                      'The model predicts in KES/kg and the app converts for farmer-facing display.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // AI disclaimer
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Disclaimer: AI-generated predictions may be inaccurate. '
                      'Market conditions can change rapidly due to weather, policy, or supply shocks. '
                      'Always verify with local traders or market authorities before making selling decisions.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (onRefresh != null) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text(
                    'REFRESH',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'BACK TO FORECAST',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  // ── sections ────────────────────────────────────────────────────────────────

  Widget _buildDecisionHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _decisionColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _decisionColor.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(_decisionIcon, color: Colors.white, size: 40),
          const SizedBox(height: 10),
          Text(
            _decisionLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _action,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceComparisonCard(BuildContext context) {
    final horizonDays = selectedDate
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    final targetPoint = forecastPoints.isNotEmpty
        ? forecastPoints.reduce(
            (a, b) => (a.day - horizonDays).abs() < (b.day - horizonDays).abs()
                ? a
                : b,
          )
        : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Price Comparison',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _priceColumn('Current', bagPrice(currentPrice), Colors.grey),
              const Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: Colors.black26,
              ),
              _priceColumn(
                'Peak${_peakDate.isNotEmpty ? '\n$_peakDate' : ' (Day +$_peakDay)'}',
                bagPrice(_peakPrice),
                Colors.orange,
              ),
              if (targetPoint != null) ...[
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: Colors.black26,
                ),
                _priceColumn(
                  MaterialLocalizations.of(
                    context,
                  ).formatShortDate(selectedDate),
                  bagPrice(targetPoint.predictedPrice),
                  const Color(0xFF2E7D32),
                ),
              ],
            ],
          ),
          if (_peakGainPerBag != 0) ...[
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Potential gain at peak:',
                  style: TextStyle(fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (_peakGainPerBag >= 0 ? Colors.green : Colors.red)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_peakGainPerBag >= 0 ? '+' : ''}KES ${_peakGainPerBag.toStringAsFixed(0)} / bag',
                    style: TextStyle(
                      color: _peakGainPerBag >= 0
                          ? const Color(0xFF2E7D32)
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendSummaryCard() {
    final isRising = _slope > 0.15;
    final isFalling = _slope < -0.15;
    final trendLabel = isRising
        ? 'Rising'
        : isFalling
        ? 'Falling'
        : 'Stable';
    final trendColor = isRising
        ? const Color(0xFF2E7D32)
        : isFalling
        ? Colors.redAccent
        : Colors.orange;
    final trendIcon = isRising
        ? Icons.trending_up
        : isFalling
        ? Icons.trending_down
        : Icons.trending_flat;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trend Summary',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statChip(
                icon: trendIcon,
                label: trendLabel,
                value:
                    '${_slope >= 0 ? '+' : ''}${_slope.toStringAsFixed(2)} KES/kg/day',
                color: trendColor,
              ),
              const SizedBox(width: 10),
              _statChip(
                icon: Icons.flag_outlined,
                label: 'Peak Day',
                value: _peakDay > 0 ? 'Day +$_peakDay' : '—',
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFactorsSection() {
    if (_factors.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Key Influencing Factors',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        ..._factors.asMap().entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildFactorCard(e.key, e.value),
          ),
        ),
      ],
    );
  }

  Widget _buildFactorCard(int index, String factor) {
    const icons = [
      Icons.agriculture,
      Icons.water_drop_outlined,
      Icons.local_gas_station_outlined,
      Icons.show_chart,
      Icons.calendar_month_outlined,
    ];
    const colors = [
      Color(0xFF2E7D32),
      Colors.blue,
      Colors.deepOrange,
      Colors.purple,
      Colors.teal,
    ];
    final icon = icons[index % icons.length];
    final color = colors[index % colors.length];
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              factor,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChartCard() {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final horizonDays = selectedDate.difference(todayOnly).inDays;
    final List<FlSpot> spots = [FlSpot(0, bagPrice(currentPrice))];
    for (final p in forecastPoints) {
      if (p.day > horizonDays) break;
      spots.add(FlSpot(p.day.toDouble(), bagPrice(p.predictedPrice)));
    }
    if (spots.length < 2) return const SizedBox.shrink();
    final prices = spots.map((s) => s.y).toList();
    final minY = prices.reduce((a, b) => a < b ? a : b) - 80;
    final maxY = prices.reduce((a, b) => a > b ? a : b) + 80;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Forecast Trend',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: _decisionColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _decisionColor.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceColumn(String label, double bagPriceVal, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black45),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'KES ${bagPriceVal.toStringAsFixed(0)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Push-navigation screen (launched from Analytics via Navigator.push) ────────

class RecommendationScreen extends StatelessWidget {
  final List<ForecastPoint> forecastPoints;
  final List<HistoricalPoint> historicalPoints;
  final Map<String, dynamic> recommendation;
  final double currentPrice;
  final DateTime selectedDate;
  final String countyName;

  const RecommendationScreen({
    super.key,
    required this.forecastPoints,
    required this.historicalPoints,
    required this.recommendation,
    required this.currentPrice,
    required this.selectedDate,
    required this.countyName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 35),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: _RecommendationBody(
        forecastPoints: forecastPoints,
        historicalPoints: historicalPoints,
        recommendation: recommendation,
        currentPrice: currentPrice,
        selectedDate: selectedDate,
        countyName: countyName,
      ),
    );
  }
}
