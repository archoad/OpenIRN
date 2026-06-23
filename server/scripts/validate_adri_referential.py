#!/usr/bin/env python3
"""
Valide le JSON canonique produit depuis le référentiel officiel aDRI.

Usage :
  python server/scripts/validate_adri_referential.py \
    --input canonical_irn_v1_1.json \
    --output validation_referential_report.json

Le validateur contrôle le socle minimal attendu avant d'embarquer le référentiel dans Flutter.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PILLAR_RE = re.compile(r"^RES-[1-8]$")
CRITERION_RE = re.compile(r"^RES-[1-8]\.[0-9]+$")
SOURCE_CODE_RE = re.compile(r"^RES-[1-8][.-][0-9]+$")
ALLOWED_SCOPES = {"organization", "businessFunction", "criticalSystem", "asset", "unknown"}


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"Impossible de lire {path}: {exc}") from exc


def add_issue(target: list[dict[str, Any]], code: str, message: str, **details: Any) -> None:
    issue = {"code": code, "message": message}
    if details:
        issue["details"] = details
    target.append(issue)


def validate(data: dict[str, Any], expected_criteria: int | None) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []
    infos: list[dict[str, Any]] = []

    pillars = data.get("pillars") or []
    criteria = data.get("criteria") or []
    source = data.get("source") or {}

    if not data.get("id"):
        add_issue(errors, "missing_referential_id", "Le référentiel n'a pas d'identifiant.")
    if not data.get("version"):
        add_issue(errors, "missing_version", "Le référentiel n'a pas de version.")
    if not source.get("url"):
        add_issue(warnings, "missing_source_url", "L'URL source du référentiel est absente.")
    if not source.get("checksumSha256"):
        add_issue(warnings, "missing_checksum", "Le checksum SHA-256 du fichier source est absent.")
    if not source.get("license"):
        add_issue(warnings, "missing_license", "La licence du référentiel est absente.")

    if len(pillars) != 8:
        add_issue(errors, "unexpected_pillar_count", "Le référentiel doit contenir 8 piliers.", found=len(pillars))

    if not criteria:
        add_issue(errors, "no_criteria", "Aucun critère n'a été extrait du référentiel.")
    elif expected_criteria is not None and len(criteria) != expected_criteria:
        add_issue(
            warnings,
            "unexpected_criteria_count",
            "Le nombre de critères diffère du nombre attendu pour cette version.",
            expected=expected_criteria,
            found=len(criteria),
        )

    pillar_ids: set[str] = set()
    for pillar in pillars:
        code = pillar.get("code") or pillar.get("id")
        if not code or not PILLAR_RE.match(str(code)):
            add_issue(errors, "invalid_pillar_code", "Code pilier invalide.", pillar=pillar)
            continue
        if code in pillar_ids:
            add_issue(errors, "duplicate_pillar_code", "Code pilier dupliqué.", code=code)
        pillar_ids.add(code)
        if not pillar.get("label"):
            add_issue(warnings, "missing_pillar_label", "Libellé pilier absent.", code=code)

    criterion_codes: set[str] = set()
    criteria_by_pillar: defaultdict[str, list[str]] = defaultdict(list)
    scopes = Counter()

    for criterion in criteria:
        code = criterion.get("code") or criterion.get("id")
        if not code or not CRITERION_RE.match(str(code)):
            add_issue(errors, "invalid_criterion_code", "Code critère invalide.", criterion=criterion)
            continue

        if code in criterion_codes:
            add_issue(errors, "duplicate_criterion_code", "Code critère dupliqué.", code=code)
        criterion_codes.add(code)

        source_code = criterion.get("sourceCode")
        if source_code and not SOURCE_CODE_RE.match(str(source_code)):
            add_issue(warnings, "invalid_source_code", "Code source atypique.", code=code, sourceCode=source_code)

        pillar_id = criterion.get("pillarId")
        expected_pillar = str(code).split(".")[0]
        if pillar_id != expected_pillar:
            add_issue(warnings, "criterion_pillar_mismatch", "Le pilier du critère ne correspond pas au code critère.", code=code, pillarId=pillar_id, expected=expected_pillar)
        if pillar_id not in pillar_ids:
            add_issue(errors, "unknown_criterion_pillar", "Le critère référence un pilier inconnu.", code=code, pillarId=pillar_id)
        else:
            criteria_by_pillar[pillar_id].append(code)

        if not criterion.get("label"):
            add_issue(warnings, "missing_criterion_label", "Libellé critère absent.", code=code)

        scope = criterion.get("scope") or "unknown"
        scopes[str(scope)] += 1
        if scope not in ALLOWED_SCOPES:
            add_issue(warnings, "invalid_scope", "Portée de critère inconnue.", code=code, scope=scope)
        elif scope == "unknown":
            add_issue(warnings, "unknown_scope", "Portée de critère non déterminée.", code=code)

        if criterion.get("answerMode") != "R_NR":
            add_issue(warnings, "unexpected_answer_mode", "Mode de réponse inattendu.", code=code, answerMode=criterion.get("answerMode"))

    for pillar_id in sorted(pillar_ids):
        if not criteria_by_pillar.get(pillar_id):
            add_issue(warnings, "pillar_without_criteria", "Aucun critère rattaché à ce pilier.", pillarId=pillar_id)

    add_issue(
        infos,
        "summary",
        "Synthèse du référentiel.",
        referentialId=data.get("id"),
        version=data.get("version"),
        pillars=len(pillars),
        criteria=len(criteria),
        scopes=dict(sorted(scopes.items())),
        criteriaByPillar={k: len(v) for k, v in sorted(criteria_by_pillar.items())},
    )

    status = "failed" if errors else ("passed_with_warnings" if warnings else "passed")
    return {
        "status": status,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "infos": infos,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="JSON canonique du référentiel")
    parser.add_argument("--output", default=None, help="Rapport JSON optionnel")
    parser.add_argument("--expected-criteria", type=int, default=30, help="Nombre attendu de critères. Utiliser 0 pour désactiver ce contrôle.")
    args = parser.parse_args()

    expected_criteria = None if args.expected_criteria == 0 else args.expected_criteria
    data = load_json(Path(args.input))
    report = validate(data, expected_criteria=expected_criteria)

    if args.output:
        Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    summary = report["infos"][0]["details"] if report.get("infos") else {}
    print(
        f"status={report['status']} "
        f"errors={len(report['errors'])} "
        f"warnings={len(report['warnings'])} "
        f"pillars={summary.get('pillars')} "
        f"criteria={summary.get('criteria')} "
        f"scopes={summary.get('scopes')}"
    )

    if report["errors"]:
        print("Errors:")
        for issue in report["errors"]:
            print(f"- {issue['code']}: {issue['message']}")
        sys.exit(1)

    if report["warnings"]:
        print("Warnings:")
        for issue in report["warnings"]:
            details = issue.get("details") or {}
            suffix = f" {details}" if details else ""
            print(f"- {issue['code']}: {issue['message']}{suffix}")


if __name__ == "__main__":
    main()
