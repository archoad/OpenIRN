---
title: "OpenIRN user guide"
subtitle: "Conducting a Digital Resilience Index assessment"
author: "OpenIRN Project"
---

# Welcome to OpenIRN

OpenIRN helps an organization structure and conduct Digital Resilience Index assessments. The application is used to prepare the scope, distribute criteria among several people, enter and justify answers, check quality, and produce a summary.

OpenIRN is an independent working tool. It does not issue certification and does not replace interpretation of the official referential published by aDRI / Digital Resilience Initiative.

# 1. Understand the terminology

| Term | Meaning in OpenIRN |
|---|---|
| Workspace | isolated scope for an organization or team |
| Critical function | business activity that the organization must preserve |
| Information system (IS) | set of resources supporting a critical function |
| Asset | human, information, software, hardware, or supplier component of the IS |
| Campaign | IRN assessment of an IS and its assets |
| Criterion | question or expectation from the IRN referential |
| Assignment | criterion allocated to an evaluator |
| Justification | factual information explaining the selected answer |
| Summary | consolidated view of campaign results |
| Device | computer, phone, or tablet running OpenIRN |

# 2. Roles, permissions, and responsibilities

Each person has a role within their workspace. An inactive account has no permissions, regardless of the role displayed.

## Administrator

**Responsibility:** ensure the operation, security, and correct configuration of OpenIRN.

An Administrator can:

- view the referential and all campaigns;
- create, modify, delete, and reset campaigns;
- answer every criterion and modify campaign information;
- manage assignments, exports, and campaign activity logs;
- manage the inventory of critical functions, information systems, and assets;
- manage users and their temporary PINs;
- create and administer workspaces;
- approve, rename, or revoke devices;
- view the security log and server sessions;
- update the official referential;
- view revisions, analyze conflicts, and restore a revision;
- check MariaDB and trigger a backup.

An active Administrator in the workspace designated as the solution administration workspace can administer other workspaces. This cross-workspace access does not apply to IRN Managers, Evaluators, Reviewers, or Readers.

## IRN Manager

**Responsibility:** organize the assessment and lead the campaign through validation.

An IRN Manager can:

- create and manage campaigns in their workspace;
- manage the inventory of critical functions, information systems, and assets;
- create a campaign from an IS and its assets;
- modify all answers in an editable campaign;
- assign criteria to Evaluators;
- view the summary and quality check;
- change the campaign status;
- export data and view the campaign activity log;
- view history and restore a revision;
- manage non-administrator users in their workspace;
- process device authorization requests and authorizations in their workspace.

An IRN Manager cannot manage workspaces, Administrators, the security log, server sessions, the official referential, or MariaDB maintenance.

## Evaluator

**Responsibility:** provide reliable and justified answers for the criteria assigned to them.

An Evaluator can:

- view the referential;
- open campaigns in their workspace;
- view the summary and quality check;
- see the criteria assigned to them;
- answer and add justifications only for those criteria while the campaign remains editable.

An Evaluator cannot create a campaign, change assignments, or answer criteria assigned to another person.

## Reviewer

**Responsibility:** review the assessment, evaluate the consistency of the evidence, and contribute to validation.

A Reviewer can:

- view the referential and campaigns;
- view answers, the summary, and the quality check;
- use the review workflow while a campaign is still editable.

A Reviewer does not perform routine criterion entry, manage campaigns, or administer the platform.

## Reader

**Responsibility:** read results without modifying them.

A Reader can view:

- the referential;
- the campaign list and campaign content;
- answers;
- the summary;
- the quality check.

A Reader cannot modify data.

## Summary matrix

| Function | Admin. | IRN Manager | Evaluator | Reviewer | Reader |
|---|:---:|:---:|:---:|:---:|:---:|
| View referential and campaigns | yes | yes | yes | yes | yes |
| View summary and quality | yes | yes | yes | yes | yes |
| Answer all criteria | yes | yes | no | no | no |
| Answer assigned criteria | yes | yes | yes | no | no |
| Review a campaign | yes | yes | no | yes | no |
| Manage campaigns and assignments | yes | yes | no | no | no |
| Manage the IS inventory | yes | yes | no | no | no |
| Manage users in the same workspace | yes | yes, except Administrators | no | no | no |
| Manage devices in the same workspace | yes | yes | no | no | no |
| Manage workspaces and server security | yes | no | no | no | no |
| Manage the referential and backups | yes | no | no | no | no |

# 3. First launch

