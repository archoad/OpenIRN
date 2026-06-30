import 'package:flutter/material.dart';

import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../campaigns/campaign_management_screen.dart';
import '../common/openirn_app_bar.dart';
import '../users/user_list_screen.dart';
import 'authorized_devices_screen.dart';
import 'campaign_history_screen.dart';
import 'official_referential_screen.dart';
import 'security_audit_screen.dart';
import 'server_maintenance_screen.dart';
import 'server_sessions_screen.dart';

class AdministrationScreen extends StatelessWidget {
  final IrnReferential referential;
  final AppUser activeUser;

  const AdministrationScreen({
    required this.referential,
    required this.activeUser,
    super.key,
  });

  Future<void> _openCampaignManagement(BuildContext context) async {
    if (!_hasServerReferential) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Installe ou recharge le référentiel officiel aDRI avant de gérer les campagnes.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CampaignManagementScreen(
          referential: referential,
          activeUser: activeUser,
        ),
      ),
    );
  }

  bool get _hasServerReferential =>
      referential.pillars.isNotEmpty || referential.criteria.isNotEmpty;

  Future<void> _openUsersAdministration(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const UserListScreen()));
  }

  Future<void> _openServerMaintenance(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerMaintenanceScreen(activeUser: activeUser),
      ),
    );
  }

  Future<void> _openCampaignHistory(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CampaignHistoryScreen(activeUser: activeUser),
      ),
    );
  }

  Future<void> _openOfficialReferential(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfficialReferentialScreen(activeUser: activeUser),
      ),
    );
  }

  Future<void> _openSecurityAudit(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecurityAuditScreen(activeUser: activeUser),
      ),
    );
  }

  Future<void> _openServerSessions(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerSessionsScreen(activeUser: activeUser),
      ),
    );
  }

  Future<void> _openAuthorizedDevices(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthorizedDevicesScreen(activeUser: activeUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedName = activeUser.fullName.isNotEmpty
        ? activeUser.fullName
        : activeUser.email.isNotEmpty
        ? activeUser.email
        : activeUser.id;

    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Administration'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 38),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Session administration',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$authenticatedName — ${activeUser.role.label}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Gérer les campagnes',
                subtitle: _hasServerReferential
                    ? 'Créer une campagne, supprimer une campagne existante et nettoyer le journal associé.'
                    : 'Référentiel serveur absent : installe d’abord le référentiel officiel aDRI.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openCampaignManagement(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.people_alt_outlined,
                title: 'Utilisateurs',
                subtitle:
                    'Créer, modifier ou supprimer les utilisateurs depuis la base centrale serveur.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openUsersAdministration(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.devices_other_outlined,
                title: 'Terminaux autorisés',
                subtitle:
                    'Créer une invitation, consulter les terminaux enrôlés, renommer ou révoquer un accès.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openAuthorizedDevices(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.security_outlined,
                title: 'Journal sécurité',
                subtitle:
                    'Consulter les authentifications, limitations anti-bruteforce, enrôlements, révocations et événements terminaux.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openSecurityAudit(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.lock_clock_outlined,
                title: 'Sessions serveur',
                subtitle:
                    'Consulter les sessions courtes ouvertes côté serveur et révoquer les sessions actives inutiles.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openServerSessions(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.system_update_alt_outlined,
                title: 'Référentiel officiel aDRI',
                subtitle:
                    'Vérifier la dernière version publiée, la télécharger et l’installer sur le serveur OpenIRN.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openOfficialReferential(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.manage_history_outlined,
                title: 'Historique / conflits',
                subtitle:
                    'Consulter les révisions serveur des campagnes, analyser les conflits et restaurer une version si nécessaire.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openCampaignHistory(context),
              ),
              const SizedBox(height: 12),
              _AdministrationActionCard(
                icon: Icons.storage_outlined,
                title: 'Maintenance serveur',
                subtitle:
                    'Contrôler SQLite, créer une sauvegarde, restaurer ou supprimer une sauvegarde serveur.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openServerMaintenance(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdministrationActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _AdministrationActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(subtitle),
            ],
          ),
        ),
      ],
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
                  FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(buttonLabel),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(buttonLabel),
                  ),
                ],
              ),
      ),
    );
  }
}
