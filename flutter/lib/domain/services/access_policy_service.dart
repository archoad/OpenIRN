import '../models/app_user.dart';
import '../models/criterion_assignment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';

enum OpenIrnPermission {
  viewReferentialCatalog,
  viewCampaignList,
  viewCampaign,
  viewCampaignSummary,
  viewCampaignQuality,
  viewAssignedCriteriaOnly,
  evaluateAssignedCriterion,
  evaluateAnyCriterion,
  reviewCampaign,
  editCampaignInformation,
  manageCampaigns,
  manageAssignments,
  exportCampaignJson,
  viewCampaignActivityLog,
  resetCampaignAnswers,
  openAdministration,
  manageUsers,
  manageTenants,
  manageAuthorizedDevices,
  viewSecurityAudit,
  manageServerSessions,
  manageOfficialReferential,
  viewCampaignHistory,
  restoreCampaignRevision,
  manageServerMaintenance,
  manageSyncConfiguration,
}

class AccessPolicyService {
  const AccessPolicyService();

  static const Map<AppUserRole, Set<OpenIrnPermission>> _permissionsByRole = {
    AppUserRole.administrator: {
      OpenIrnPermission.viewReferentialCatalog,
      OpenIrnPermission.viewCampaignList,
      OpenIrnPermission.viewCampaign,
      OpenIrnPermission.viewCampaignSummary,
      OpenIrnPermission.viewCampaignQuality,
      OpenIrnPermission.evaluateAnyCriterion,
      OpenIrnPermission.reviewCampaign,
      OpenIrnPermission.editCampaignInformation,
      OpenIrnPermission.manageCampaigns,
      OpenIrnPermission.manageAssignments,
      OpenIrnPermission.exportCampaignJson,
      OpenIrnPermission.viewCampaignActivityLog,
      OpenIrnPermission.resetCampaignAnswers,
      OpenIrnPermission.openAdministration,
      OpenIrnPermission.manageUsers,
      OpenIrnPermission.manageTenants,
      OpenIrnPermission.manageAuthorizedDevices,
      OpenIrnPermission.viewSecurityAudit,
      OpenIrnPermission.manageServerSessions,
      OpenIrnPermission.manageOfficialReferential,
      OpenIrnPermission.viewCampaignHistory,
      OpenIrnPermission.restoreCampaignRevision,
      OpenIrnPermission.manageServerMaintenance,
      OpenIrnPermission.manageSyncConfiguration,
    },
    AppUserRole.campaignManager: {
      OpenIrnPermission.viewReferentialCatalog,
      OpenIrnPermission.viewCampaignList,
      OpenIrnPermission.viewCampaign,
      OpenIrnPermission.viewCampaignSummary,
      OpenIrnPermission.viewCampaignQuality,
      OpenIrnPermission.evaluateAnyCriterion,
      OpenIrnPermission.reviewCampaign,
      OpenIrnPermission.editCampaignInformation,
      OpenIrnPermission.manageCampaigns,
      OpenIrnPermission.manageAssignments,
      OpenIrnPermission.exportCampaignJson,
      OpenIrnPermission.viewCampaignActivityLog,
      OpenIrnPermission.resetCampaignAnswers,
      OpenIrnPermission.openAdministration,
      OpenIrnPermission.viewCampaignHistory,
      OpenIrnPermission.restoreCampaignRevision,
    },
    AppUserRole.evaluator: {
      OpenIrnPermission.viewReferentialCatalog,
      OpenIrnPermission.viewCampaignList,
      OpenIrnPermission.viewCampaign,
      OpenIrnPermission.viewCampaignSummary,
      OpenIrnPermission.viewCampaignQuality,
      OpenIrnPermission.viewAssignedCriteriaOnly,
      OpenIrnPermission.evaluateAssignedCriterion,
    },
    AppUserRole.reviewer: {
      OpenIrnPermission.viewReferentialCatalog,
      OpenIrnPermission.viewCampaignList,
      OpenIrnPermission.viewCampaign,
      OpenIrnPermission.viewCampaignSummary,
      OpenIrnPermission.viewCampaignQuality,
      OpenIrnPermission.reviewCampaign,
    },
    AppUserRole.reader: {
      OpenIrnPermission.viewReferentialCatalog,
      OpenIrnPermission.viewCampaignList,
      OpenIrnPermission.viewCampaign,
      OpenIrnPermission.viewCampaignSummary,
      OpenIrnPermission.viewCampaignQuality,
    },
  };

