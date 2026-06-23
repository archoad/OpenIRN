#!/usr/bin/env python3
"""
Valide la cohérence entre le référentiel IRN canonique et les données entreprise importées.

Usage :
  python server/scripts/validate_irn_seed.py \
    --referential canonical_irn_v1_1.json \
    --company company_seed.json \
    --output validation_report.json
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

CRITERION_RE = re.compile(r"^(RES-[1-8])([.-])([0-9]+)$")


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    path: str = ""
    hint: str = ""


def load_json(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def normalize_criterion_code(value: Any) -> str:
    s = "" if value is None else str(value).strip()
    m = CRITERION_RE.match(s)
    if not m:
        return s
    return f"{m.group(1)}.{m.group(3)}"


def index_by_id(items: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {str(item.get("id", "")): item for item in items if item.get("id")}


def find_duplicates(values: list[str]) -> list[str]:
    return sorted([v for v, count in Counter(values).items() if v and count > 1])


def validate_referential(ref: dict[str, Any], issues: list[Issue]) -> dict[str, Any]:
    pillars = ref.get("pillars", [])
    criteria = ref.get("criteria", [])
    pillar_ids = [str(p.get("id", "")) for p in pillars]
    criterion_codes = [normalize_criterion_code(c.get("code") or c.get("id")) for c in criteria]

    if len(pillars) != 8:
        issues.append(Issue("error", "REF_PILLAR_COUNT", f"Le référentiel contient {len(pillars)} piliers au lieu de 8.", "referential.pillars"))
    if not criteria:
        issues.append(Issue("error", "REF_NO_CRITERIA", "Aucun critère trouvé dans le référentiel.", "referential.criteria"))

    for dup in find_duplicates(pillar_ids):
        issues.append(Issue("error", "REF_DUPLICATE_PILLAR", f"Pilier dupliqué: {dup}.", "referential.pillars"))
    for dup in find_duplicates(criterion_codes):
        issues.append(Issue("error", "REF_DUPLICATE_CRITERION", f"Critère dupliqué: {dup}.", "referential.criteria"))

    pillar_set = set(pillar_ids)
    for idx, criterion in enumerate(criteria):
        code = normalize_criterion_code(criterion.get("code") or criterion.get("id"))
        pillar_id = str(criterion.get("pillarId", ""))
        if not code:
            issues.append(Issue("error", "REF_CRITERION_WITHOUT_CODE", f"Critère sans code à l'index {idx}.", f"referential.criteria[{idx}]"))
            continue
        if not CRITERION_RE.match(code):
            issues.append(Issue("warning", "REF_CRITERION_CODE_FORMAT", f"Format de code critère inhabituel: {code}.", f"referential.criteria[{idx}].code"))
        if pillar_id not in pillar_set:
            issues.append(Issue("error", "REF_CRITERION_UNKNOWN_PILLAR", f"Le critère {code} référence un pilier inconnu: {pillar_id}.", f"referential.criteria[{idx}].pillarId"))
        if not str(criterion.get("label", "")).strip():
            issues.append(Issue("warning", "REF_CRITERION_EMPTY_LABEL", f"Le critère {code} n'a pas de libellé.", f"referential.criteria[{idx}].label"))

    return {
        "pillarCount": len(pillars),
        "criterionCount": len(criteria),
        "criteriaByScope": dict(Counter(str(c.get("scope", "unknown")) for c in criteria)),
    }


def validate_company(company_seed: dict[str, Any], ref: dict[str, Any], issues: list[Issue]) -> dict[str, Any]:
    company = company_seed.get("company", {})
    campaign = company_seed.get("campaign", {})
    ref_id = ref.get("id")
    campaign_ref_id = campaign.get("referentialId")

    if ref_id and campaign_ref_id and ref_id != campaign_ref_id:
        issues.append(Issue(
            "warning",
            "CAMPAIGN_REFERENTIAL_MISMATCH",
            f"La campagne référence {campaign_ref_id!r} alors que le référentiel chargé est {ref_id!r}.",
            "campaign.referentialId",
            "Vérifier que la campagne est bien rattachée à la version du référentiel utilisée pour le scoring.",
        ))

    entities = company.get("entities", [])
    business_functions = company.get("businessFunctions", [])
    critical_systems = company.get("criticalSystems", [])
    technical_functions = company.get("technicalFunctions", [])
    assets = company.get("assets", [])
    harmonized_assets = company.get("harmonizedAssets", [])
    assignments = campaign.get("assignments", [])

    entity_ids = {e.get("id") for e in entities}
    business_function_ids = {f.get("id") for f in business_functions}
    critical_system_ids = {s.get("id") for s in critical_systems}
    technical_function_ids = {f.get("id") for f in technical_functions}
    asset_ids = {a.get("id") for a in assets}
    harmonized_asset_ids = {a.get("id") for a in harmonized_assets}
    all_target_ids = asset_ids | harmonized_asset_ids

    for collection_name, collection, label in [
        ("entities", entities, "entité"),
        ("businessFunctions", business_functions, "fonction métier"),
        ("criticalSystems", critical_systems, "système critique"),
        ("technicalFunctions", technical_functions, "fonction technique"),
        ("assets", assets, "asset"),
        ("harmonizedAssets", harmonized_assets, "asset harmonisé"),
    ]:
        ids = [str(item.get("id", "")) for item in collection]
        for dup in find_duplicates(ids):
            issues.append(Issue("error", f"COMPANY_DUPLICATE_{collection_name.upper()}", f"ID de {label} dupliqué: {dup}.", f"company.{collection_name}"))
        for idx, item in enumerate(collection):
            if not str(item.get("name", "")).strip():
                issues.append(Issue("warning", f"COMPANY_EMPTY_NAME_{collection_name.upper()}", f"{label.capitalize()} sans nom: {item.get('id')}.", f"company.{collection_name}[{idx}].name"))

    for idx, item in enumerate(business_functions):
        if item.get("entityId") not in entity_ids:
            issues.append(Issue("error", "COMPANY_BF_UNKNOWN_ENTITY", f"La fonction métier {item.get('id')} référence une entité inconnue: {item.get('entityId')}.", f"company.businessFunctions[{idx}].entityId"))
    for idx, item in enumerate(critical_systems):
        if item.get("businessFunctionId") not in business_function_ids:
            issues.append(Issue("error", "COMPANY_SYSTEM_UNKNOWN_BF", f"Le système {item.get('id')} référence une fonction métier inconnue: {item.get('businessFunctionId')}.", f"company.criticalSystems[{idx}].businessFunctionId"))
    for idx, item in enumerate(technical_functions):
        if item.get("criticalSystemId") not in critical_system_ids:
            issues.append(Issue("error", "COMPANY_TF_UNKNOWN_SYSTEM", f"La fonction technique {item.get('id')} référence un système inconnu: {item.get('criticalSystemId')}.", f"company.technicalFunctions[{idx}].criticalSystemId"))
    for idx, item in enumerate(assets):
        if item.get("technicalFunctionId") not in technical_function_ids:
            issues.append(Issue("error", "COMPANY_ASSET_UNKNOWN_TF", f"L'asset {item.get('id')} référence une fonction technique inconnue: {item.get('technicalFunctionId')}.", f"company.assets[{idx}].technicalFunctionId"))

    source_asset_to_harmonized: dict[str, list[str]] = defaultdict(list)
    for idx, item in enumerate(harmonized_assets):
        if item.get("isCommon") and str(item.get("id", "")).startswith("E"):
            issues.append(Issue(
                "warning",
                "COMPANY_COMMON_ASSET_NOT_HARMONIZED",
                f"L'asset commun {item.get('name')!r} utilise un ID source {item.get('id')!r} au lieu d'une référence commune type C-Axxxx.",
                f"company.harmonizedAssets[{idx}].id",
            ))
        for source_id in item.get("sourceAssetIds", []):
            if source_id not in asset_ids:
                issues.append(Issue("warning", "COMPANY_HARMONIZED_UNKNOWN_SOURCE", f"L'asset harmonisé {item.get('id')} référence un asset source inconnu: {source_id}.", f"company.harmonizedAssets[{idx}].sourceAssetIds"))
            source_asset_to_harmonized[source_id].append(item.get("id"))
    for source_id, refs in source_asset_to_harmonized.items():
        if len(refs) > 1:
            issues.append(Issue("error", "COMPANY_SOURCE_ASSET_MULTI_MAPPING", f"L'asset source {source_id} est rattaché à plusieurs assets harmonisés: {refs}.", "company.harmonizedAssets"))

    criteria = ref.get("criteria", [])
    criteria_by_code = {normalize_criterion_code(c.get("code") or c.get("id")): c for c in criteria}
    assignment_criteria = set()
    assignment_targets = set()
    assignment_pairs = []

    for idx, assignment in enumerate(assignments):
        criterion_id = normalize_criterion_code(assignment.get("criterionId"))
        target_id = assignment.get("targetId")
        target_type = assignment.get("targetType")
        assignment_criteria.add(criterion_id)
        assignment_targets.add(target_id)
        assignment_pairs.append((target_id, criterion_id))

        if criterion_id not in criteria_by_code:
            issues.append(Issue("error", "ASSIGNMENT_UNKNOWN_CRITERION", f"Assignation vers un critère absent du référentiel: {criterion_id}.", f"campaign.assignments[{idx}].criterionId"))
        else:
            scope = criteria_by_code[criterion_id].get("scope")
            if target_type == "asset" and scope != "asset":
                issues.append(Issue(
                    "warning",
                    "ASSIGNMENT_SCOPE_MISMATCH",
                    f"Le critère {criterion_id} a une portée {scope!r}, mais il est assigné à un asset {target_id!r}.",
                    f"campaign.assignments[{idx}]",
                    "Décider si ce critère doit rester au niveau asset dans votre méthode interne ou être évalué au niveau organisation/fonction.",
                ))

        if target_id not in all_target_ids:
            issues.append(Issue("error", "ASSIGNMENT_UNKNOWN_TARGET", f"Assignation vers une cible inconnue: {target_id!r}.", f"campaign.assignments[{idx}].targetId"))
        if not str(assignment.get("assigneeId", "")).strip():
            issues.append(Issue("warning", "ASSIGNMENT_EMPTY_ASSIGNEE", f"Assignation sans évaluateur pour {target_id} / {criterion_id}.", f"campaign.assignments[{idx}].assigneeId"))

    for pair, count in Counter(assignment_pairs).items():
        if pair[0] and pair[1] and count > 1:
            issues.append(Issue("warning", "ASSIGNMENT_DUPLICATE_PAIR", f"Assignation dupliquée pour cible/critère: {pair[0]} / {pair[1]} ({count} fois).", "campaign.assignments"))

    asset_scope_criteria = {code for code, c in criteria_by_code.items() if c.get("scope") == "asset"}
    org_scope_criteria = {code for code, c in criteria_by_code.items() if c.get("scope") == "organization"}
    missing_asset_scope_assignments = sorted(asset_scope_criteria - assignment_criteria)
    assigned_org_scope_to_assets = sorted(org_scope_criteria & assignment_criteria)
    not_assigned_org_scope = sorted(org_scope_criteria - assignment_criteria)

    if missing_asset_scope_assignments:
        issues.append(Issue(
            "warning",
            "COVERAGE_MISSING_ASSET_CRITERIA",
            f"Critères de portée asset non assignés: {', '.join(missing_asset_scope_assignments)}.",
            "campaign.assignments",
        ))
    if not_assigned_org_scope:
        issues.append(Issue(
            "info",
            "COVERAGE_ORG_CRITERIA_TO_PLAN",
            f"Critères organisation/fonction à prévoir dans un écran dédié: {', '.join(not_assigned_org_scope)}.",
            "campaign.assignments",
        ))

    return {
        "entityCount": len(entities),
        "businessFunctionCount": len(business_functions),
        "criticalSystemCount": len(critical_systems),
        "technicalFunctionCount": len(technical_functions),
        "assetCount": len(assets),
        "harmonizedAssetCount": len(harmonized_assets),
        "assignmentCount": len(assignments),
        "assignmentTargetCount": len(assignment_targets),
        "assignedCriterionCount": len(assignment_criteria),
        "missingAssetScopeAssignments": missing_asset_scope_assignments,
        "assignedOrganizationScopeToAssets": assigned_org_scope_to_assets,
        "organizationScopeCriteriaToPlan": not_assigned_org_scope,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--referential", required=True, help="Chemin vers canonical_irn_v1_1.json")
    parser.add_argument("--company", required=True, help="Chemin vers company_seed.json")
    parser.add_argument("--output", default="validation_report.json", help="Chemin du rapport JSON")
    parser.add_argument("--fail-on-error", action="store_true", help="Retourne un code != 0 si des erreurs sont détectées")
    args = parser.parse_args()

    ref = load_json(args.referential)
    company_seed = load_json(args.company)
    issues: list[Issue] = []

    referential_stats = validate_referential(ref, issues)
    company_stats = validate_company(company_seed, ref, issues)
    counts_by_severity = dict(Counter(issue.severity for issue in issues))

    report = {
        "status": "failed" if counts_by_severity.get("error", 0) else "passed_with_warnings" if issues else "passed",
        "summary": {
            "errors": counts_by_severity.get("error", 0),
            "warnings": counts_by_severity.get("warning", 0),
            "infos": counts_by_severity.get("info", 0),
        },
        "referential": referential_stats,
        "company": company_stats,
        "issues": [asdict(issue) for issue in issues],
    }

    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Wrote {args.output}")
    print(f"status={report['status']} errors={report['summary']['errors']} warnings={report['summary']['warnings']} infos={report['summary']['infos']}")
    print(
        f"referential: pillars={referential_stats['pillarCount']}, "
        f"criteria={referential_stats['criterionCount']}, scopes={referential_stats['criteriaByScope']}"
    )
    print(
        f"company: entities={company_stats['entityCount']}, systems={company_stats['criticalSystemCount']}, "
        f"assets={company_stats['assetCount']}, harmonizedAssets={company_stats['harmonizedAssetCount']}, "
        f"assignments={company_stats['assignmentCount']}"
    )

    if issues:
        print("\nIssues principales:")
        for issue in issues[:20]:
            print(f"- [{issue.severity}] {issue.code}: {issue.message}")
        if len(issues) > 20:
            print(f"... {len(issues) - 20} autres issues dans {args.output}")

    if args.fail_on_error and counts_by_severity.get("error", 0):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
