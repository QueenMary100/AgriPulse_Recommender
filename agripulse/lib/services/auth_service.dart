import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  // Track failed attempts locally for this session
  int _failedLoginAttempts = 0;
  final int _maxAttempts = 3;

  // ---EMAIL OTP METHODS ---

  /// Step 1: Send the 6-digit code to the user's email
  Future<void> sendEmailOTP(String email) async {
    await _supabase.auth.signInWithOtp(
      email: email,
      // If true, new users will be created automatically upon verification
      shouldCreateUser: true,
    );
  }

  /// Step 2: Verify the 6-digit code entered by the user
  Future<void> verifyEmailOTP({
    required String email,
    required String token,
  }) async {
    await _supabase.auth.verifyOTP(
      type: OtpType.email,
      token: token,
      email: email,
    );
  }

  // --- SIGN UP (Manual with Profile) ---

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required int countyId,
  }) async {
    final normalizedPhone = _normalizePhone(phoneNumber);
    final AuthResponse res = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    final User? user = res.user;

    if (user != null) {
      try {
        await _supabase.from('profiles').insert({
          'id': user.id,
          'full_name': fullName,
          'phone_number': normalizedPhone,
          'county_id': countyId,
          'email': email.toLowerCase(),
        });
      } on PostgrestException catch (e) {
        if (_isMissingEmailColumnError(e)) {
          await _supabase.from('profiles').insert({
            'id': user.id,
            'full_name': fullName,
            'phone_number': normalizedPhone,
            'county_id': countyId,
          });
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> logIn(String identifier, String password) async {
    try {
      if (_failedLoginAttempts >= _maxAttempts) {
        throw AuthException(
          "Too many failed attempts. Please reset your password.",
          statusCode: '429',
        );
      }

      final email = await _resolveEmailFromIdentifier(identifier);
      await _supabase.auth.signInWithPassword(email: email, password: password);
      await _syncProfileEmailFromCurrentUser();
      _failedLoginAttempts = 0;
    } on AuthException {
      _failedLoginAttempts++;
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<void> updatePassword(String newPassword) async {
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> logOut() async {
    await _supabase.auth.signOut();
  }

  Future<String> _resolveEmailFromIdentifier(String identifier) async {
    final value = identifier.trim();
    if (value.contains('@')) return value.toLowerCase();

    final normalized = _normalizePhone(value);
    final candidates = {
      value,
      normalized,
      _denormalizeToLeadingZero(normalized),
      _denormalizeTo254(normalized),
    }.where((v) => v.isNotEmpty).toList();

    for (final phone in candidates) {
      try {
        final row = await _supabase
            .from('profiles')
            .select('email')
            .eq('phone_number', phone)
            .maybeSingle();

        final email = row?['email']?.toString().trim();
        if (email != null && email.isNotEmpty) {
          return email.toLowerCase();
        }
      } on PostgrestException catch (e) {
        if (_isMissingEmailColumnError(e)) {
          throw AuthException(
            'Phone login setup is incomplete. Run the profiles email migration first.',
          );
        }
        rethrow;
      }
    }

    throw AuthException(
      'No account found for this phone number. Use your email or update profile.',
    );
  }

  Future<void> _syncProfileEmailFromCurrentUser() async {
    final user = _supabase.auth.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) return;

    try {
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'email': email,
      });
    } on PostgrestException catch (e) {
      if (_isMissingEmailColumnError(e)) return;
      rethrow;
    }
  }

  bool _isMissingEmailColumnError(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('column') && msg.contains('email') && msg.contains('does not exist');
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\s+'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('0') && digits.length >= 10) {
      return '+254${digits.substring(1)}';
    }
    if (digits.startsWith('254') && digits.length >= 12) {
      return '+$digits';
    }
    return digits;
  }

  String _denormalizeToLeadingZero(String phone) {
    if (phone.startsWith('+254') && phone.length >= 13) {
      return '0${phone.substring(4)}';
    }
    return phone;
  }

  String _denormalizeTo254(String phone) {
    if (phone.startsWith('+254') && phone.length >= 13) {
      return phone.substring(1);
    }
    return phone;
  }

  User? get currentUser => _supabase.auth.currentUser;
  int get failedAttempts => _failedLoginAttempts;
}
