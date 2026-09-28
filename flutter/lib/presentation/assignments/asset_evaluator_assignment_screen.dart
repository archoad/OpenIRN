import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_asset_evaluator_assignment_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/asset_evaluator_assignment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/access_policy_service.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';

class AssetEvaluatorAssignmentScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;

  const AssetEvaluatorAssignmentScreen({
    required this.referential,
    required this.campaign,
    super.key,
  });

  @override
  State<AssetEvaluatorAssignmentScreen> createState() =>
      _AssetEvaluatorAssignmentScreenState();
}

class _AssetEvaluatorAssignmentScreenState
    extends State<AssetEvaluatorAssignmentScreen> {
  final _userRepository = const LocalUserRepository();
  final _assignmentRepository = const LocalAssetEvaluatorAssignmentRepository();
  final _activityRepository = const LocalActivityRepository();
  final _sessionRepository = const LocalSessionRepository();
  final _accessPolicy = const AccessPolicyService();

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
    final assignments = await _assignmentRepository.loadAssignmentsByAsset(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
    return _AssignmentState(
      activeUser: activeUser,
      evaluators: evaluators,
      usersById: <String, AppUser>{for (final user in users) user.id: user},
      assignmentsByAssetId: assignments,
    );
  }

  Future<void> _assignAsset({
    required CampaignInformationAsset asset,
    required String? userId,
    required _AssignmentState state,
  }) async {
    if (!_accessPolicy.canManageAssignments(
      state.activeUser,
      widget.campaign,
    )) {
      return;
    }

    final previousAssignment = state.assignmentsByAssetId[asset.id];
    final previousUser = previousAssignment == null
        ? null
        : state.usersById[previousAssignment.userId];
    final selectedUser = userId == null ? null : state.assignableUser(userId);
    if (userId != null && selectedUser == null) {
      return;
    }
    final activityTitle = context.tr(
      selectedUser == null
          ? 'assignment.activity.deleted'
          : previousAssignment == null
          ? 'assignment.activity.assigned'
          : 'assignment.activity.updated',
    );
    final unassignedLabel = context.tr('assignment.unassigned');
    final previousUserLabel = previousUser?.displayName ?? unassignedLabel;
    final selectedUserLabel = selectedUser?.displayName ?? unassignedLabel;

    AssetEvaluatorAssignment? savedAssignment;
    try {
      if (selectedUser == null) {
        await _assignmentRepository.clearAssignment(assetId: asset.id);
      } else {
        savedAssignment = await _assignmentRepository.assignAsset(
          referentialId: widget.referential.id,
          campaignId: widget.campaign.id,
          assetId: asset.id,
          userId: selectedUser.id,
          assignedByUserId: state.activeUser.id,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'assignment.error.save_failed',
              values: {'error': error},
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    final nextAssignments = Map<String, AssetEvaluatorAssignment>.of(
      state.assignmentsByAssetId,
    );
    if (savedAssignment == null) {
      nextAssignments.remove(asset.id);
    } else {
      nextAssignments[asset.id] = savedAssignment;
    }
    setState(() {
      _stateFuture = Future<_AssignmentState>.value(
        state.copyWith(assignmentsByAssetId: nextAssignments),
      );
    });

    try {
      await _activityRepository.appendEvent(
        LocalActivityEvent.create(
          referentialId: widget.referential.id,
          campaignId: widget.campaign.id,
          type: LocalActivityType.assignmentChanged,
          title: activityTitle,
          description: asset.displayLabel,
          fromValue: previousUserLabel,
          toValue: selectedUserLabel,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'assignment.error.activity_failed',
              values: {'error': error},
            ),
          ),
        ),
      );
    }
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
          if (state == null) {
            return Center(
              child: Text(
                snapshot.hasError
                    ? context.tr(
                        'assignment.error.load_failed',
                        values: {'error': snapshot.error},
                      )
                    : context.tr('assignment.empty'),
              ),
            );
          }

          final assets = widget.campaign.information.assets;
          final canManage = _accessPolicy.canManageAssignments(
            state.activeUser,
            widget.campaign,
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AssignmentHeaderCard(
                    campaign: widget.campaign,
                    evaluatorCount: state.evaluators.length,
                    assignedCount: state.assignmentsByAssetId.length,
                    totalAssets: assets.length,
                    activeUser: state.activeUser,
                    canManageAssignments: canManage,
                  ),
                  const SizedBox(height: 12),
                  if (assets.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(context.tr('assignment.empty.assets')),
                      ),
                    )
                  else
                    for (final asset in assets)
                      _AssetAssignmentCard(
                        asset: asset,
                        evaluators: state.evaluators,
                        usersById: state.usersById,
                        assignment: state.assignmentsByAssetId[asset.id],
                        readOnly: !canManage,
                        onChanged: (userId) => _assignAsset(
                          asset: asset,
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

class _AssignmentState {
  final AppUser activeUser;
  final List<AppUser> evaluators;
  final Map<String, AppUser> usersById;
  final Map<String, AssetEvaluatorAssignment> assignmentsByAssetId;

  const _AssignmentState({
    required this.activeUser,
    required this.evaluators,
    required this.usersById,
    required this.assignmentsByAssetId,
  });

  AppUser? assignableUser(String userId) {
    for (final user in evaluators) {
      if (user.id == userId) {
        return user;
      }
    }
    return null;
  }

  _AssignmentState copyWith({
    Map<String, AssetEvaluatorAssignment>? assignmentsByAssetId,
  }) {
    return _AssignmentState(
      activeUser: activeUser,
      evaluators: evaluators,
      usersById: usersById,
      assignmentsByAssetId: assignmentsByAssetId ?? this.assignmentsByAssetId,
    );
  }
}

class _AssignmentHeaderCard extends StatelessWidget {
  final LocalCampaign campaign;
  final int evaluatorCount;
  final int assignedCount;
  final int totalAssets;
  final AppUser activeUser;
  final bool canManageAssignments;

  const _AssignmentHeaderCard({
    required this.campaign,
    required this.evaluatorCount,
    required this.assignedCount,
    required this.totalAssets,
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
                      values: {'count': evaluatorCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assignment.chip.assigned',
                      values: {'assigned': assignedCount, 'total': totalAssets},
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
                if (!canManageAssignments)
                  Chip(
                    avatar: const Icon(Icons.lock_outline, size: 18),
                    label: Text(context.tr('assignment.chip.read_only_role')),
                  ),
                if (evaluatorCount == 0)
                  Chip(
                    avatar: const Icon(Icons.warning_amber_outlined, size: 18),
                    label: Text(context.tr('assignment.chip.no_evaluator')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetAssignmentCard extends StatelessWidget {
  final CampaignInformationAsset asset;
  final List<AppUser> evaluators;
  final Map<String, AppUser> usersById;
  final AssetEvaluatorAssignment? assignment;
  final bool readOnly;
  final ValueChanged<String?> onChanged;

  const _AssetAssignmentCard({
    required this.asset,
    required this.evaluators,
    required this.usersById,
    required this.assignment,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final assignedUserId = assignment?.userId;
    final isAssignable =
        assignedUserId != null &&
        evaluators.any((user) => user.id == assignedUserId);
    final staleUser = assignedUserId != null && !isAssignable
        ? usersById[assignedUserId]
        : null;
    final selectedUserId = assignedUserId == null
        ? ''
        : (isAssignable || staleUser != null)
        ? assignedUserId
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(asset.displayLabel),
              subtitle: Text(
                [
                  if (asset.assetType.trim().isNotEmpty) asset.assetType.trim(),
                  asset.criticalityLabel,
                ].join(' · '),
              ),
            );
            final dropdown = DropdownButtonFormField<String>(
              key: ValueKey<String>(
                'asset-evaluator-${asset.id}-$selectedUserId',
              ),
              initialValue: selectedUserId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('assignment.field.evaluator'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(context.tr('assignment.unassigned')),
                ),
                if (staleUser != null)
                  DropdownMenuItem<String>(
                    value: staleUser.id,
                    child: Text(_staleUserLabel(context, staleUser)),
                  ),
                for (final user in evaluators)
                  DropdownMenuItem<String>(
                    value: user.id,
                    child: Text(_userLabel(user)),
                  ),
              ],
              onChanged: readOnly
                  ? null
                  : (value) => onChanged(
                      value == null || value.isEmpty ? null : value,
                    ),
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const SizedBox(height: 8), dropdown],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: details),
                const SizedBox(width: 16),
                SizedBox(width: 380, child: dropdown),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _staleUserLabel(BuildContext context, AppUser user) {
    final identity = user.fullName.trim().isEmpty ? user.email : user.fullName;
    return context.tr(
      !user.active
          ? 'assignment.evaluator.inactive'
          : 'assignment.evaluator.not_evaluator',
      values: {'name': identity},
    );
  }

  static String _userLabel(AppUser user) {
    final identity = user.fullName.trim().isEmpty ? user.email : user.fullName;
    return '$identity · ${OpenIrnLocalizations.instance.text(user.role.label)}';
  }
}
