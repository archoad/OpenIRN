import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/services/app_session_manager.dart';
import 'responsive_autofocus.dart';
import 'responsive_dialog.dart';

class ChangeAccessCodeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool elevatedButton;

  const ChangeAccessCodeCard({
    this.title = 'Changement de code',
    this.subtitle =
        'Changer votre code d’accès personnel. Le code actuel est demandé avant l’enregistrement du nouveau code.',
    this.buttonLabel = 'Changer le code',
    this.elevatedButton = false,
    super.key,
  });

  @override
  State<ChangeAccessCodeCard> createState() => _ChangeAccessCodeCardState();
}

class _ChangeAccessCodeCardState extends State<ChangeAccessCodeCard> {
  final _apiClient = const OpenIrnApiClient();
  final _configurationRepository = const LocalSyncConfigurationRepository();
  bool _isUpdating = false;

  Future<void> _changeCode() async {
    final session = AppSessionManager.instance;
    final activeUser = session.activeUser;
    if (!session.hasActiveSession || activeUser == null) {
      _showMessage(
        'Veuillez ouvrir une session avant de changer votre code d’accès.',
      );
      return;
    }

    final form = await showDialog<_AccessCodeChangeFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccessCodeChangeDialog(userLabel: activeUser.displayName),
    );
    if (form == null || !mounted) {
      return;
    }

    setState(() => _isUpdating = true);
    try {
      final configuration = await _configurationRepository.loadConfiguration();
      final result = await _apiClient.changeOwnPin(
        baseUrl: configuration.apiBaseUrl,
        apiToken: session.apiToken,
        currentPin: form.currentCode,
        newPin: form.newCode,
      );
      if (!mounted) {
        return;
      }
      _showMessage('${result.title} — ${result.message}');
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.password_outlined, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(widget.subtitle),
            ],
          ),
        ),
      ],
    );

    final button = widget.elevatedButton
        ? FilledButton.icon(
            onPressed: _isUpdating ? null : _changeCode,
            icon: _isUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset_outlined),
            label: Text(_isUpdating ? 'Mise à jour...' : widget.buttonLabel),
          )
        : OutlinedButton.icon(
            onPressed: _isUpdating ? null : _changeCode,
            icon: _isUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset_outlined),
            label: Text(_isUpdating ? 'Mise à jour...' : widget.buttonLabel),
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: 14),
                  button,
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  button,
                ],
              ),
      ),
    );
  }
}

class _AccessCodeChangeFormResult {
  final String currentCode;
  final String newCode;

  const _AccessCodeChangeFormResult({
    required this.currentCode,
    required this.newCode,
  });
}

class _AccessCodeChangeDialog extends StatefulWidget {
  final String userLabel;

  const _AccessCodeChangeDialog({required this.userLabel});

  @override
  State<_AccessCodeChangeDialog> createState() =>
      _AccessCodeChangeDialogState();
}

class _AccessCodeChangeDialogState extends State<_AccessCodeChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentCodeController = TextEditingController();
  final _newCodeController = TextEditingController();
  final _confirmCodeController = TextEditingController();

  @override
  void dispose() {
    _currentCodeController.dispose();
    _newCodeController.dispose();
    _confirmCodeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _AccessCodeChangeFormResult(
        currentCode: _currentCodeController.text.trim(),
        newCode: _newCodeController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLabel = widget.userLabel.trim();
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Changer le code d’accès'),
      content: ResponsiveDialogContent(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (userLabel.isNotEmpty) ...[
                Text('Utilisateur : $userLabel'),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _currentCodeController,
                autofocus: shouldAutofocusTextField(context),
                obscureText: true,
                keyboardType: safeKeyboardType(context, TextInputType.number),
                decoration: const InputDecoration(
                  labelText: 'Code actuel',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) {
                  if ((value?.trim() ?? '').isEmpty) {
                    return 'Veuillez saisir le code actuel.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCodeController,
                obscureText: true,
                keyboardType: safeKeyboardType(context, TextInputType.number),
                decoration: const InputDecoration(
                  labelText: 'Nouveau code',
                  helperText: '4 à 32 caractères.',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
                validator: (value) {
                  final code = value?.trim() ?? '';
                  if (code.length < 4) {
                    return 'Le code doit contenir au moins 4 caractères.';
                  }
                  if (code.length > 32) {
                    return 'Le code ne doit pas dépasser 32 caractères.';
                  }
                  if (code == _currentCodeController.text.trim()) {
                    return 'Le nouveau code doit être différent du code actuel.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCodeController,
                obscureText: true,
                keyboardType: safeKeyboardType(context, TextInputType.number),
                decoration: const InputDecoration(
                  labelText: 'Confirmer le nouveau code',
                  prefixIcon: Icon(Icons.done_all_outlined),
                ),
                validator: (value) {
                  if ((value?.trim() ?? '') != _newCodeController.text.trim()) {
                    return 'Les deux saisies ne correspondent pas.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.lock_reset_outlined),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
