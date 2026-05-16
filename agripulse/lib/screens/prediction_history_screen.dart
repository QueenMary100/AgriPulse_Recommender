import 'package:flutter/material.dart';

import '../services/prediction_service.dart';
import '../widgets/app_card.dart';
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
    if (widget.refreshToken != oldWidget.refreshToken) _loadHistory();
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
              backgroundColor: kGreen,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text('Prediction History',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: CustomScaffold(
        showAppBar: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.green))
            : _rows.isEmpty
                ? const Center(
                    child: Text(
                      'No history yet. Run a prediction to see records here.',
                      style: TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildCard(_rows[index]),
                  ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final horizon = (row['horizon'] as int?) ?? 14;
    final predictedPrice = _toDouble(row['predicted_price']);
    final currentPrice = _toDouble(row['current_price']);
    final model = row['model']?.toString();
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: county + sync badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  row['county_name']?.toString() ?? 'Unknown county',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _syncBadge(row['sync_status']?.toString()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Week key: ${row['cache_week_key']}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          if (createdAt != null)
            Text(
              'Created: $createdAt',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          const Divider(height: 22),

          // Price rows
          PriceDataRow(
            label: 'Current Price',
            pricePerKg: currentPrice,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 10),
          PriceDataRow(
            label: 'Predicted Price (+${horizon}d)',
            pricePerKg: predictedPrice,
          ),

          // Model name
          if (model != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Model',
                    style: TextStyle(fontSize: 13, color: Colors.black54)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    model,
                    style: const TextStyle(
                        fontSize: 12,
                        color: kGreen,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _syncBadge(String? status) {
    final isSynced = status == 'synced';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isSynced ? Colors.green : Colors.orange)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isSynced ? 'Synced' : 'Local cache',
        style: TextStyle(
          color: isSynced ? kGreen : Colors.orange.shade800,
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
