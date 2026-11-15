import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../data/room_repository.dart';
import '../domain/room_session_controller.dart';

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final code = _codeController.text.trim().toUpperCase();
      final session = await ref.read(roomRepositoryProvider).joinRoom(code);
      if (!mounted) return;
      ref.read(roomSessionProvider.notifier).start(session);
      context.push(AppRoutes.room(session.roomCode));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.joinRoomFailed)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.joinRoomTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MajlisCard(
                    child: TextFormField(
                      controller: _codeController,
                      enabled: !_loading,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.go,
                      onFieldSubmitted: (_) => _join(),
                      decoration: InputDecoration(
                        labelText: l10n.joinRoomCodeLabel,
                        hintText: l10n.joinRoomCodeHint,
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? l10n.joinRoomCodeRequired
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  MajlisButton(
                    label: l10n.joinRoomJoin,
                    icon: Icons.login,
                    loading: _loading,
                    onPressed: _loading ? null : _join,
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
