import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/custom_scaffold.dart';
import 'auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _counties = [];
  int? _selectedCountyId;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfileData() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _dbService.getUserProfile();
      final counties = await _dbService.getCounties();
      if (!mounted) return;

      _nameController.text = profile['full_name']?.toString() ?? '';
      _phoneController.text = profile['phone_number']?.toString() ?? '';

      final countyIdRaw = profile['county_id'];
      final countyId = countyIdRaw is num
          ? countyIdRaw.toInt()
          : int.tryParse(countyIdRaw?.toString() ?? '');

      setState(() {
        _userData = profile;
        _counties = counties;
        _selectedCountyId = countyId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error loading profile: $e")));
    }
  }

  Future<void> _saveProfile() async {
    final fullName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final countyId = _selectedCountyId;

    if (fullName.isEmpty || phone.isEmpty || countyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all profile fields.")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _dbService.updateUserProfile(
        fullName: fullName,
        phoneNumber: phone,
        countyId: countyId,
      );
      await _fetchProfileData();
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update profile: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _cancelEdit() {
    if (_userData != null) {
      _nameController.text = _userData?['full_name']?.toString() ?? '';
      _phoneController.text = _userData?['phone_number']?.toString() ?? '';
      final countyIdRaw = _userData?['county_id'];
      _selectedCountyId = countyIdRaw is num
          ? countyIdRaw.toInt()
          : int.tryParse(countyIdRaw?.toString() ?? '');
    }
    setState(() => _isEditing = false);
  }

  Future<void> _handleLogout() async {
    await _authService.logOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: false,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                children: [
                  const Text(
                    "Farmer Profile",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 60, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  _buildTextFieldTile(
                    icon: Icons.person_outline,
                    label: "Full Name",
                    controller: _nameController,
                    enabled: _isEditing,
                  ),
                  _buildReadOnlyTile(
                    icon: Icons.email_outlined,
                    fieldLabel: "Email",
                    value: _authService.currentUser?.email ?? "No email",
                  ),
                  _buildCountyTile(),
                  _buildReadOnlyTile(
                    icon: Icons.flag_outlined,
                    fieldLabel: "Country",
                    value: "Kenya",
                  ),
                  _buildTextFieldTile(
                    icon: Icons.phone_android_outlined,
                    label: "Phone Number",
                    controller: _phoneController,
                    enabled: _isEditing,
                  ),
                  const SizedBox(height: 28),
                  if (!_isEditing)
                    _buildActionButton(
                      label: "EDIT PROFILE",
                      color: const Color(0xFF2E7D32),
                      onTap: () => setState(() => _isEditing = true),
                    )
                  else ...[
                    _buildActionButton(
                      label: _isSaving ? "SAVING..." : "SAVE CHANGES",
                      color: const Color(0xFF2E7D32),
                      onTap: _isSaving ? null : _saveProfile,
                    ),
                    const SizedBox(height: 12),
                    _buildActionButton(
                      label: "CANCEL",
                      color: Colors.grey,
                      onTap: _isSaving ? null : _cancelEdit,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildActionButton(
                    label: "LOGOUT",
                    color: Colors.orange,
                    onTap: _handleLogout,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextFieldTile({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: !enabled,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(
                  color: Color(0xFF558B2F),
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelStyle: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountyTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: Color(0xFF2E7D32)),
          const SizedBox(width: 14),
          Expanded(
            child: _isEditing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'County',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF558B2F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedCountyId,
                          isExpanded: true,
                          hint: const Text(
                            "Select County",
                            style: TextStyle(color: Colors.black54),
                          ),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          items: _counties
                              .map(
                                (county) => DropdownMenuItem<int>(
                                  value: (county['id'] as num).toInt(),
                                  child: Text(county['name']?.toString() ?? 'County'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedCountyId = value;
                            });
                          },
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'County',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF558B2F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _userData?['counties']?['name'] ?? 'County not set',
                        style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyTile({
    required IconData icon,
    required String fieldLabel,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fieldLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF558B2F),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
