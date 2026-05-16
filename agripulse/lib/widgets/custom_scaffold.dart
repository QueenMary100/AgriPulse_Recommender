import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CustomScaffold extends StatelessWidget {
  const CustomScaffold({super.key, this.child, this.showAppBar = true});
  final Widget? child;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: showAppBar
          ? AppBar(
              iconTheme: const IconThemeData(color: Colors.white),
              backgroundColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
          ),

          Image.asset(
            'assets/images/backgroundimg.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            opacity: const AlwaysStoppedAnimation(0.4),
          ),

          // 3. The Content
          SafeArea(child: child!),
        ],
      ),
    );
  }
}
