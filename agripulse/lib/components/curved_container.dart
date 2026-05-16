import 'package:flutter/material.dart';

class CurvedContainer extends StatelessWidget {
  final Widget child;
  final double flex;

  const CurvedContainer({super.key, required this.child, this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex.toInt(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(25.0, 50.0, 25.0, 20.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(40.0),
            topRight: Radius.circular(40.0),
          ),
        ),
        child: child,
      ),
    );
  }
}
