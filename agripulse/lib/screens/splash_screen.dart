import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/database_service.dart';
import '../widgets/custom_scaffold.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final DatabaseService _dbService = DatabaseService();

  Future<void> _routeAfterSessionCheck() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
      return;
    }

    final profileComplete = await _dbService.isProfileComplete();
    if (!mounted) return;
    if (profileComplete) {
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      Navigator.pushReplacementNamed(context, '/complete-profile');
    }
  }

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _routeAfterSessionCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 200),
            const SizedBox(height: 20),
            const Text(
              "Smart Maize Market Advisor",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// // lib/screens/splash_screen.dart
// import 'package:flutter/material.dart';
// import '../widgets/custom_scaffold.dart';
// import '../theme/app_theme.dart';
// import 'onboarding_screen.dart';

// class SplashScreen extends StatefulWidget {
//   const SplashScreen({super.key});

//   @override
//   State<SplashScreen> createState() => _SplashScreenState();
// }

// class _SplashScreenState extends State<SplashScreen> {
//   @override
//   void initState() {
//     super.initState();
//     Future.delayed(const Duration(seconds: 3), () {
//       if (mounted) {
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (_) => const OnboardingScreen()),
//         );
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return CustomScaffold(
//       showAppBar: false,
//       child: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             // Logo
//             Image.asset('assets/images/logo.png', width: 200),
//             const SizedBox(height: 20),
//             // Tagline in your specific green shade
//             const Text(
//               "Smart Maize Market Advisor",
//               style: TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.w500,
//                 color: AppTheme.primaryGreen, // Using your 0xFF2E7D32
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
