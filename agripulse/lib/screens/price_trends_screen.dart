import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../widgets/app_card.dart';
import '../widgets/custom_scaffold.dart';

class PriceTrendsScreen extends StatefulWidget {
  final int countyId;
  final String countyName;
  final Future<void> Function(int countyId, String countyName)? onCountyChanged;

  const PriceTrendsScreen({
    super.key,
    required this.countyId,
    required this.countyName,
    this.onCountyChanged,
  });

  @override
  State<PriceTrendsScreen> createState() => _PriceTrendsScreenState();
}

class _PriceTrendsScreenState extends State<PriceTrendsScreen> {
  final DatabaseService _dbService = DatabaseService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _counties = [];
  late int _selectedCountyId;
  late String _selectedCountyName;
  int _weeksLimit = 8;

  @override
  void initState() {
    super.initState();
    _selectedCountyId = widget.countyId;
    _selectedCountyName = widget.countyName;
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant PriceTrendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.countyId != oldWidget.countyId ||
        widget.countyName != oldWidget.countyName) {
      _selectedCountyId = widget.countyId;
      _selectedCountyName = widget.countyName;
      _loadTrends();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final counties = await _dbService.getCounties();
      final validCounties = counties
          .where((row) => _countyIdOf(row) != null)
          .toList();
      if (!mounted) return;
      if (validCounties.isNotEmpty) {
        final hasSelected = validCounties.any(
          (row) => _countyIdOf(row) == _selectedCountyId,
        );
        if (!hasSelected) {
          _selectedCountyId = _countyIdOf(validCounties.first)!;
          _selectedCountyName =
              validCounties.first['name']?.toString() ?? 'County';
        }
      }
      setState(() {
        _counties = validCounties;
      });
      await _loadTrends(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTrends({bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final rows = await _dbService.getRecentWeeklyPrices(_selectedCountyId, limit: _weeksLimit);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onCountyChanged(int? countyId) async {
    if (countyId == null || countyId == _selectedCountyId) return;
    final county = _counties.firstWhere(
      (row) => _countyIdOf(row) == countyId,
      orElse: () => {'id': countyId, 'name': _selectedCountyName},
    );
    setState(() {
      _selectedCountyId = countyId;
      _selectedCountyName = county['name']?.toString() ?? _selectedCountyName;
      _rows = [];
    });
    await widget.onCountyChanged?.call(_selectedCountyId, _selectedCountyName);
    await _loadTrends();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const CustomScaffold(
        showAppBar: false,
        child: Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32))),
      );
    }

    if (_rows.isEmpty) {
      return CustomScaffold(
        showAppBar: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.show_chart, size: 52, color: Colors.black26),
              const SizedBox(height: 8),
              const Text(
                'No weekly price trend data found.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadTrends,
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      );
    }

    final bagPrices = _rows.map((e) => bagPrice(_toDouble(e['price']))).toList();

    return CustomScaffold(
      showAppBar: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCountySelectorCard(),
            const SizedBox(height: 16),
            _buildChartCard(bagPrices),
            const SizedBox(height: 16),
            _buildWeeklyListCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildCountySelectorCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          if (_counties.isEmpty)
            Text(
              _selectedCountyName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            )
          else
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _selectedCountyId,
                  items: _counties
                      .map(
                        (county) => DropdownMenuItem<int>(
                          value: (county['id'] as num).toInt(),
                          child: Text(
                            county['name']?.toString() ?? 'County',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _onCountyChanged,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartCard(List<double> bagPrices) {
    final chartValues = bagPrices.length == 1
        ? <double>[bagPrices.first, bagPrices.first]
        : bagPrices;
    final minY = chartValues.reduce((a, b) => a < b ? a : b);
    final maxY = chartValues.reduce((a, b) => a > b ? a : b);
    final delta = (maxY - minY).abs();
    final padding = (delta * 0.2).clamp(80.0, 220.0);
    final hInterval = ((delta <= 0 ? 100.0 : delta) / 4).clamp(50.0, 400.0);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price Trends (Last $_weeksLimit Weeks)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          // Weeks range selector
          Row(
            children: [
              const Text('Show:',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(width: 8),
              ...[4, 8, 12, 16].map((weeks) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$weeks w',
                          style: const TextStyle(fontSize: 11)),
                      selected: _weeksLimit == weeks,
                      onSelected: (selected) {
                        if (!selected || _weeksLimit == weeks) return;
                        setState(() => _weeksLimit = weeks);
                        _loadTrends();
                      },
                      selectedColor: Colors.orange.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _weeksLimit == weeks
                            ? Colors.orange.shade800
                            : Colors.black54,
                        fontWeight: _weeksLimit == weeks
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                minY: minY - padding,
                maxY: maxY + padding,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: hInterval,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.black12, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    axisNameWidget: const RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'Price (KES / 90 kg bag)',
                        style: TextStyle(fontSize: 9, color: Colors.black45),
                      ),
                    ),
                    axisNameSize: 32,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) {
                        if (!value.isFinite || value.isNaN) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          '${(value / 1000).toStringAsFixed(1)}K',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text(
                      'Weeks from today',
                      style: TextStyle(fontSize: 9, color: Colors.black45),
                    ),
                    axisNameSize: 16,
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        if (!value.isFinite || value.isNaN) {
                          return const SizedBox.shrink();
                        }
                        final i = value.toInt();
                        if (i < 0 || i >= chartValues.length) {
                          return const SizedBox.shrink();
                        }
                        final weeksAgo = chartValues.length - 1 - i;
                        final isToday = weeksAgo == 0;
                        // For large datasets skip odd indices but always show Today
                        if (chartValues.length > 8 && !isToday && i % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        final label = isToday ? 'Today' : '-${weeksAgo}w';
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 9,
                              color: isToday
                                  ? const Color(0xFF2E7D32)
                                  : Colors.black45,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: chartValues
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                    isCurved: true,
                    curveSmoothness: 0.28,
                    color: Colors.orange.shade700,
                    barWidth: 4,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 3.6,
                        color: Colors.orange.shade700,
                        strokeColor: Colors.white,
                        strokeWidth: 1.2,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orange.withValues(alpha: 0.12),
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

  Widget _buildWeeklyListCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Weekly Prices',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          ..._rows.reversed.map((row) {
            final date = DateTime.tryParse(row['date']?.toString() ?? '');
            final bag = bagPrice(_toDouble(row['price']));
            final dateText = date == null
                ? '-'
                : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateText, style: const TextStyle(color: Colors.black54)),
                  Text(
                    'KES ${bag.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int? _countyIdOf(Map<String, dynamic> row) {
    final raw = row['id'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

}
