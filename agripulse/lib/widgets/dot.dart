import 'package:flutter/material.dart'; 

class Dot extends StatelessWidget {
  final bool isActive;
  const Dot({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 12 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
