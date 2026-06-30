import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:openirn/domain/models/criterion_assignment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/services/access_policy_service.dart';

void main() {
  const service = AccessPolicyService();
  final campaign = LocalCampaign.create(
    referentialId: 'adri-irn-v1.1',
    name: 'Campagne test',
    now: DateTime.utc(2026, 6, 24),
  );
  const criterion = IrnCriterion(
    id: 'RES-1.1',
    code: 'RES-1.1',
    sourceCode: 'RES-1.1',
    pillarId: 'RES-1',
    label: 'Critère test',
    shortLabel: 'Critère test',
    description: 'Critère test',
    scope: CriterionScope.organization,
    sourceScope: 'Organisation',
    answerMode: 'R_NR',
    regulatoryReferences: '',
    recommendations: '',
    active: true,
    source: CriterionSourceLocation(sheet: 'test', row: 1),
  );

  AppUser user(String id, AppUserRole role, {bool active = true}) => AppUser(
    id: id,
    firstName: id,
    lastName: 'Test',
    email: '$id@example.test',
    role: role,
    active: active,
    createdAt: DateTime.utc(2026, 6, 24),
    updatedAt: DateTime.utc(2026, 6, 24),
  );

  CriterionAssignment assignmentFor(String userId) =>
      CriterionAssignment.create(
        referentialId: 'adri-irn-v1.1',
        campaignId: campaign.id,
        criterionId: criterion.id,
        userId: userId,
        assignedByUserId: 'pilot',
        now: DateTime.utc(2026, 6, 24),
      );

  test('inactive users have no permission', () {
    final inactiveAdmin = user(
      'inactive-admin',
      AppUserRole.administrator,
      active: false,
    );

    expect(service.can(inactiveAdmin, OpenIrnPermission.manageUsers), isFalse);
    expect(service.canManageCampaigns(inactiveAdmin), isFalse);
    expect(service.canReadCampaign(inactiveAdmin), isFalse);
  });

  test('administrator has full administration permissions', () {
    final admin = user('admin', AppUserRole.administrator);

    expect(service.canOpenAdministration(admin), isTrue);
    expect(service.canManageUsers(admin), isTrue);
    expect(service.canManageAuthorizedDevices(admin), isTrue);
    expect(service.canViewSecurityAudit(admin), isTrue);
    expect(service.canManageServerSessions(admin), isTrue);
    expect(service.canManageOfficialReferential(admin), isTrue);
    expect(service.canManageServerMaintenance(admin), isTrue);
  });

  test(
    'campaign manager keeps campaign permissions but not platform security',
    () {
      final pilot = user('pilot', AppUserRole.campaignManager);

      expect(service.canOpenAdministration(pilot), isTrue);
      expect(service.canManageCampaigns(pilot), isTrue);
      expect(service.canManageAssignments(pilot, campaign), isTrue);
      expect(service.canViewCampaignHistory(pilot), isTrue);
      expect(service.canManageUsers(pilot), isFalse);
      expect(service.canManageAuthorizedDevices(pilot), isFalse);
      expect(service.canViewSecurityAudit(pilot), isFalse);
      expect(service.canManageServerSessions(pilot), isFalse);
      expect(service.canManageServerMaintenance(pilot), isFalse);
    },
  );

  test(
    'administrators and campaign managers can evaluate any editable campaign',
    () {
      for (final role in [
        AppUserRole.administrator,
        AppUserRole.campaignManager,
      ]) {
        expect(
          service.canEvaluateCriterion(
            user: user(role.jsonValue, role),
            campaign: campaign,
            criterion: criterion,
          ),
          isTrue,
        );
      }
    },
  );

  test('evaluators can evaluate only criteria explicitly assigned to them', () {
    final evaluator = user('evaluator-1', AppUserRole.evaluator);

    expect(service.shouldLimitToAssignedCriteria(evaluator), isTrue);
    expect(
      service.canEvaluateCriterion(
        user: evaluator,
        campaign: campaign,
        criterion: criterion,
      ),
      isFalse,
    );
    expect(
      service.canEvaluateCriterion(
        user: evaluator,
        campaign: campaign,
        criterion: criterion,
        assignment: assignmentFor('another-evaluator'),
      ),
      isFalse,
    );
    expect(
      service.canEvaluateCriterion(
        user: evaluator,
        campaign: campaign,
        criterion: criterion,
        assignment: assignmentFor(evaluator.id),
      ),
      isTrue,
    );
  });

  test('reviewers and readers cannot evaluate criteria', () {
    for (final role in [AppUserRole.reviewer, AppUserRole.reader]) {
      expect(
        service.canEvaluateCriterion(
          user: user(role.jsonValue, role),
          campaign: campaign,
          criterion: criterion,
          assignment: assignmentFor(role.jsonValue),
        ),
        isFalse,
      );
    }
  });

  test('basic campaign read, summary and quality permissions are shared', () {
    for (final role in AppUserRole.values) {
      final activeUser = user(role.jsonValue, role);

      expect(service.canReadCampaign(activeUser), isTrue);
      expect(
        service.can(activeUser, OpenIrnPermission.viewCampaignSummary),
        isTrue,
      );
      expect(
        service.can(activeUser, OpenIrnPermission.viewCampaignQuality),
        isTrue,
      );
    }
  });
}
