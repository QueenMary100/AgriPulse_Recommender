import 'package:flutter/material.dart';
import '../widgets/custom_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _showOtpField = false;
  bool _showPasswordFields = false;

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
                const SizedBox(height: 40),

                // 🌿 Logo
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
                  "Enter your phone number to receive a verification code",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),

                const SizedBox(height: 40),

                // 📱 Phone Number Field
                if (!_showOtpField && !_showPasswordFields) ...[
                  _inputField(
                    controller: _phoneController,
                    icon: Icons.phone,
                    hint: "Phone Number",
                    keyboardType: TextInputType.phone,
                  ),

                  const SizedBox(height: 30),

                  // 🔘 Send OTP Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _sendOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                      ),
                      child: const Text(
                        "SEND OTP",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],

                // 🔢 OTP Field
                if (_showOtpField && !_showPasswordFields) ...[
                  _inputField(
                    controller: _otpController,
                    icon: Icons.verified_user,
                    hint: "Enter OTP",
                    keyboardType: TextInputType.number,
                  ),

                  const SizedBox(height: 30),

                  // 🔘 Verify OTP Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                      ),
                      child: const Text(
                        "VERIFY OTP",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],

                // 🔐 Password Fields
                if (_showPasswordFields) ...[
                  _inputField(
                    controller: _newPasswordController,
                    icon: Icons.lock,
                    hint: "New Password",
                    isPassword: true,
                  ),

                  const SizedBox(height: 15),

                  _inputField(
                    controller: _confirmPasswordController,
                    icon: Icons.lock,
                    hint: "Confirm New Password",
                    isPassword: true,
                  ),

                  const SizedBox(height: 30),

                  // 🔘 Reset Password Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                      ),
                      child: const Text(
                        "RESET PASSWORD",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // 🔙 Back to Login
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Back to Login",
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: Colors.green),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15),
        ),
      ),
    );
  }

  void _sendOtp() {
    if (_phoneController.text.isNotEmpty) {
      setState(() {
        _showOtpField = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("OTP sent to your phone number"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _verifyOtp() {
    if (_otpController.text.isNotEmpty) {
      setState(() {
        _showPasswordFields = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("OTP verified successfully"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _resetPassword() {
    if (_newPasswordController.text == _confirmPasswordController.text &&
        _newPasswordController.text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset successful!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Passwords do not match"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
