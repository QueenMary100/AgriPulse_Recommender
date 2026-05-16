import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';  //connect to supabase database
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/complete_profile_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/resetpassword_screen.dart';
import 'screens/main_wrapper.dart'; 
import 'theme/app_theme.dart';

Future<void> main() async {
  //  Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  //  Initialize Supabase
  await Supabase.initialize(
    url: 'https://nugrhcilsasqkggssraa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im51Z3JoY2lsc2FzcWtnZ3NzcmFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MTU2MjEsImV4cCI6MjA5MDM5MTYyMX0.u3uhS8VXPNi1Ui6bNfobd3gaIYpC8gAqIIDlH0sEmFE', // Replace with your Anon Key
  );

  runApp(const AgriPulseApp());
}

class AgriPulseApp extends StatelessWidget {
  const AgriPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AgriPulse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primaryGreen,
          primary: AppTheme.primaryGreen
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      // The Splash Screen will check if the user is logged in
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/complete-profile': (context) => const CompleteProfileScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/main': (context) => const MainWrapper(), // Added Main route
      },
    );
  }
}
