import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';

/// A light check before asking the server (which checks properly).
bool looksLikeEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

/// Sign in with email + password, or create an account with them. Signing in
/// needs no navigation here: the router moves a signed-in player on.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final auth = ref.read(authControllerProvider.notifier);
    setState(() => _loading = true);
    try {
      if (_creating) {
        await auth.createAccount(_email.text, _password.text);
      } else {
        await auth.signInWithEmail(_email.text, _password.text);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.emailTitle)),
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
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(l10n.emailModeSignIn),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(l10n.emailModeCreate),
                          ),
                        ],
                        selected: {_creating},
                        onSelectionChanged: (choice) =>
                            setState(() => _creating = choice.single),
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
                              isNew: _creating,
                              onSubmitted: (_) => _submit(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      MajlisButton(
                        label: _creating ? l10n.emailCreate : l10n.emailSignIn,
                        icon: _creating ? Icons.person_add_alt : Icons.login,
                        loading: _loading,
                        onPressed: _loading ? null : _submit,
                      ),
                      if (!_creating) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              context.push(AppRoutes.forgotPassword),
                          child: Text(l10n.emailForgot),
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

/// Email input with a light format check.
class EmailField extends StatelessWidget {
  const EmailField({super.key, required this.controller, this.enabled = true});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: l10n.emailField,
        prefixIcon: const Icon(Icons.mail_outline),
      ),
      validator: (value) =>
          looksLikeEmail(value ?? '') ? null : l10n.emailFieldInvalid,
    );
  }
}

/// Password input with show/hide. [isNew] adds the strength hint (the server
/// decides what's strong enough).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.isNew = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool isNew;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: TextInputAction.done,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.isNew ? l10n.passwordHint : null,
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _visible ? l10n.passwordHide : l10n.passwordShow,
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
      validator: (value) =>
          (value ?? '').isEmpty ? l10n.passwordFieldEmpty : null,
    );
  }
}
