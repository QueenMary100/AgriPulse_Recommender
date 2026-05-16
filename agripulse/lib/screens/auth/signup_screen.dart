import 'package:flutter/material.dart';
import '../../widgets/custom_scaffold.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  List<Map<String, dynamic>> _counties = [];
  int? _selectedCountyId;
  bool _isLoading = false;
  bool _isLoadingCounties = true;
  bool _isPasswordVisible = false; // Toggle state for password visibility

  @override
  void initState() {
    super.initState();
    _loadCounties();
  }

  Future<void> _loadCounties() async {
    try {
      final rows = await _dbService.getCounties();
      if (!mounted) return;
      setState(() {
        _counties = rows;
        if (_counties.isNotEmpty) {
          _selectedCountyId = (_counties.first['id'] as num).toInt();
        }
        _isLoadingCounties = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingCounties = false);
    }
  }

  Widget _inputField({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(icon, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: isPassword ? !_isPasswordVisible : false,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                suffixIcon: isPassword
                    ? IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationDropdown() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: _isLoadingCounties
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Loading counties..."),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedCountyId,
                      isExpanded: true,
                      hint: const Text("Select county"),
                      items: _counties.map((county) {
                        return DropdownMenuItem<int>(
                          value: (county['id'] as num).toInt(),
                          child: Text(county['name']?.toString() ?? 'County'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCountyId = value;
                        });
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _phoneField() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.phone, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: "Phone Number (07..., +254..., or 254...)",
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignup() async {
    if (_selectedCountyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your county.")),
      );
      return;
    }

    final normalizedPhone = _normalizeKenyanPhone(_phoneController.text);
    if (normalizedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Enter a valid Kenyan phone number (07..., +254..., or 254...).",
          ),
        ),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Passwords do not match!")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        fullName: _nameController.text.trim(),
        phoneNumber: normalizedPhone,
        countyId: _selectedCountyId!,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Signup Failed: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _normalizeKenyanPhone(String input) {
    final value = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (value.isEmpty) return null;

    String digits = value;
    if (digits.startsWith('+')) {
      digits = digits.substring(1);
    }

    if (digits.startsWith('0') && digits.length == 10) {
      digits = '254${digits.substring(1)}';
    }

    if (digits.startsWith('254') && digits.length == 12) {
      return '+$digits';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showAppBar: false,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 60),
              Image.asset('assets/images/logo.png', height: 80),
              const SizedBox(height: 10),
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _inputField(
                      icon: Icons.person,
                      hint: "Full Name",
                      controller: _nameController,
                    ),
                    const SizedBox(height: 15),
                    _inputField(
                      icon: Icons.email,
                      hint: "Email Address",
                      controller: _emailController,
                    ),
                    const SizedBox(height: 15),
                    _locationDropdown(),
                    const SizedBox(height: 15),
                    _phoneField(),
                    const SizedBox(height: 15),
                    _inputField(
                      icon: Icons.lock,
                      hint: "Create Password",
                      isPassword: true,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 15),
                    _inputField(
                      icon: Icons.lock,
                      hint: "Confirm Password",
                      isPassword: true,
                      controller: _confirmPasswordController,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "SIGN UP",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text.rich(
                  TextSpan(
                    text: "Already have an account? ",
                    children: [
                      TextSpan(
                        text: "Login",
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import '../../widgets/custom_scaffold.dart';
// import '../../services/auth_service.dart'; // Import your service

// class SignupScreen extends StatefulWidget {
//   const SignupScreen({super.key});

//   @override
//   State<SignupScreen> createState() => _SignupScreenState();
// }

// class _SignupScreenState extends State<SignupScreen> {
//   // 1. Controllers and Services
//   final AuthService _authService = AuthService();
//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _phoneController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();
//   final TextEditingController _confirmPasswordController =
//       TextEditingController();

//   String selectedLocation = "Nairobi";
//   bool _isLoading = false;

//   // Map locations to IDs matching your PostgreSQL 'counties' table
//   final Map<String, int> locationIds = {
//     "Nairobi": 1,
//     "Eldoret": 2,
//     "Kisumu": 3,
//     "Mombasa": 4,
//     "Kiambu": 5,
//     "Kakamega": 6,
//     "Bungoma": 7,
//     "Busia": 8,
//     "Vihiga": 9,
//   };

//   // 🔹 Updated Input Field with Controller
//   Widget _inputField({
//     required IconData icon,
//     required String hint,
//     required TextEditingController controller,
//     bool isPassword = false,
//   }) {
//     return Container(
//       height: 60,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
//       ),
//       child: Row(
//         children: [
//           const SizedBox(width: 10),
//           Icon(icon, color: Colors.green),
//           const SizedBox(width: 10),
//           Expanded(
//             child: TextField(
//               controller: controller,
//               obscureText: isPassword,
//               decoration: InputDecoration(
//                 hintText: hint,
//                 border: InputBorder.none,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // 📍 Location Dropdown
//   Widget _locationDropdown() {
//     return Container(
//       height: 60,
//       padding: const EdgeInsets.symmetric(horizontal: 10),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
//       ),
//       child: Row(
//         children: [
//           const Icon(Icons.location_on, color: Colors.green),
//           const SizedBox(width: 10),
//           Expanded(
//             child: DropdownButtonHideUnderline(
//               child: DropdownButton<String>(
//                 value: selectedLocation,
//                 isExpanded: true,
//                 items: locationIds.keys.map((loc) {
//                   return DropdownMenuItem(value: loc, child: Text(loc));
//                 }).toList(),
//                 onChanged: (value) {
//                   setState(() {
//                     selectedLocation = value!;
//                   });
//                 },
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // 📱 Phone Field with Controller
//   Widget _phoneField() {
//     return Container(
//       height: 60,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
//       ),
//       child: Row(
//         children: [
//           const SizedBox(width: 10),
//           const Icon(Icons.phone, color: Colors.green),
//           const SizedBox(width: 10),
//           const Text("+254", style: TextStyle(fontWeight: FontWeight.bold)),
//           const SizedBox(width: 10),
//           Expanded(
//             child: TextField(
//               controller: _phoneController,
//               keyboardType: TextInputType.phone,
//               decoration: const InputDecoration(
//                 hintText: "Phone Number",
//                 border: InputBorder.none,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // 🚀 Updated SIGN UP Method
//   Future<void> _handleSignup() async {
//     if (_passwordController.text != _confirmPasswordController.text) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text("Passwords do not match!")));
//       return;
//     }

//     setState(() => _isLoading = true);

//     try {
//       await _authService.signUp(
//         email: _emailController.text.trim(),
//         password: _passwordController.text.trim(),
//         fullName: _nameController.text.trim(),
//         phoneNumber: "+254${_phoneController.text.trim()}",
//         countyId: locationIds[selectedLocation]!,
//       );

//       if (mounted) {
//         Navigator.pushReplacementNamed(context, '/main');
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text("Signup Failed: ${e.toString()}")),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return CustomScaffold(
//       showAppBar: false,
//       child: SafeArea(
//         child: SingleChildScrollView(
//           child: Column(
//             children: [
//               const SizedBox(height: 60),
//               Image.asset('assets/images/logo.png', height: 80),
//               const SizedBox(height: 10),
//               const Text(
//                 "Create Account",
//                 style: TextStyle(
//                   fontSize: 24,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.green,
//                 ),
//               ),
//               const SizedBox(height: 40),
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 20),
//                 child: Column(
//                   children: [
//                     _inputField(
//                       icon: Icons.person,
//                       hint: "Full Name",
//                       controller: _nameController,
//                     ),
//                     const SizedBox(height: 15),
//                     _inputField(
//                       icon: Icons.email,
//                       hint: "Email Address",
//                       controller: _emailController,
//                     ),
//                     const SizedBox(height: 15),
//                     _locationDropdown(),
//                     const SizedBox(height: 15),
//                     _phoneField(),
//                     const SizedBox(height: 15),
//                     _inputField(
//                       icon: Icons.lock,
//                       hint: "Create Password",
//                       isPassword: true,
//                       controller: _passwordController,
//                     ),
//                     const SizedBox(height: 15),
//                     _inputField(
//                       icon: Icons.lock,
//                       hint: "Confirm Password",
//                       isPassword: true,
//                       controller: _confirmPasswordController,
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 25),
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 20),
//                 child: SizedBox(
//                   width: double.infinity,
//                   height: 55,
//                   child: ElevatedButton(
//                     onPressed: _isLoading ? null : _handleSignup,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.green,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       elevation: 5,
//                     ),
//                     child: _isLoading
//                         ? const CircularProgressIndicator(color: Colors.white)
//                         : const Text(
//                             "SIGN UP",
//                             style: TextStyle(
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                               color: Colors.white,
//                             ),
//                           ),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 40),
//               GestureDetector(
//                 onTap: () => Navigator.pop(context),
//                 child: const Text.rich(
//                   TextSpan(
//                     text: "Already have an account? ",
//                     children: [
//                       TextSpan(
//                         text: "Login",
//                         style: TextStyle(
//                           color: Colors.orange,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 40),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