## Choose a workspace

1. Open OpenIRN.
2. Select **Choose workspace**.
3. Choose the workspace provided by your manager.
4. Check its name before continuing.

Data is isolated by workspace. Changing workspace grants no additional permissions and may require the same device to be enrolled again.

## Authorize the device

If the home screen reports that the device is not authorized:

1. Open **Authorize this device**.
2. If you have a one-time code, enter it.
3. Otherwise, select **Request authorization**.
4. Inform the workspace IRN Manager or Administrator.
5. When you receive an approved code, enter it before it expires.

Do not send the code through a public channel. An authorization applies to one specific device and workspace.

## Open a session

1. Select **Unlock OpenIRN**.
2. Choose your profile.
3. Enter your personal access code.
4. If the code is temporary, immediately choose a new one.

The session is short-lived and remains only in memory. OpenIRN locks after a period of inactivity. Locking protects the session but does not revoke the device authorization.

## Change language

Select the flag in the top bar, then choose a language. The current application provides French, English, Spanish, and German.

# 4. Navigate the home screen

After opening a session, the home screen provides access to the main authorized functions:

- **Digital Resilience Index Assessment**: campaigns and data entry;
- **aDRI IRN referential**: pillars and criteria;
- **Administration**: actions reserved for Administrators and IRN Managers;
- workspace selection or change;
- connection and synchronization status;
- language selection;
- **About / License**: version and legal information.

If a card is not displayed, check your role first. The interface hides prohibited functions, and the server also checks every sensitive operation.

# 5. View the official referential

1. From the home screen, open **aDRI IRN referential**.
2. View the available pillars.
3. Open a pillar to display its criteria.
4. Open a criterion to read its label, description, scope, recommendations, and references.

Viewing the referential does not modify any campaign. The active version is loaded from the server; it is not a persistent business copy stored on the device.

# 6. Prepare the IS inventory

This function is available to Administrators and IRN Managers under **Administration → Critical functions, IS & assets**.

## Create a critical function

1. Select the option to add a critical function.
2. Give it a clear business name.
3. Add a description explaining the consequences of an interruption.
4. Save.

## Create an information system

1. Open the relevant critical function.
2. Add an information system.
3. Enter its name, description, and owner.
4. Save.

## Add assets

For each asset:

1. select the IS;
2. enter a distinctive name;
3. specify its type and a useful description;
4. assign a criticality level;
5. save.

The criticality levels are:

| Level | Label | Practical interpretation |
|---|---|---|
| N1 | standard | limited impact |
| N2 | moderate | noticeable impact |
| N3 | high | significant impact |
| N4 | critical | major impact on the function |

## Import or export with Excel

The screen can export the workspace template, which can then be completed and imported. Preserve protected identifiers in the file, do not rename worksheets arbitrarily, and review the validation report before confirming an import.

An export is a copy that may contain sensitive mapping information. Store it according to the organization's security policy.

# 7. Create a campaign

This action is available to an Administrator or IRN Manager.

1. Check that the official referential is installed.
2. Check that the IS and its assets exist in the inventory.
3. Open **Administration → Manage campaigns**.
4. Choose to create a campaign from an information system.
5. Select the critical function and then the IS.
6. Check the asset list and criticality levels.
7. Enter the campaign name, description, and project manager information.
8. Create the campaign.

The campaign starts with **Draft** status. Avoid generic names such as “Test” on a production instance.

# 8. Assign criteria

1. Open the campaign.
2. Open **Criterion assignments**.
3. Choose a pillar and then a criterion.
4. Select the appropriate Evaluator.
5. Save the assignment.

Assign criteria according to actual knowledge of the assets, not availability alone. Evaluators can enter data only for criteria explicitly assigned to them.

# 9. Answer an assessment

## Choose the asset

When a campaign contains several assets, first select the asset to assess. Answers are separate for each asset.

## Choose an answer

OpenIRN uses the following levels:

| Answer | Value used | General meaning |
|---|---:|---|
| N.C. | excluded from score | criterion not concerned; justification required |
| Not resilient | 10/100 | absent or significantly insufficient |
| Intention | 25/100 | intent identified, limited implementation |
| Means | 50/100 | resources committed, result still partial |
| Result | 95/100 | demonstrated and controlled result |

A high value must be supported by verifiable evidence. `N.C.` counts toward completeness but is excluded from score calculation.

## Add a justification

A good justification:

