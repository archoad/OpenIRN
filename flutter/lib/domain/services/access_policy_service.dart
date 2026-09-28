import '../models/app_user.dart';
import '../models/asset_evaluator_assignment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';

enum OpenIrnPermission {
  viewReferentialCatalog,
  viewCampaignList,
  viewCampaign,
  viewCampaignSummary,
  viewCampaignQuality,
  viewAssignedAssetsOnly,
  evaluateAssignedAsset,
  evaluateAnyCriterion,
  reviewCampaign,
  editCampaignInformation,
  manageCampaigns,
  manageAssignments,
  exportCampaignJson,
  viewCampaignActivityLog,
  clearCampaignActivityLog,
  resetCampaignAnswers,
  openAdministration,
  manageUsers,
  manageTenantUsers,
  manageTenants,
  manageAuthorizedDevices,
  manageTenantAuthorizedDevices,
  manageInformationAssets,
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
      OpenIrnPermission.clearCampaignActivityLog,
      OpenIrnPermission.resetCampaignAnswers,
      OpenIrnPermission.openAdministration,
      OpenIrnPermission.manageUsers,
      OpenIrnPermission.manageTenants,
      OpenIrnPermission.manageAuthorizedDevices,
      OpenIrnPermission.manageInformationAssets,
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
      OpenIrnPermission.clearCampaignActivityLog,
      OpenIrnPermission.resetCampaignAnswers,
      OpenIrnPermission.openAdministration,
      OpenIrnPermission.manageTenantUsers,
      OpenIrnPermission.manageTenantAuthorizedDevices,
      OpenIrnPermission.manageInformationAssets,
    },
    AppUserRole.evaluator: {
      OpenIrnPermission.viewReferentialCatalog,
      OpenIrnPermission.viewCampaignList,
      OpenIrnPermission.viewCampaign,
      OpenIrnPermission.viewCampaignSummary,
      OpenIrnPermission.viewCampaignQuality,
      OpenIrnPermission.viewAssignedAssetsOnly,
      OpenIrnPermission.evaluateAssignedAsset,
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

  bool canOpenAdministration(AppUser user) {
    return can(user, OpenIrnPermission.openAdministration);
  }

  bool canManageTenantUsers(AppUser user) {
    return can(user, OpenIrnPermission.manageUsers) ||
        can(user, OpenIrnPermission.manageTenantUsers);
  }

  bool canManageTenants(AppUser user) {
    return can(user, OpenIrnPermission.manageTenants);
  }

  bool canManageTenantAuthorizedDevices(AppUser user) {
    return can(user, OpenIrnPermission.manageAuthorizedDevices) ||
        can(user, OpenIrnPermission.manageTenantAuthorizedDevices);
  }

  bool canManageInformationAssets(AppUser user) {
    return can(user, OpenIrnPermission.manageInformationAssets);
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

  bool canClearCampaignActivityLog(AppUser user) {
    return can(user, OpenIrnPermission.clearCampaignActivityLog);
  }

  bool canResetCampaignAnswers(AppUser user, LocalCampaign campaign) {
    return !campaign.isReadOnly &&
        can(user, OpenIrnPermission.resetCampaignAnswers);
  }

  bool canEvaluateCriterion({
    required AppUser user,
    required LocalCampaign campaign,
    required IrnCriterion criterion,
    required String assetId,
    AssetEvaluatorAssignment? assignment,
  }) {
    if (!user.active || campaign.isReadOnly) {
      return false;
    }
    if (can(user, OpenIrnPermission.evaluateAnyCriterion)) {
      return true;
    }
    if (!can(user, OpenIrnPermission.evaluateAssignedAsset)) {
      return false;
    }
    return assignment != null &&
        assetId.trim().isNotEmpty &&
        assignment.assetId == assetId &&
        assignment.userId == user.id;
  }

  bool canReadCampaign(AppUser user) {
    return can(user, OpenIrnPermission.viewCampaign);
  }

  bool shouldLimitToAssignedAssets(AppUser user) {
    return can(user, OpenIrnPermission.viewAssignedAssetsOnly);
  }

  bool shouldOpenEvaluatorAssessmentWorkspace(AppUser user) {
    return user.active && user.role == AppUserRole.evaluator;
  }

  String administrationForbiddenMessage(AppUser user) {
    if (!user.active) {
      return 'La session active correspond à un utilisateur inactif.';
    }
    return 'La console d’administration est réservée aux profils Administrateur et Pilote IRN.';
  }
}
