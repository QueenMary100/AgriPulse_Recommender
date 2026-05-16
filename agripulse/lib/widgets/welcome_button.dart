import 'package:flutter/material.dart';

class WelcomeButton extends StatelessWidget {
  const WelcomeButton({
    super.key,
    this.buttonText,
    this.onTap,
    this.color,
    this.textColor,
  });

  final String? buttonText;
  final VoidCallback? onTap; 
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 25.0),
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(50)),
        ),
        child: Text(
          buttonText!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
            color: textColor ?? Colors.black,
          ),
        ),
      ),
    );
  }
}
