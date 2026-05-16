import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'dashboard_screen.dart';
import 'forecast_screen.dart';
import 'prediction_history_screen.dart';
import 'profile_screen.dart';
import 'recommendation_screen.dart';
import '../widgets/nav_drawer.dart';

class MainWrapper extends StatefulWidget {
  final int initialIndex;

  const MainWrapper({super.key, this.initialIndex = 0});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  late int _selectedIndex;
  final DatabaseService _dbService = DatabaseService();
  int _historyRefreshToken = 0;
  int _analyticsRefreshToken = 0;
  DateTime _dashboardSelectedDate = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 1)),
  );

  String _countyName = 'Loading...';
  int _countyId = 0;
  double _currentPrice = 0.0;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _fetchUserContext();
  }

  Future<void> _fetchUserContext() async {
    try {
      final profile = await _dbService.getUserProfile();
      final price = await _dbService.getLatestPrice(profile['counties']['id']);
      if (mounted) {
        setState(() {
          _countyId = profile['counties']['id'];
          _countyName = profile['counties']['name'];
          _currentPrice = price;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingData = false);
      debugPrint('Error in MainWrapper Context: $e');
    }
  }

  Future<void> _handleSharedCountyChanged(
    int countyId,
    String countyName,
  ) async {
    if (countyId == _countyId && countyName == _countyName) return;
    final latestPrice = await _dbService.getLatestPrice(countyId);
    if (!mounted) return;
    setState(() {
      _countyId = countyId;
      _countyName = countyName;
      _currentPrice = latestPrice;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
        ),
      );
    }

    final List<Widget> screens = [
      // 0 — Dashboard
      DashboardScreen(
        onPredictionComplete: (date) => setState(() {
          _dashboardSelectedDate = date;
          _analyticsRefreshToken++;
        }),
      ),
      // 1 — Forecast Analytics
      ForecastScreen(
        countyId: _countyId,
        countyName: _countyName,
        currentPrice: _currentPrice,
        initialSelectedDate: _dashboardSelectedDate,
        refreshToken: _analyticsRefreshToken,
        onCountyChanged: _handleSharedCountyChanged,
      ),
      // 2 — History
      PredictionHistoryScreen(
        showAppBar: false,
        refreshToken: _historyRefreshToken,
      ),
      // 3 — Recommendation
      RecommendationTabScreen(
        countyId: _countyId,
        countyName: _countyName,
        refreshToken: _analyticsRefreshToken,
      ),
      // 4 — Profile
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 35),
            const SizedBox(width: 8),
          ],
        ),
      ),
      drawer: const NavDrawer(),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            if (index == 2) _historyRefreshToken++;
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tips_and_updates_outlined),
            activeIcon: Icon(Icons.tips_and_updates),
            label: 'Recommendation',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
