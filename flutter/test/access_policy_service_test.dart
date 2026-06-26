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

  AppUser user(String id, AppUserRole role) => AppUser(
        id: id,
        firstName: id,
        lastName: 'Test',
        email: '$id@example.test',
        role: role,
        active: true,
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
}
