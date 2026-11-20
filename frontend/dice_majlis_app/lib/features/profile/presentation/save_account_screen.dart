import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../auth/presentation/email_screen.dart';
import '../data/account_repository.dart';

/// A guest adds email + password: same account, same Player ID, and now it
/// can be signed into again on any phone.
class SaveAccountScreen extends ConsumerStatefulWidget {
  const SaveAccountScreen({super.key});

  @override
  ConsumerState<SaveAccountScreen> createState() => _SaveAccountScreenState();
}

class _SaveAccountScreenState extends ConsumerState<SaveAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      final account = await ref
          .read(accountRepositoryProvider)
          .saveAccount(email: _email.text, password: _password.text);
      ref.read(authControllerProvider.notifier).accountChanged(account);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.saveAccountDone)));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.saveAccountTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.saveAccountIntro,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.majlis.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      MajlisCard(
                        child: Column(
                          children: [
                            EmailField(controller: _email),
                            const SizedBox(height: 14),
                            PasswordField(
                              controller: _password,
                              label: l10n.passwordField,
                              isNew: true,
                              onSubmitted: (_) => _save(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      MajlisButton(
                        label: l10n.saveAccountButton,
                        icon: Icons.verified_user_outlined,
                        loading: _loading,
                        onPressed: _loading ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
