import 'package:flutter/material.dart';

import '../services/prediction_service.dart';
import '../widgets/custom_scaffold.dart';

class PredictionHistoryScreen extends StatefulWidget {
  final bool showAppBar;
  final int refreshToken;

  const PredictionHistoryScreen({
    super.key,
    this.showAppBar = true,
    this.refreshToken = 0,
  });

  @override
  State<PredictionHistoryScreen> createState() =>
      _PredictionHistoryScreenState();
}

class _PredictionHistoryScreenState extends State<PredictionHistoryScreen> {
  static const double _bagSizeKg = 90;
  final PredictionService _predictionService = PredictionService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant PredictionHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _predictionService.getUserHistory();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: const Color(0xFF2E7D32),
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'Prediction History',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: CustomScaffold(
        showAppBar: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.green),
              )
            : _rows.isEmpty
            ? const Center(
                child: Text(
                  'No history yet. Run a prediction to see records here.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _rows.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final week1 = _toDouble(row['week_1']);
                  final week2 = _toDouble(row['week_2']);
                  final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
                 

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                row['county_name']?.toString() ?? 'Unknown county',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildSyncBadge(row['sync_status']?.toString()),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Week key: ${row['cache_week_key']}",
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                        if (createdAt != null)
                          Text(
                            "Created: ${createdAt.toLocal()}",
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        const Divider(height: 22),
                        _dataRow("Current", _toDouble(row['current_price'])),
                        _dataRow("Week 1", week1),
                        _dataRow("Week 2", week2),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _dataRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            "KES ${(value * _bagSizeKg).toStringAsFixed(0)}",
            style: const TextStyle(
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncBadge(String? syncStatus) {
    final isSynced = syncStatus == 'synced';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isSynced ? Colors.green : Colors.orange).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isSynced ? 'Synced' : 'Local cache',
        style: TextStyle(
          color: isSynced ? const Color(0xFF2E7D32) : Colors.orange.shade800,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
