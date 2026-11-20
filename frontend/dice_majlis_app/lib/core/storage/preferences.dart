import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small device settings (theme, later language), loaded once in `main()`.
///
/// Null when there is no storage (widget tests, or the platform refused):
/// settings then last until the app closes.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);
