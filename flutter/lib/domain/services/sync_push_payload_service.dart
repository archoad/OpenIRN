import '../models/app_user.dart';
import '../models/criterion_assignment.dart';
import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_activity_event.dart';
import '../models/local_campaign.dart';
import '../models/sync_configuration.dart';

class CampaignSyncSnapshot {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final List<CriterionAssignment> assignments;
  final List<LocalActivityEvent> activityEvents;

  const CampaignSyncSnapshot({
    required this.campaign,
    required this.criterionAnswers,
    required this.assignments,
    required this.activityEvents,
  });

  int get answeredCount => criterionAnswers.values.where((answer) => answer.answer.isCounted).length;
  int get justifiedCount => criterionAnswers.values.where((answer) => answer.hasJustification).length;
}

class SyncPushPayloadService {
  const SyncPushPayloadService();

  Map<String, dynamic> buildPushPayload({
    required IrnReferential referential,
    required SyncConfiguration configuration,
    required AppUser activeUser,
    required List<AppUser> users,
    required List<CampaignSyncSnapshot> campaigns,
    DateTime? generatedAt,
  }) {
    final timestamp = (generatedAt ?? DateTime.now()).toUtc();

    return <String, dynamic>{
      'schemaVersion': 1,
      'type': 'openirn.syncPush',
      'application': 'OpenIRN',
      'generatedAt': timestamp.toIso8601String(),
      'sync': <String, dynamic>{
        'mode': 'local_prepare_push_payload',
        'enabled': configuration.enabled,
        'apiBaseUrl': configuration.apiBaseUrl,
        'tenantId': configuration.tenantId,
        'deviceId': configuration.deviceId,
        'isConfigured': configuration.isConfigured,
      },
      'actor': activeUser.toJson(),
      'referential': <String, dynamic>{
        'id': referential.id,
        'version': referential.version,
        'sourceUrl': referential.sourceUrl,
        'license': referential.license,
        'checksumSha256': referential.checksumSha256,
        'criteriaCount': referential.criteria.length,
        'pillarsCount': referential.pillars.length,
      },
      'users': users.map((user) => user.toJson()).toList(growable: false),
      'campaigns': campaigns.map(_campaignToJson).toList(growable: false),
      'summary': <String, dynamic>{
        'userCount': users.length,
        'campaignCount': campaigns.length,
        'answerCount': campaigns.fold<int>(0, (total, campaign) => total + campaign.criterionAnswers.length),
        'assignmentCount': campaigns.fold<int>(0, (total, campaign) => total + campaign.assignments.length),
        'activityEventCount': campaigns.fold<int>(0, (total, campaign) => total + campaign.activityEvents.length),
      },
    };
  }

  Map<String, dynamic> _campaignToJson(CampaignSyncSnapshot snapshot) {
    return <String, dynamic>{
      'campaign': snapshot.campaign.toJson(),
      'answers': snapshot.criterionAnswers.values.map(_answerToJson).toList(growable: false),
      'assignments': snapshot.assignments.map((assignment) => assignment.toJson()).toList(growable: false),
      'activityLog': <String, dynamic>{
        'eventCount': snapshot.activityEvents.length,
        'events': snapshot.activityEvents.map((event) => event.toJson()).toList(growable: false),
      },
      'localSummary': <String, dynamic>{
        'answeredCount': snapshot.answeredCount,
        'justifiedCount': snapshot.justifiedCount,
        'assignmentCount': snapshot.assignments.length,
        'activityEventCount': snapshot.activityEvents.length,
      },
    };
  }

  Map<String, dynamic> _answerToJson(CriterionAnswer answer) {
    return <String, dynamic>{
      'criterionId': answer.criterionId,
      'answer': answer.answer.name,
      'answerLabel': answer.answer.label,
      'justification': answer.justification.trim(),
      'hasJustification': answer.hasJustification,
    };
  }
}
