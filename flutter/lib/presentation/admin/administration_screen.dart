import 'package:flutter/material.dart';

import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../campaigns/campaign_management_screen.dart';
import '../common/openirn_app_bar.dart';
import '../users/user_list_screen.dart';
import 'authorized_devices_screen.dart';
import 'official_referential_screen.dart';
import 'server_maintenance_screen.dart';

class AdministrationScreen extends StatelessWidget {
  final IrnReferential referential;
  final AppUser activeUser;

  const AdministrationScreen({
    required this.referential,
    required this.activeUser,
    super.key,
  });

  Future<void> _openCampaignManagement(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CampaignManagementScreen(
          referential: referential,
          activeUser: activeUser,
        ),
      ),
    );
  }

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

  Future<void> _openOfficialReferential(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfficialReferentialScreen(activeUser: activeUser),
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
                subtitle:
                    'Créer une campagne, supprimer une campagne existante et nettoyer le journal associé.',
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
                icon: Icons.system_update_alt_outlined,
                title: 'Référentiel officiel aDRI',
                subtitle:
                    'Vérifier la dernière version publiée, la télécharger et l’installer sur le serveur OpenIRN.',
                buttonLabel: 'Ouvrir',
                onPressed: () => _openOfficialReferential(context),
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
