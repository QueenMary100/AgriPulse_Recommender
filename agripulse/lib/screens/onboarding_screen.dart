import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/custom_scaffold.dart';
import '../widgets/welcome_button.dart';
import '../widgets/dot.dart';
import 'auth/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  final List<Map<String, String>> onboardingData = [
    {
      "title": "Track Prices",
      "desc": "Get real-time maize market prices across Kenya.",
    },
    {
      "title": "Predict Trends",
      "desc": "AI-powered forecasting for your next harvest.",
    },
    {
      "title": "Expert Advice",
      "desc": "Smart recommendations for small-scale farmers.",
    },
  ];

  @override
  void initState() {
    super.initState();
    // Auto-scroll logic: runs every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPage < onboardingData.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0; // Loop back to start
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    // To always cancel timers when the widget is destroyed
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: false,
      child: Column(
        children: [
          // 1. Carousel Section (Flex 8)
          Flexible(
            flex: 8,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (value) => setState(() => _currentPage = value),
              itemCount: onboardingData.length,
              itemBuilder: (context, index) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/logo.png', width: 200),
                  const SizedBox(height: 40),
                  Text(
                    onboardingData[index]['title']!,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32), // agripulse brand green
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      onboardingData[index]['desc']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Navigation Section (Flex 2)
          Flexible(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    onboardingData.length,
                    (index) => Dot(isActive: _currentPage == index),
                  ),
                ),
                const SizedBox(height: 30),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: WelcomeButton(
                        buttonText: "SKIP",
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        ),
                        color: Colors.transparent,
                        textColor: Colors.black54,
                      ),
                    ),
                    Expanded(
                      child: WelcomeButton(
                        buttonText: "NEXT",
                        onTap: () {
                          if (_currentPage == onboardingData.length - 1) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeIn,
                            );
                          }
                        },
                        color: Colors.white,
                        textColor: const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
