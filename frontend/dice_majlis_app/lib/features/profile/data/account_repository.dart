import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account.dart';
import '../../../core/network/api_service.dart';
import '../domain/profile_options.dart';

/// Changes to the signed-in account. Each call returns the account as the
/// server now has it. Tests swap in a fake through [accountRepositoryProvider].
abstract class AccountRepository {
  Future<ProfileOptions> profileOptions();

  /// Send only what changes: `displayName`, `avatar`, `country` ('' hides
  /// it) and/or `languages`.
  Future<Account> updateProfile({
    String? displayName,
    String? avatar,
    String? country,
    List<String>? languages,
  });

  /// A guest adds email + password (keeps the same account and Player ID).
  Future<Account> saveAccount({
    required String email,
    required String password,
  });
}

class ApiAccountRepository implements AccountRepository {
  const ApiAccountRepository(this._api);

  final ApiService _api;

  @override
  Future<ProfileOptions> profileOptions() async =>
      ProfileOptions.fromJson(await _api.profileOptions());

  @override
  Future<Account> updateProfile({
    String? displayName,
    String? avatar,
    String? country,
    List<String>? languages,
  }) async => Account.fromJson(
    await _api.updateProfile({
      'display_name': ?displayName,
      'avatar': ?avatar,
      'country': ?country,
      'languages': ?languages,
    }),
  );

  @override
  Future<Account> saveAccount({
    required String email,
    required String password,
  }) async => Account.fromJson(
    await _api.saveAccount(email: email.trim(), password: password),
  );
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => ApiAccountRepository(ref.watch(apiServiceProvider)),
);

/// The profile choices, loaded from the server when the profile screen opens.
final profileOptionsProvider = FutureProvider.autoDispose<ProfileOptions>(
  (ref) => ref.watch(accountRepositoryProvider).profileOptions(),
);
