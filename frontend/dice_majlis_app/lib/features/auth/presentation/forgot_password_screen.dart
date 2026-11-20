import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_api.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import 'email_screen.dart';

/// Forgotten password, in two steps: the email gets a 6-digit code, then the
/// code + a new password sign the player in (the router moves them on).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
  }

  Future<void> _sendCode() async {
    if (!looksLikeEmail(_email.text)) {
      _formKey.currentState!.validate();
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authApiProvider).requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _codeSent = true);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: _email.text,
            code: _code.text,
            newPassword: _password.text,
          );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: context.majlis.textMuted,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.forgotTitle)),
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
                        _codeSent
                            ? l10n.forgotCodeSent(_email.text.trim())
                            : l10n.forgotIntro,
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                      const SizedBox(height: 20),
                      MajlisCard(
                        child: Column(
                          children: [
                            EmailField(controller: _email, enabled: !_codeSent),
                            if (_codeSent) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _code,
                                keyboardType: TextInputType.number,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode,
                                ],
                                maxLength: 6,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: l10n.forgotCode,
                                  prefixIcon: const Icon(Icons.pin_outlined),
                                ),
                                validator: (value) =>
                                    RegExp(r'^\d{6}$').hasMatch(value ?? '')
                                    ? null
                                    : l10n.forgotCodeInvalid,
                              ),
                              const SizedBox(height: 6),
                              PasswordField(
                                controller: _password,
                                label: l10n.newPasswordField,
                                isNew: true,
                                onSubmitted: (_) => _changePassword(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      MajlisButton(
                        label: _codeSent ? l10n.forgotChange : l10n.forgotSend,
                        icon: _codeSent ? Icons.lock_reset : Icons.send,
                        loading: _loading,
                        onPressed: _loading
                            ? null
                            : (_codeSent ? _changePassword : _sendCode),
                      ),
                      if (_codeSent) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading ? null : _sendCode,
                          child: Text(l10n.forgotResend),
                        ),
                      ],
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
