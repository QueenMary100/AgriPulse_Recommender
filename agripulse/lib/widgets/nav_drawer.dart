import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../screens/main_wrapper.dart';
import '../screens/auth/login_screen.dart';

class NavDrawer extends StatefulWidget {
  const NavDrawer({super.key});

  @override
  State<NavDrawer> createState() => _NavDrawerState();
}

class _NavDrawerState extends State<NavDrawer> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  String userName = "Farmer";
  String location = "Loading...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final data = await _dbService.getUserProfile();
      if (mounted) {
        setState(() {
          userName = data['full_name'] ?? "Farmer";
          // Safely access the nested county name from the join
          location = (data['counties'] != null)
              ? data['counties']['name']
              : "Location not set";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogout() async {
    await _authService.logOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          //  Drawer Header with Live Data
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 20),
            color: const Color(0xFF2E7D32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 45, color: Colors.grey),
                ),
                const SizedBox(height: 15),
                Text(
                  _isLoading ? "..." : "Hello, $userName!",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  location,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          _buildDrawerItem(
            icon: Icons.grid_view_rounded,
            title: "Dashboard",
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainWrapper(initialIndex: 0),
                ),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.analytics_rounded,
            title: "Forecast Analytics",
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainWrapper(initialIndex: 1),
                ),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.history_rounded,
            title: "Prediction History",
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainWrapper(initialIndex: 2),
                ),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.tips_and_updates_rounded,
            title: "Recommendation",
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainWrapper(initialIndex: 3),
                ),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.person_outline_rounded,
            title: "My Profile",
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainWrapper(initialIndex: 4),
                ),
              );
            },
          ),

          const Spacer(), 
          const Divider(),

          // Logout Item
          _buildDrawerItem(
            icon: Icons.logout_rounded,
            title: "Logout",
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: _handleLogout,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? const Color(0xFF2E7D32)),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
