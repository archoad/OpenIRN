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
import '../../l10n/openirn_localizations.dart';
import '../common/irn_pillar_palette.dart';
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
  State<CriterionAssignmentScreen> createState() =>
      _CriterionAssignmentScreenState();
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
    final usersById = <String, AppUser>{
      for (final user in users) user.id: user,
    };
    final assignments = await _assignmentRepository.loadAssignmentsByCriterion(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
    return _AssignmentState(
      activeUser: activeUser,
      users: evaluators,
      usersById: usersById,
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
    if (!_accessPolicy.canManageAssignments(
      state.activeUser,
      widget.campaign,
    )) {
      return;
    }

    final previousAssignment = state.assignmentsByCriterionId[criterion.id];
    final previousUser = previousAssignment == null
        ? null
        : state.userById(previousAssignment.userId);

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
      if (!mounted) {
        return;
      }
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
        title: previousAssignment == null
            ? 'Critère affecté'
            : 'Affectation modifiée',
        description: '${criterion.code} — ${criterion.label}',
        criterionId: criterion.id,
        fromValue: previousUser?.displayName ?? 'Non affecté',
        toValue: selectedUser.displayName,
      ),
    );
    if (!mounted) {
      return;
    }
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
    final nextAssignments = Map<String, CriterionAssignment>.of(
      state.assignmentsByCriterionId,
    );
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
      appBar: OpenIrnAppBar(title: context.tr('assignment.title')),
      body: FutureBuilder<_AssignmentState>(
        future: _stateFuture,
        builder: (context, snapshot) {
          final state = snapshot.data;
          if (state == null &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state == null && snapshot.hasError) {
            return Center(
              child: Text(
                context.tr(
                  'assignment.error.load_failed',
                  values: {'error': snapshot.error},
                ),
              ),
            );
          }
          if (state == null) {
            return Center(child: Text(context.tr('assignment.empty')));
          }
          final criteriaByPillar = _catalogService.criteriaByPillar(
            widget.referential,
          );
          final activeCriteriaCount = widget.referential.criteria
              .where((criterion) => criterion.active)
              .length;
          final canManageAssignments = _accessPolicy.canManageAssignments(
            state.activeUser,
            widget.campaign,
          );
          // Every stored assignment record represents a criterion that is
          // assigned to someone, even if that evaluator was since
          // deactivated or reassigned a different role.
          final assignedCount = state.assignmentsByCriterionId.length;

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
                    _AssignmentPillarCard(
                      pillar: entry.key,
                      criteria: entry.value,
                      initiallyExpanded: _expandedPillarIds.contains(
                        entry.key.id,
                      ),
                      users: state.users,
                      usersById: state.usersById,
                      assignmentsByCriterionId: state.assignmentsByCriterionId,
                      readOnly: !canManageAssignments,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (expanded) {
                            _expandedPillarIds.add(entry.key.id);
                          } else {
                            _expandedPillarIds.remove(entry.key.id);
                          }
                        });
                      },
                      onAssignmentChanged: (criterion, userId) =>
                          _assignCriterion(
                            criterion: criterion,
                            userId: userId,
                            state: state,
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

class _AssignmentPillarCard extends StatelessWidget {
  final IrnPillar pillar;
  final List<IrnCriterion> criteria;
  final bool initiallyExpanded;
  final List<AppUser> users;
  final Map<String, AppUser> usersById;
  final Map<String, CriterionAssignment> assignmentsByCriterionId;
  final bool readOnly;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(IrnCriterion criterion, String? userId)
  onAssignmentChanged;

  const _AssignmentPillarCard({
    required this.pillar,
    required this.criteria,
    required this.initiallyExpanded,
    required this.users,
    required this.usersById,
    required this.assignmentsByCriterionId,
    required this.readOnly,
    required this.onExpansionChanged,
    required this.onAssignmentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pillarStyle = IrnPillarPalette.forPillar(pillar);
    return Card(
      color: pillarStyle.backgroundColor,
      shape: pillarStyle.cardShape(),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: pillarStyle.borderColor.withValues(alpha: 0.35),
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>('assignment-pillar-${pillar.id}'),
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpansionChanged,
          textColor: pillarStyle.foregroundColor,
          collapsedTextColor: pillarStyle.foregroundColor,
          iconColor: pillarStyle.borderColor,
          collapsedIconColor: pillarStyle.borderColor,
          title: Text('${pillar.code} — ${pillar.label}'),
          subtitle: Text(
            context.tr(
              'assignment.count.criteria',
              values: {'count': criteria.length},
            ),
          ),
          children: [
            for (final criterion in criteria)
              _CriterionAssignmentTile(
                criterion: criterion,
                users: users,
                usersById: usersById,
                assignment: assignmentsByCriterionId[criterion.id],
                readOnly: readOnly,
                onChanged: (userId) => onAssignmentChanged(criterion, userId),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentState {
  final AppUser activeUser;
  final List<AppUser> users;
  final Map<String, AppUser> usersById;
  final Map<String, CriterionAssignment> assignmentsByCriterionId;

  const _AssignmentState({
    required this.activeUser,
    required this.users,
    required this.usersById,
    required this.assignmentsByCriterionId,
  });

  _AssignmentState copyWith({
    List<AppUser>? users,
    Map<String, CriterionAssignment>? assignmentsByCriterionId,
  }) {
    return _AssignmentState(
      activeUser: activeUser,
      users: users ?? this.users,
      usersById: usersById,
      assignmentsByCriterionId:
          assignmentsByCriterionId ?? this.assignmentsByCriterionId,
    );
  }

  /// Restricted to currently assignable (active) evaluators — used to
  /// validate a *new* assignment choice.
  AppUser? userById(String userId) {
    for (final user in users) {
      if (user.id == userId) {
        return user;
      }
    }
    return null;
  }

  /// Looks up any known user regardless of active/role status — used to
  /// resolve who an *existing* assignment record actually points to, even
  /// if that person is no longer an assignable evaluator.
  AppUser? anyUserById(String userId) => usersById[userId];
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
            Text(
              context.tr(
                'assignment.header.title',
                values: {'campaign': campaign.name},
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(context.tr('assignment.header.description')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    context.tr(
                      'assignment.chip.evaluators',
                      values: {'count': userCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assignment.chip.assigned',
                      values: {
                        'assigned': assignedCount,
                        'total': totalCriteria,
                      },
                    ),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(
                    context.tr(
                      'assignment.chip.session',
                      values: {'user': activeUser.displayName},
                    ),
                  ),
                ),
                Chip(label: Text(context.trText(activeUser.role.label))),
                if (!canManageAssignments)
                  Chip(
                    avatar: const Icon(Icons.lock_outline, size: 18),
                    label: Text(context.tr('assignment.chip.read_only_role')),
                  ),
                if (userCount == 0)
                  Chip(
                    avatar: const Icon(Icons.warning_amber_outlined, size: 18),
                    label: Text(context.tr('assignment.chip.no_evaluator')),
                  ),
                if (campaign.isReadOnly)
                  Chip(
                    avatar: const Icon(Icons.lock_outline, size: 18),
                    label: Text(context.tr('common.read_only')),
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
  final Map<String, AppUser> usersById;
  final CriterionAssignment? assignment;
  final bool readOnly;
  final ValueChanged<String?> onChanged;

  const _CriterionAssignmentTile({
    required this.criterion,
    required this.users,
    required this.usersById,
    required this.assignment,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final criterionInfo = ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${criterion.code} — ${criterion.label}'),
      subtitle: Text(
        context.tr(
          'criterion.scope.value',
          values: {'scope': context.trText(criterion.scope.label)},
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dropdown = _buildAssigneeDropdown(context);

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [criterionInfo, const SizedBox(height: 8), dropdown],
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

  Widget _buildAssigneeDropdown(BuildContext context) {
    final assignedUserId = assignment?.userId;
    final isAssignableEvaluator =
        assignedUserId != null &&
        users.any((user) => user.id == assignedUserId);
    // The assignment record may point to a user who was since deactivated
    // or reassigned away from the Évaluateur role. Rather than silently
    // falling back to "Non affecté" and hiding that a real assignment still
    // exists, surface that user as a distinct, clearly-labelled entry.
    final staleAssignedUser = assignedUserId != null && !isAssignableEvaluator
        ? usersById[assignedUserId]
        : null;
    final selectedUserId = assignedUserId == null
        ? ''
        : (isAssignableEvaluator || staleAssignedUser != null)
        ? assignedUserId
        : '';

    return DropdownButtonFormField<String>(
      initialValue: selectedUserId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr('assignment.field.evaluator'),
        border: const OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => [
        Text(
          context.tr('assignment.unassigned'),
          overflow: TextOverflow.ellipsis,
        ),
        if (staleAssignedUser != null)
          Text(
            _staleUserLabel(context, staleAssignedUser),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        for (final user in users)
          Text(
            _shortUserLabel(user),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(
            context.tr('assignment.unassigned'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (staleAssignedUser != null)
          DropdownMenuItem<String>(
            value: staleAssignedUser.id,
            child: Text(
              _staleUserLabel(context, staleAssignedUser),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
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
      onChanged: readOnly
          ? null
          : (value) => onChanged(value == null || value.isEmpty ? null : value),
    );
  }

  static String _staleUserLabel(BuildContext context, AppUser user) {
    final identity = user.fullName.trim().isEmpty ? user.email : user.fullName;
    final isInactive = !user.active;
    return context.tr(
      isInactive
          ? 'assignment.evaluator.inactive'
          : 'assignment.evaluator.not_evaluator',
      values: {'name': identity},
      fallback: isInactive
          ? '$identity (compte non actif)'
          : '$identity (n’est plus évaluateur)',
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
    return '$identity · ${OpenIrnLocalizations.instance.text(user.role.label)}';
  }
}
