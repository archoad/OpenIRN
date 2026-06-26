import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../common/openirn_app_bar.dart';

class CriterionAssignmentScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;

  const CriterionAssignmentScreen({
    required this.referential,
    required this.campaign,
    super.key,
  });

  @override
  State<CriterionAssignmentScreen> createState() => _CriterionAssignmentScreenState();
}

class _CriterionAssignmentScreenState extends State<CriterionAssignmentScreen> {
  final _userRepository = const LocalUserRepository();
  final _assignmentRepository = const LocalCriterionAssignmentRepository();
  final _activityRepository = const LocalActivityRepository();
  final _sessionRepository = const LocalSessionRepository();
  final _accessPolicy = const AccessPolicyService();
  final _catalogService = const ReferentialCatalogService();
  final _scrollController = ScrollController();
  final Set<String> _expandedPillarIds = <String>{};

  late Future<_AssignmentState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadState();
  }

  Future<_AssignmentState> _loadState() async {
    final activeUser = await _sessionRepository.getActiveUser();
    final users = await _userRepository.ensureDefaultUsers();
    final evaluators = users
        .where((user) => user.active && user.role == AppUserRole.evaluator)
        .toList(growable: false);
    final assignments = await _assignmentRepository.loadAssignmentsByCriterion(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
    return _AssignmentState(
      activeUser: activeUser,
      users: evaluators,
      assignmentsByCriterionId: assignments,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _assignCriterion({
    required IrnCriterion criterion,
    required String? userId,
    required _AssignmentState state,
  }) async {
    if (!_accessPolicy.canManageAssignments(state.activeUser, widget.campaign)) {
      return;
    }

    final previousAssignment = state.assignmentsByCriterionId[criterion.id];
    final previousUser = previousAssignment == null ? null : state.userById(previousAssignment.userId);

    if (userId == null || userId.trim().isEmpty) {
      await _assignmentRepository.clearAssignment(
        referentialId: widget.referential.id,
        campaignId: widget.campaign.id,
        criterionId: criterion.id,
      );
      await _activityRepository.appendEvent(
        LocalActivityEvent.create(
          referentialId: widget.referential.id,
          campaignId: widget.campaign.id,
          type: LocalActivityType.assignmentChanged,
          title: 'Affectation supprimée',
          description: '${criterion.code} — ${criterion.label}',
          criterionId: criterion.id,
          fromValue: previousUser?.displayName,
          toValue: 'Non affecté',
        ),
      );
      _updateAssignmentInCurrentState(
        state: state,
        criterionId: criterion.id,
        assignment: null,
      );
      return;
    }

    final selectedUser = state.userById(userId);
    if (selectedUser == null) {
      return;
    }

    final savedAssignment = await _assignmentRepository.assignCriterion(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
      criterionId: criterion.id,
      userId: userId,
      assignedByUserId: state.activeUser.id,
    );
    await _activityRepository.appendEvent(
      LocalActivityEvent.create(
        referentialId: widget.referential.id,
        campaignId: widget.campaign.id,
        type: LocalActivityType.assignmentChanged,
        title: previousAssignment == null ? 'Critère affecté' : 'Affectation modifiée',
        description: '${criterion.code} — ${criterion.label}',
        criterionId: criterion.id,
        fromValue: previousUser?.displayName ?? 'Non affecté',
        toValue: selectedUser.displayName,
      ),
    );
    _updateAssignmentInCurrentState(
      state: state,
      criterionId: criterion.id,
      assignment: savedAssignment,
    );
  }

  void _updateAssignmentInCurrentState({
    required _AssignmentState state,
    required String criterionId,
    required CriterionAssignment? assignment,
  }) {
    final nextAssignments = Map<String, CriterionAssignment>.of(state.assignmentsByCriterionId);
    if (assignment == null) {
      nextAssignments.remove(criterionId);
    } else {
      nextAssignments[criterionId] = assignment;
    }

    setState(() {
      _stateFuture = Future<_AssignmentState>.value(
        state.copyWith(assignmentsByCriterionId: nextAssignments),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Affectations des critères'),
      body: FutureBuilder<_AssignmentState>(
        future: _stateFuture,
        builder: (context, snapshot) {
          final state = snapshot.data;
          if (state == null && snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state == null && snapshot.hasError) {
            return Center(child: Text('Chargement impossible : ${snapshot.error}'));
          }
          if (state == null) {
            return const Center(child: Text('Aucune donnée d’affectation disponible.'));
          }
          final criteriaByPillar = _catalogService.criteriaByPillar(widget.referential);
          final activeCriteriaCount = widget.referential.criteria.where((criterion) => criterion.active).length;
          final evaluatorIds = state.users.map((user) => user.id).toSet();
          final canManageAssignments = _accessPolicy.canManageAssignments(state.activeUser, widget.campaign);
          final assignedCount = state.assignmentsByCriterionId.values
              .where((assignment) => evaluatorIds.contains(assignment.userId))
              .length;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _AssignmentHeaderCard(
                    campaign: widget.campaign,
                    userCount: state.users.length,
                    assignedCount: assignedCount,
                    totalCriteria: activeCriteriaCount,
                    activeUser: state.activeUser,
                    canManageAssignments: canManageAssignments,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in criteriaByPillar.entries)
                    Card(
                      child: ExpansionTile(
                        key: PageStorageKey<String>('assignment-pillar-${entry.key.id}'),
                        initiallyExpanded: _expandedPillarIds.contains(entry.key.id),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            if (expanded) {
                              _expandedPillarIds.add(entry.key.id);
                            } else {
                              _expandedPillarIds.remove(entry.key.id);
                            }
                          });
                        },
                        title: Text('${entry.key.code} — ${entry.key.label}'),
                        subtitle: Text('${entry.value.length} critère(s)'),
                        children: [
                          for (final criterion in entry.value)
                            _CriterionAssignmentTile(
                              criterion: criterion,
                              users: state.users,
                              assignment: state.assignmentsByCriterionId[criterion.id],
                              readOnly: !canManageAssignments,
                              onChanged: (userId) => _assignCriterion(
                                criterion: criterion,
                                userId: userId,
                                state: state,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssignmentState {
  final AppUser activeUser;
  final List<AppUser> users;
  final Map<String, CriterionAssignment> assignmentsByCriterionId;

  const _AssignmentState({
    required this.activeUser,
    required this.users,
    required this.assignmentsByCriterionId,
  });

  _AssignmentState copyWith({
    List<AppUser>? users,
    Map<String, CriterionAssignment>? assignmentsByCriterionId,
  }) {
    return _AssignmentState(
      activeUser: activeUser,
      users: users ?? this.users,
      assignmentsByCriterionId: assignmentsByCriterionId ?? this.assignmentsByCriterionId,
    );
  }

  AppUser? userById(String userId) {
    for (final user in users) {
      if (user.id == userId) {
        return user;
      }
    }
    return null;
  }
}

class _AssignmentHeaderCard extends StatelessWidget {
  final LocalCampaign campaign;
  final int userCount;
  final int assignedCount;
  final int totalCriteria;
  final AppUser activeUser;
  final bool canManageAssignments;

  const _AssignmentHeaderCard({
    required this.campaign,
    required this.userCount,
    required this.assignedCount,
    required this.totalCriteria,
    required this.activeUser,
    required this.canManageAssignments,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Affectations — ${campaign.name}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Affecte chaque critère à un utilisateur de secours disposant du profil Évaluateur. Les droits serveur et la connexion réelle seront ajoutés dans l’étape API.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Évaluateurs actifs : $userCount')),
                Chip(label: Text('Critères affectés : $assignedCount/$totalCriteria')),
                Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text('Session : ${activeUser.displayName}'),
                ),
                Chip(label: Text(activeUser.role.label)),
                if (!canManageAssignments)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 18),
                    label: Text('Lecture seule par rôle'),
                  ),
                if (userCount == 0)
                  const Chip(
                    avatar: Icon(Icons.warning_amber_outlined, size: 18),
                    label: Text('Aucun évaluateur actif'),
                  ),
                if (campaign.isReadOnly)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 18),
                    label: Text('Lecture seule'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CriterionAssignmentTile extends StatelessWidget {
  final IrnCriterion criterion;
  final List<AppUser> users;
  final CriterionAssignment? assignment;
  final bool readOnly;
  final ValueChanged<String?> onChanged;

  const _CriterionAssignmentTile({
    required this.criterion,
    required this.users,
    required this.assignment,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final criterionInfo = ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${criterion.code} — ${criterion.label}'),
      subtitle: Text('Portée : ${criterion.scope.label}'),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dropdown = _buildAssigneeDropdown();

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                criterionInfo,
                const SizedBox(height: 8),
                dropdown,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: criterionInfo),
              const SizedBox(width: 12),
              SizedBox(width: 380, child: dropdown),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAssigneeDropdown() {
    final selectedUserId = users.any((user) => user.id == assignment?.userId) ? assignment!.userId : '';

    return DropdownButtonFormField<String>(
      initialValue: selectedUserId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Évaluateur affecté',
        border: OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => [
        const Text('Non affecté', overflow: TextOverflow.ellipsis),
        for (final user in users)
          Text(
            _shortUserLabel(user),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Non affecté', overflow: TextOverflow.ellipsis),
        ),
        for (final user in users)
          DropdownMenuItem<String>(
            value: user.id,
            child: Text(
              _fullUserLabel(user),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
      onChanged: readOnly ? null : (value) => onChanged(value == null || value.isEmpty ? null : value),
    );
  }

  static String _shortUserLabel(AppUser user) {
    if (user.fullName.trim().isNotEmpty) {
      return user.fullName;
    }
    return user.email;
  }

  static String _fullUserLabel(AppUser user) {
    final identity = user.fullName.trim().isEmpty ? user.email : user.fullName;
    return '$identity · ${user.role.label}';
  }
}
