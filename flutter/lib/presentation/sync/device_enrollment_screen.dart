import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';

class DeviceEnrollmentScreen extends StatefulWidget {
  final IrnReferential referential;

  const DeviceEnrollmentScreen({required this.referential, super.key});

  @override
  State<DeviceEnrollmentScreen> createState() => _DeviceEnrollmentScreenState();
}

class _DeviceEnrollmentScreenState extends State<DeviceEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  late final TextEditingController _tenantIdController;
  late final TextEditingController _codeController;
  late final TextEditingController _deviceNameController;
  bool _working = false;
  OpenIrnApiConnectionResult? _connectionResult;
  OpenIrnApiEnrollmentResult? _enrollmentResult;

  @override
  void initState() {
    super.initState();
    _tenantIdController = TextEditingController(
      text: SyncConfiguration.defaultTenantId,
    );
    _codeController = TextEditingController();
    _deviceNameController = TextEditingController(text: _defaultDeviceName());
  }

  @override
  void dispose() {
    _tenantIdController.dispose();
    _codeController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _testServer() async {
    setState(() {
      _working = true;
      _connectionResult = null;
      _enrollmentResult = null;
    });
    final result = await _apiClient.testConnection(
      baseUrl: SyncConfiguration.fixedApiBaseUrl,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _working = false;
      _connectionResult = result;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.title)));
  }

  Future<void> _consumeEnrollment() async {
    if (_formKey.currentState?.validate() != true || _working) {
      return;
    }

    setState(() {
      _working = true;
      _connectionResult = null;
      _enrollmentResult = null;
    });

    final result = await _apiClient.consumeDeviceEnrollment(
      baseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: _tenantIdController.text,
      code: _codeController.text,
      deviceName: _deviceNameController.text,
      platform: _platformName(),
    );

    if (!mounted) {
      return;
    }

    if (!result.isAccepted) {
      setState(() {
        _working = false;
        _enrollmentResult = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.title} — ${result.message}')),
      );
      return;
    }

    final token = result.apiToken.trim();
    final deviceId = result.device?.deviceId.trim() ?? '';
    if (token.isEmpty || deviceId.isEmpty) {
      setState(() {
        _working = false;
        _enrollmentResult = OpenIrnApiEnrollmentResult(
          status: OpenIrnApiEnrollmentStatus.rejected,
          url: result.url,
          statusCode: result.statusCode,
          title: 'Réponse serveur incomplète',
          message:
              'Le serveur a accepté le code, mais n’a pas retourné de jeton terminal complet.',
          tenantId: result.tenantId,
          enrollmentId: result.enrollmentId,
          code: '',
          expiresAt: null,
          expiresInMinutes: 0,
          qrPayloadText: '',
          apiToken: '',
          device: result.device,
          responseBody: result.responseBody,
        );
      });
      return;
    }

    final configuration = SyncConfiguration.empty(deviceId: deviceId).copyWith(
      tenantId: result.tenantId,
      deviceId: deviceId,
      enabled: true,
      apiToken: token,
    );
    final saved = await _configurationRepository.saveConfiguration(
      configuration,
    );

    AppSyncCoordinator.instance.start(referential: widget.referential);
    await AppSyncCoordinator.instance.pullLatestNow();

    if (!mounted) {
      return;
    }

    setState(() {
      _working = false;
      _enrollmentResult = result;
      _tenantIdController.text = saved.tenantId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Terminal autorisé. Synchronisation initiale lancée.'),
      ),
    );
    Navigator.of(context).pop(true);
  }

  void _pasteQrPayloadText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final tenantId = decoded['tenantId']?.toString().trim() ?? '';
        final code = decoded['code']?.toString().trim() ?? '';
        if (tenantId.isNotEmpty) {
          _tenantIdController.text = tenantId;
        }
        if (code.isNotEmpty) {
          _codeController.text = code;
        }
      }
    } on FormatException {
      _codeController.text = trimmed;
    }
  }

  Future<void> _openPastePayloadDialog() async {
    final controller = TextEditingController();
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coller une invitation'),
        content: TextField(
          controller: controller,
          autofocus: shouldAutofocusTextField(context),
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Code ou payload JSON',
            hintText: '{"type":"openirn.deviceEnrollment", ...}',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Utiliser'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (payload == null || payload.trim().isEmpty || !mounted) {
      return;
    }
    setState(() {
      _pasteQrPayloadText(payload);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 760;

    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Autoriser ce terminal'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: isNarrow
                      ? _IntroColumn(theme: theme)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.phonelink_lock_outlined, size: 44),
                            const SizedBox(width: 16),
                            Expanded(child: _IntroColumn(theme: theme)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Code d’appairage',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Crée d’abord une invitation depuis un terminal déjà autorisé : Administration → Terminaux autorisés.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _deviceNameController,
                          autofocus: shouldAutofocusTextField(context),
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Nom de ce terminal',
                            hintText: 'Ex. iPhone Michel, PC Salle 1...',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.devices_other_outlined),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Indique un nom reconnaissable pour ce terminal.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.text,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9\-\s]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Code d’appairage',
                            hintText: '123-456 ou ABCD-EFGH',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.password_outlined),
                          ),
                          onFieldSubmitted: (_) => _consumeEnrollment(),
                          validator: (value) {
                            final normalized = (value ?? '')
                                .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                                .trim();
                            if (normalized.length < 8) {
                              return 'Saisis le code d’appairage complet.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Paramètres avancés'),
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          children: [
                            TextFormField(
                              controller: _tenantIdController,
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Tenant serveur',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.account_tree_outlined),
                              ),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Le tenant serveur est obligatoire.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _working ? null : _testServer,
                              icon: const Icon(Icons.wifi_tethering_outlined),
                              label: const Text('Tester le serveur'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _working
                                  ? null
                                  : _openPastePayloadDialog,
                              icon: const Icon(Icons.content_paste_go_outlined),
                              label: const Text('Coller invitation'),
                            ),
                            FilledButton.icon(
                              onPressed: _working ? null : _consumeEnrollment,
                              icon: _working
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.verified_user_outlined),
                              label: Text(
                                _working
                                    ? 'Autorisation...'
                                    : 'Autoriser ce terminal',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_connectionResult != null)
                _ResultCard(
                  icon: _connectionResult!.isReachable
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  title: _connectionResult!.title,
                  message: _connectionResult!.message,
                  positive: _connectionResult!.isReachable,
                ),
              if (_enrollmentResult != null)
                _ResultCard(
                  icon: _enrollmentResult!.isAccepted
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  title: _enrollmentResult!.title,
                  message: _enrollmentResult!.message,
                  positive: _enrollmentResult!.isAccepted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _defaultDeviceName() {
    return 'Terminal ${_platformLabel()}';
  }

  String _platformLabel() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}

class _IntroColumn extends StatelessWidget {
  final ThemeData theme;

  const _IntroColumn({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appairage sécurisé', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Ce terminal va recevoir son propre jeton serveur. Le bearer global n’est pas saisi par l’utilisateur.',
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('Code à usage unique')),
            Chip(label: Text('Expiration courte')),
            Chip(label: Text('Révocation par terminal')),
          ],
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool positive;

  const _ResultCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: positive
          ? colorScheme.primaryContainer
          : colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }
}
