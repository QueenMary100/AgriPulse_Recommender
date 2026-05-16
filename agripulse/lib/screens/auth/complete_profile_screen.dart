import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/database_service.dart';
import '../../widgets/custom_scaffold.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  List<Map<String, dynamic>> _counties = [];
  int? _selectedCountyId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final counties = await _dbService.getCounties();
      final existing = await _dbService.getUserProfileOrNull();
      final user = Supabase.instance.client.auth.currentUser;

      final metaName =
          user?.userMetadata?['full_name'] ??
          user?.userMetadata?['name'] ??
          user?.email?.split('@').first;

      _nameController.text =
          existing?['full_name']?.toString() ?? metaName?.toString() ?? '';
      _phoneController.text = existing?['phone_number']?.toString() ?? '';

      final countyRaw = existing?['county_id'];
      _selectedCountyId = countyRaw is num
          ? countyRaw.toInt()
          : int.tryParse(countyRaw?.toString() ?? '');

      if (_selectedCountyId == null && counties.isNotEmpty) {
        final firstIdRaw = counties.first['id'];
        _selectedCountyId = firstIdRaw is num
            ? firstIdRaw.toInt()
            : int.tryParse(firstIdRaw?.toString() ?? '');
      }

      if (!mounted) return;
      setState(() {
        _counties = counties;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile form: $e')));
    }
  }

  Future<void> _saveAndContinue() async {
    final fullName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final countyId = _selectedCountyId;

    if (fullName.isEmpty || phone.isEmpty || countyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _dbService.upsertUserProfile(
        fullName: fullName,
        phoneNumber: phone,
        countyId: countyId,
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: false,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Complete Your Profile',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please provide your details before continuing.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  _textField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_android_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  _countyDropdown(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'SAVE & CONTINUE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF2E7D32)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _countyDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedCountyId,
                isExpanded: true,
                hint: const Text('Select County'),
                items: _counties
                    .map(
                      (county) => DropdownMenuItem<int>(
                        value: (county['id'] as num).toInt(),
                        child: Text(county['name']?.toString() ?? 'County'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCountyId = value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
