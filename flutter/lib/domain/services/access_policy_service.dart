import '../models/app_user.dart';
import '../models/criterion_assignment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';

class AccessPolicyService {
  const AccessPolicyService();

  bool canManageUsers(AppUser user) => canManageCampaigns(user);

  bool canManageCampaigns(AppUser user) {
    return user.active &&
        (user.role == AppUserRole.administrator ||
            user.role == AppUserRole.campaignManager);
  }

  bool canManageAssignments(AppUser user, LocalCampaign campaign) {
    return !campaign.isReadOnly && canManageCampaigns(user);
  }

  bool canEvaluateCriterion({
    required AppUser user,
    required LocalCampaign campaign,
    required IrnCriterion criterion,
    CriterionAssignment? assignment,
  }) {
    if (!user.active || campaign.isReadOnly) {
      return false;
    }
    if (user.role == AppUserRole.administrator ||
        user.role == AppUserRole.campaignManager) {
      return true;
    }
    if (user.role != AppUserRole.evaluator) {
      return false;
    }
    return assignment != null && assignment.userId == user.id;
  }

  bool canReviewCampaign(AppUser user, LocalCampaign campaign) {
    if (!user.active) {
      return false;
    }
    return user.role == AppUserRole.administrator ||
        user.role == AppUserRole.campaignManager ||
        user.role == AppUserRole.reviewer;
  }

  bool canReadCampaign(AppUser user) => user.active;
}
