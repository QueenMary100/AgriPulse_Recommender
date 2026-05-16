import 'package:flutter/material.dart';

const double kBagKg = 90.0;
const Color kGreen = Color(0xFF2E7D32);

double bagPrice(double pricePerKg) => pricePerKg * kBagKg;

String formatBagPrice(double pricePerKg) =>
    'KES ${bagPrice(pricePerKg).toStringAsFixed(0)}';

/// Shared card container used across all screens.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A label + KES price row used inside cards.
class PriceDataRow extends StatelessWidget {
  final String label;
  final double pricePerKg;
  final Color color;
  final double fontSize;

  const PriceDataRow({
    super.key,
    required this.label,
    required this.pricePerKg,
    this.color = kGreen,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: fontSize, color: Colors.black87),
          ),
        ),
        Text(
          formatBagPrice(pricePerKg),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: fontSize + 1,
          ),
        ),
      ],
    );
  }
}
