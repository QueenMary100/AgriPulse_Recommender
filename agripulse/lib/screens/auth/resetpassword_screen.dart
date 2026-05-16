import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/custom_scaffold.dart';
import '../../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final AuthService _authService = AuthService();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // Password validation getters
  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasUppercase =>
      _newPasswordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase =>
      _newPasswordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _isPasswordValid =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber;

  void _resetPassword() async {
    // 1. Extract the email passed as an argument from ForgotPasswordScreen
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args == null || args is! String) {
      _showError("Session expired. Please request a new code.");
      return;
    }
    final String email = args;

    if (_otpController.text.length != 6) {
      _showError("Please enter a valid 6-digit OTP");
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showError("Passwords do not match");
      return;
    }

    if (!_isPasswordValid) {
      _showError("Please meet all password requirements");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Verify the OTP (This creates a temporary authenticated session)
      await _authService.verifyEmailOTP(
        email: email,
        token: _otpController.text.trim(),
      );

      // Step 2: Update the password while the session is active
      await _authService.updatePassword(_newPasswordController.text.trim());

      // Step 3: Log out immediately to force a fresh login with the new credentials
      await _authService.logOut();

      if (mounted) {
        _showSuccess("Password reset successful! Please login.");
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError("An unexpected error occurred. Try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resendOtp() async {
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args != null && args is String) {
      try {
        await _authService.sendPasswordReset(args);
        _showSuccess("A new code has been sent to $args");
      } catch (e) {
        _showError("Could not resend code.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: true,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Image.asset('assets/images/logo.png', height: 80),
                const SizedBox(height: 20),
                const Text(
                  "Reset Password",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Enter the 6-digit code sent to your email and your new password.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 30),

                _buildField(
                  controller: _otpController,
                  hint: "Enter 6-digit OTP",
                  icon: Icons.verified_user,
                  type: TextInputType.number,
                ),
                const SizedBox(height: 15),

                _buildField(
                  controller: _newPasswordController,
                  hint: "New Password",
                  icon: Icons.lock,
                  isPassword: true,
                  isObscured: _obscureNewPassword,
                  onToggle: () => setState(
                    () => _obscureNewPassword = !_obscureNewPassword,
                  ),
                ),
                const SizedBox(height: 15),

                _buildField(
                  controller: _confirmPasswordController,
                  hint: "Confirm New Password",
                  icon: Icons.lock_outline,
                  isPassword: true,
                  isObscured: _obscureConfirmPassword,
                  onToggle: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),

                const SizedBox(height: 15),
                _buildRequirementList(),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "RESET PASSWORD",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _resendOtp,
                  child: const Text(
                    "Resend OTP",
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Remember Password?",
                      style: TextStyle(color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false),
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Helpers ---
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isObscured = false,
    VoidCallback? onToggle,
    TextInputType type = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: TextField(
        controller: controller,
        obscureText: isObscured,
        keyboardType: type,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.green),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isObscured ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: onToggle,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementList() {
    return Column(
      children: [
        _requirementItem("8+ Characters", _hasMinLength),
        _requirementItem(
          "Uppercase & Lowercase",
          _hasUppercase && _hasLowercase,
        ),
        _requirementItem("Includes a number", _hasNumber),
      ],
    );
  }

  Widget _requirementItem(String text, bool valid) {
    return Row(
      children: [
        Icon(
          valid ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: valid ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: valid ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }

  void _showError(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  void _showSuccess(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.green));
}