  bool can(AppUser? user, OpenIrnPermission permission) {
    if (user == null || !user.active) {
      return false;
    }
    return _permissionsByRole[user.role]?.contains(permission) ?? false;
  }

  bool hasAny(AppUser? user, Iterable<OpenIrnPermission> permissions) {
    return permissions.any((permission) => can(user, permission));
  }

  bool canOpenAdministration(AppUser user) {
    return can(user, OpenIrnPermission.openAdministration);
  }

  bool canManageUsers(AppUser user) {
    return can(user, OpenIrnPermission.manageUsers);
  }

  bool canManageTenants(AppUser user) {
    return can(user, OpenIrnPermission.manageTenants);
  }

  bool canManageAuthorizedDevices(AppUser user) {
    return can(user, OpenIrnPermission.manageAuthorizedDevices);
  }

  bool canViewSecurityAudit(AppUser user) {
    return can(user, OpenIrnPermission.viewSecurityAudit);
  }

  bool canManageServerSessions(AppUser user) {
    return can(user, OpenIrnPermission.manageServerSessions);
  }

  bool canManageOfficialReferential(AppUser user) {
    return can(user, OpenIrnPermission.manageOfficialReferential);
  }

  bool canViewCampaignHistory(AppUser user) {
    return can(user, OpenIrnPermission.viewCampaignHistory);
  }

  bool canRestoreCampaignRevision(AppUser user) {
    return can(user, OpenIrnPermission.restoreCampaignRevision);
  }

  bool canManageServerMaintenance(AppUser user) {
    return can(user, OpenIrnPermission.manageServerMaintenance);
  }

  bool canManageSyncConfiguration(AppUser user) {
    return can(user, OpenIrnPermission.manageSyncConfiguration);
  }

  bool canManageCampaigns(AppUser user) {
    return can(user, OpenIrnPermission.manageCampaigns);
  }

  bool canEditCampaignInformation(AppUser user, LocalCampaign campaign) {
    return !campaign.isReadOnly &&
        can(user, OpenIrnPermission.editCampaignInformation);
  }

  bool canManageAssignments(AppUser user, LocalCampaign campaign) {
    return !campaign.isReadOnly &&
        can(user, OpenIrnPermission.manageAssignments);
  }

  bool canExportCampaign(AppUser user) {
    return can(user, OpenIrnPermission.exportCampaignJson);
  }

  bool canViewCampaignActivityLog(AppUser user) {
    return can(user, OpenIrnPermission.viewCampaignActivityLog);
  }

  bool canResetCampaignAnswers(AppUser user, LocalCampaign campaign) {
    return !campaign.isReadOnly &&
        can(user, OpenIrnPermission.resetCampaignAnswers);
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
    if (can(user, OpenIrnPermission.evaluateAnyCriterion)) {
      return true;
    }
    if (!can(user, OpenIrnPermission.evaluateAssignedCriterion)) {
      return false;
    }
    return assignment != null && assignment.userId == user.id;
  }

  bool canReviewCampaign(AppUser user, LocalCampaign campaign) {
    return !campaign.isReadOnly && can(user, OpenIrnPermission.reviewCampaign);
  }

  bool canReadCampaign(AppUser user) {
    return can(user, OpenIrnPermission.viewCampaign);
  }

  bool shouldLimitToAssignedCriteria(AppUser user) {
    return can(user, OpenIrnPermission.viewAssignedCriteriaOnly);
  }

  String administrationForbiddenMessage(AppUser user) {
    if (!user.active) {
      return 'La session active correspond à un utilisateur inactif.';
    }
    return 'La console d’administration est réservée aux profils Administrateur et Pilote IRN.';
  }
}
