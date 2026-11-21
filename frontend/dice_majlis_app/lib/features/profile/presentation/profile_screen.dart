import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/account.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../../shared/widgets/player_avatar.dart';
import '../../stats/presentation/stats_card.dart';
import '../data/account_repository.dart';
import '../domain/profile_options.dart';

/// "🇧🇭 Bahrain" for a country code, in the app's language when the picker
/// has it.
String countryLabel(BuildContext context, String code) {
  final country = CountryParser.tryParseCountryCode(code);
  if (country == null) return code;
  final name = country.getTranslatedName(context) ?? country.name;
  return '${country.flagEmoji} $name';
}

/// Your own profile: see your Player ID and level, change your name, avatar,
/// country and languages. Every change is saved on the server straight away
/// (the name when you press Save).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name;
  String? _nameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ref.read(accountProvider)?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Sends one change; the server answers with the whole account.
  Future<bool> _save({
    String? displayName,
    String? avatar,
    String? country,
    List<String>? languages,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final account = await ref
          .read(accountRepositoryProvider)
          .updateProfile(
            displayName: displayName,
            avatar: avatar,
            country: country,
            languages: languages,
          );
      ref.read(authControllerProvider.notifier).accountChanged(account);
      return true;
    } on ApiException catch (error) {
      final nameCode = error.fieldError('display_name');
      if (nameCode != null && mounted) {
        setState(() => _nameError = _nameErrorText(l10n, nameCode));
      } else {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _nameErrorText(AppLocalizations l10n, String code) {
    if (code == 'name_length') {
      final options = ref.read(profileOptionsProvider).value;
      if (options != null) {
        return l10n.nameLength(options.nameMinLength, options.nameMaxLength);
      }
    }
    return l10n.fieldErrorText(code) ?? l10n.errorInvalidInput;
  }

  Future<void> _saveName() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _nameError = null);
    if (await _save(displayName: _name.text)) {
      _name.text = ref.read(accountProvider)?.displayName ?? _name.text;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    }
  }

  void _chooseCountry() {
    final majlis = context.majlis;
    showCountryPicker(
      context: context,
      onSelect: (country) => _save(country: country.countryCode),
      countryListTheme: CountryListThemeData(
        backgroundColor: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        bottomSheetHeight: MediaQuery.sizeOf(context).height * 0.75,
        textStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        searchTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        inputDecoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: majlis.textMuted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    if (account == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final options = ref.watch(profileOptionsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _Header(account: account),
                  const SizedBox(height: 16),
                  _LevelCard(account: account),
                  const SizedBox(height: 16),
                  const StatsCard(),
                  const SizedBox(height: 16),
                  MajlisCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      key: const Key('profile-customise'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Icon(Icons.palette_outlined, color: majlis.gold),
                      title: Text(l10n.profileCustomise),
                      subtitle: Text(l10n.profileCustomiseHint),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.customise),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MajlisCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      key: const Key('profile-achievements'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Icon(
                        Icons.emoji_events_outlined,
                        color: majlis.gold,
                      ),
                      title: Text(l10n.profileAchievements),
                      subtitle: Text(l10n.profileAchievementsHint),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.achievements),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MajlisCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.profileName,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _name,
                          maxLength: options.value?.nameMaxLength,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveName(),
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          decoration: InputDecoration(errorText: _nameError),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton.tonal(
                            onPressed: _saving ? null : _saveName,
                            child: Text(l10n.profileNameSave),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  options.when(
                    data: (options) => _Choices(
                      account: account,
                      options: options,
                      enabled: !_saving,
                      onAvatar: (avatar) => _save(avatar: avatar),
                      onLanguages: (languages) => _save(languages: languages),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => MajlisCard(
                      child: Column(
                        children: [
                          Text(l10n.profileOptionsFailed),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(profileOptionsProvider),
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MajlisCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.profileCountry,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                account.country == null
                                    ? l10n.profileCountryNone
                                    : countryLabel(context, account.country!),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: account.country == null
                                      ? majlis.textMuted
                                      : null,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _chooseCountry,
                              child: Text(l10n.profileCountryChoose),
                            ),
                          ],
                        ),
                        if (account.country != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(country: ''),
                              child: Text(l10n.profileCountryHide),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return MajlisCard(
      child: Column(
        children: [
          PlayerAvatar(
            avatar: account.avatar,
            radius: 40,
            frame: account.frame,
          ),
          const SizedBox(height: 12),
          Text(
            account.displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          if (account.isGuest)
            Text(
              l10n.homeGuestTag,
              style: theme.textTheme.labelMedium?.copyWith(
                color: majlis.textMuted,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.homePlayerId(formatPlayerId(account.playerId)),
                style: theme.textTheme.bodyLarge?.copyWith(color: majlis.gold),
              ),
              IconButton(
                tooltip: l10n.homeCopyPlayerId,
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${account.playerId}'),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text(l10n.homePlayerIdCopied)),
                    );
                },
              ),
            ],
          ),
          if (account.languages.isNotEmpty)
            Wrap(
              spacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final code in account.languages)
                  Chip(
                    label: Text(l10n.spokenLanguageName(code)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return MajlisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech, color: majlis.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.homeLevel(account.level),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                l10n.profileLevelXp(account.xp, account.nextLevelXp),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: majlis.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: account.levelProgress,
              minHeight: 8,
              color: majlis.gold,
              backgroundColor: majlis.glassBorder,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.profileXpHow,
            style: theme.textTheme.bodySmall?.copyWith(color: majlis.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Avatar and languages: the choices come from the server.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.account,
    required this.options,
    required this.enabled,
    required this.onAvatar,
    required this.onLanguages,
  });

  final Account account;
  final ProfileOptions options;
  final bool enabled;
  final ValueChanged<String> onAvatar;
  final ValueChanged<List<String>> onLanguages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: context.majlis.textMuted,
    );
    final chosen = account.languages;
    final full = chosen.length >= options.maxLanguages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MajlisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.profileAvatar, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final avatar in options.avatars)
                    Semantics(
                      button: true,
                      selected: avatar == account.avatar,
                      label: avatar,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: enabled && avatar != account.avatar
                            ? () => onAvatar(avatar)
                            : null,
                        child: PlayerAvatar(
                          avatar: avatar,
                          radius: 24,
                          selected: avatar == account.avatar,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(l10n.profileAvatarPhotoSoon, style: muted),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MajlisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.profileLanguages, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.profileLanguagesHint(options.maxLanguages),
                style: muted,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final code in options.languages)
                    FilterChip(
                      label: Text(l10n.spokenLanguageName(code)),
                      selected: chosen.contains(code),
                      onSelected: !enabled || (full && !chosen.contains(code))
                          ? null
                          : (on) => onLanguages(
                              on
                                  ? [...chosen, code]
                                  : [
                                      for (final c in chosen)
                                        if (c != code) c,
                                    ],
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
