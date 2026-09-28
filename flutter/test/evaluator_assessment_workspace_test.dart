import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_campaign_repository.dart';
import 'package:openirn/domain/models/asset_evaluator_assignment.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/presentation/assessment/evaluator_assessment_workspace_screen.dart';

void main() {
  test('keeps only ongoing campaigns assigned to the active evaluator', () {
    final data = <LocalCampaignData>[
      _campaignData(
        id: 'draft-assigned',
        status: LocalCampaignStatus.draft,
        evaluatorId: 'evaluator-a',
      ),
      _campaignData(
        id: 'review-assigned',
        status: LocalCampaignStatus.readyForReview,
        evaluatorId: 'evaluator-a',
      ),
      _campaignData(
        id: 'validated-assigned',
        status: LocalCampaignStatus.validated,
        evaluatorId: 'evaluator-a',
      ),
      _campaignData(
        id: 'draft-other-evaluator',
        status: LocalCampaignStatus.draft,
        evaluatorId: 'evaluator-b',
      ),
    ];

    final campaigns = evaluatorAssessmentCampaigns(
      data,
      evaluatorId: 'evaluator-a',
    );

    expect(campaigns.map((entry) => entry.campaign.id), <String>[
      'draft-assigned',
      'review-assigned',
    ]);
    expect(campaigns.every((entry) => entry.assignmentCount == 1), isTrue);
    expect(
      campaigns.every(
        (entry) =>
            entry.assignedAssets.map((asset) => asset.id).toList().single ==
            'asset-test',
      ),
      isTrue,
    );
  });

  test('returns no campaign for an empty evaluator identifier', () {
    expect(
      evaluatorAssessmentCampaigns(<LocalCampaignData>[
        _campaignData(
          id: 'draft-assigned',
          status: LocalCampaignStatus.draft,
          evaluatorId: 'evaluator-a',
        ),
      ], evaluatorId: ' '),
      isEmpty,
    );
  });
}

LocalCampaignData _campaignData({
  required String id,
  required LocalCampaignStatus status,
  required String evaluatorId,
}) {
  final timestamp = DateTime.utc(2026, 9, 23);
  return LocalCampaignData(
    campaign: LocalCampaign(
      id: id,
      referentialId: 'referential-test',
      name: id,
      status: status,
      information: const CampaignInformation(
        systemName: 'SI test',
        informationSystemId: 'system-test',
        assets: <CampaignInformationAsset>[
          CampaignInformationAsset(id: 'asset-test', name: 'Actif test'),
          CampaignInformationAsset(id: 'asset-other', name: 'Autre actif'),
        ],
      ),
      createdAt: timestamp,
      updatedAt: timestamp,
      statusUpdatedAt: timestamp,
    ),
    criterionAnswers: const {},
    assignments: <AssetEvaluatorAssignment>[
      AssetEvaluatorAssignment.create(
        referentialId: 'referential-test',
        campaignId: id,
        assetId: 'asset-test',
        userId: evaluatorId,
        now: timestamp,
      ),
    ],
  );
}