- describes what is actually in place;
- refers to evidence, an owner, or a time period;
- distinguishes an observed fact from a future project;
- remains understandable to a Reviewer;
- contains no password, token, or secret.

Example structure: “Procedure approved on …; exercise performed on …; report stored in …; next review planned for …”.

## Check that the answer was saved

Watch the synchronization indicator after a change. If an error occurs, do not make contradictory changes from different devices. Record the time, retain the message, and inform the IRN Manager.

# 10. Use the quality check

Open **Quality check** from the campaign. The screen highlights:

- unanswered criteria;
- missing or incomplete justifications;
- progress by pillar or asset;
- items preventing a complete review.

Address anomalies before moving to **Ready for review**. A score does not replace the quality of evidence.

# 11. Understand the summary

The summary shows overall results and results by pillar and asset. OpenIRN calculates:

- an asset score from the geometric mean of its pillar scores;
- a consolidated IS score from a geometric mean weighted by asset criticality.

A very low value can therefore have a strong effect on the result. Always read the summary together with the associated answers and justifications.

The screen can produce PNG and PDF summary exports. Check the scope, campaign, asset, and date before distribution.

# 12. Change campaign status

| Status | Purpose | Modification |
|---|---|---|
| Draft | data entry in progress | allowed according to role |
| Ready for review | entry complete, review expected | still editable |
| Validated | approved result | read-only |
| Archived | campaign retained for historical purposes | read-only |

The IRN Manager, Reviewer, or Administrator acts according to the commands offered by the interface and their permissions. Before validation, check quality, asset scope, justifications, and the summary.

# 13. Export a campaign

Depending on the available permissions, OpenIRN can produce:

- a campaign JSON export;
- a summary PNG image;
- a summary PDF;
- an activity log JSON export;
- an inventory Excel file.

Exports can contain sensitive information about the IS. Before sending them:

1. open the file;
2. check the campaign name and workspace;
3. check that it contains no information outside the recipient's scope;
4. use the sharing channel approved by the organization.

# 14. View the activity log

The campaign activity log records functional events: changes, status transitions, assignments, exports, and synchronization operations useful for auditing.

The activity log is not the security log. The security log is reserved for Administrators and covers events such as logins, authentication failures, enrollments, revocations, and anti-abuse rate limits.

# 15. Manage users

Administrators and IRN Managers open **Administration → Users**.

1. Check the displayed workspace.
2. Add or edit the profile.
3. Assign only the role required.
4. Enable or disable the account.
5. Save.

An IRN Manager cannot create or modify an Administrator. A new account does not automatically receive `0000`. An Administrator assigns a non-trivial temporary PIN, which the user must change at first login.

When a person leaves, disable the account and ask an Administrator to revoke its active sessions.

# 16. Manage devices

Under **Administration → Authorized devices**:

- pending requests are displayed before devices;
- an Administrator with the solution role can view all workspaces;
- an IRN Manager can view only their workspace;
- approval produces a temporary, one-time code;
- revocation removes authorization from that workspace;
- renaming improves identification without changing the technical identity.

Before approval, verify the requester's identity through a separate channel. If a device is lost or stolen, revoke it before taking any other action.

# 17. Change or lock your session

To change your access code, open **Administration → Change access code** when the card is available, enter the current code, and then enter the new one twice.

Choose a non-trivial code that differs from the previous one and is not shared. OpenIRN rejects obvious sequences and repetitions.

Lock the application when leaving the device. After locking, the device remains authorized, but no sensitive user operation is allowed until the next authentication.

# 18. Respond to a common problem

| Message or situation | User action |
|---|---|
| Device not authorized | check the workspace and request enrollment |
| Session expired | return to the home screen and unlock again |
| No editable criterion | check the assignment, role, and campaign status |
| Campaign is read-only | check whether it is Validated or Archived |
| Referential missing | notify an Administrator |
| Synchronization error | avoid repeated changes; record the time and message |
| Code rejected | check that it is not expired, already consumed, or entered in the wrong workspace |
| Account missing or inactive | contact the IRN Manager or Administrator |

# 19. Good practices

- use individual named accounts;
- assign the least-privileged role compatible with the responsibility;
- give clear names to workspaces, information systems, assets, campaigns, and devices;
- require a justification for every significant answer;
- perform tests in an identified acceptance campaign;
- never share a PIN, enrollment code, or screenshot containing secrets;
- lock the session before leaving the device;
- report a lost device immediately;
- export only the data required;
- where the organization allows it, have the campaign validated by someone other than the Evaluator.
