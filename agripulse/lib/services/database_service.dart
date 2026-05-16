import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getUserProfileOrNull() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not logged in");

    return await _supabase
        .from('profiles')
        .select('id, full_name, phone_number, county_id')
        .eq('id', userId)
        .maybeSingle();
  }

  Future<bool> isProfileComplete() async {
    final row = await getUserProfileOrNull();
    if (row == null) return false;

    final fullName = row['full_name']?.toString().trim() ?? '';
    final phone = row['phone_number']?.toString().trim() ?? '';
    final countyRaw = row['county_id'];
    final countyId = countyRaw is num
        ? countyRaw.toInt()
        : int.tryParse(countyRaw?.toString() ?? '');

    return fullName.isNotEmpty && phone.isNotEmpty && countyId != null;
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not logged in");

    final data = await _supabase
        .from('profiles')
        .select('full_name, phone_number, county_id, counties(name, id)')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) {
      throw Exception("Profile not found for this user.");
    }

    return data;
  }

  Future<void> updateUserProfile({
    required String fullName,
    required String phoneNumber,
    required int countyId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not logged in");

    await _supabase
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone_number': phoneNumber,
          'county_id': countyId,
        })
        .eq('id', userId);
  }

  Future<void> upsertUserProfile({
    required String fullName,
    required String phoneNumber,
    required int countyId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    await _supabase.from('profiles').upsert({
      'id': user.id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'county_id': countyId,
    });
  }

  // Selected county current price = latest weekly_prices.price by date.
  Future<double> getLatestPrice(int countyId) async {
    final weeklyPrice = await _latestNumericValue(
      table: 'weekly_prices',
      column: 'price',
      countyId: countyId,
      orderColumn: 'date',
    );
    if (weeklyPrice != null && weeklyPrice > 0) return weeklyPrice;
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> getCounties() async {
    final List<dynamic> rows = await _supabase
        .from('counties')
        .select('id, name')
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> getRecentWeeklyPrices(
    int countyId, {
    int limit = 8,
  }) async {
    final List<dynamic> rows = await _supabase
        .from('weekly_prices')
        .select('date, price')
        .eq('county_id', countyId)
        .order('date', ascending: false)
        .limit(limit);

    final result = List<Map<String, dynamic>>.from(rows);
    result.sort((a, b) {
      final left = DateTime.tryParse(a['date']?.toString() ?? '');
      final right = DateTime.tryParse(b['date']?.toString() ?? '');
      if (left == null && right == null) return 0;
      if (left == null) return -1;
      if (right == null) return 1;
      return left.compareTo(right);
    });
    return result;
  }

  Future<double?> _latestNumericValue({
    required String table,
    required String column,
    required int countyId,
    required String orderColumn,
  }) async {
    try {
      final data = await _supabase
          .from(table)
          .select(column)
          .eq('county_id', countyId)
          .order(orderColumn, ascending: false)
          .limit(1)
          .maybeSingle();

      final value = data?[column];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}
