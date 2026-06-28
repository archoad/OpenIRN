enum CriterionScope {
  organization,
  businessFunction,
  criticalSystem,
  asset,
  unknown;

  static CriterionScope fromJson(String? value) {
    switch (value) {
      case 'organization':
        return CriterionScope.organization;
      case 'businessFunction':
        return CriterionScope.businessFunction;
      case 'criticalSystem':
        return CriterionScope.criticalSystem;
      case 'asset':
        return CriterionScope.asset;
      default:
        return CriterionScope.unknown;
    }
  }

  String get jsonValue {
    switch (this) {
      case CriterionScope.organization:
        return 'organization';
      case CriterionScope.businessFunction:
        return 'businessFunction';
      case CriterionScope.criticalSystem:
        return 'criticalSystem';
      case CriterionScope.asset:
        return 'asset';
      case CriterionScope.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case CriterionScope.organization:
        return 'Organisation';
      case CriterionScope.businessFunction:
        return 'Fonction métier';
      case CriterionScope.criticalSystem:
        return 'Système critique';
      case CriterionScope.asset:
        return 'Actif numérique';
      case CriterionScope.unknown:
        return 'Inconnue';
    }
  }
}

class IrnReferential {
  final String id;
  final String version;
  final DateTime? importedAt;
  final IrnSource source;
  final List<IrnPillar> pillars;
  final List<IrnCriterion> criteria;
  final List<String> importWarnings;

  const IrnReferential({
    required this.id,
    required this.version,
    required this.source,
    required this.pillars,
    required this.criteria,
    this.importedAt,
    this.importWarnings = const [],
  });

  factory IrnReferential.fromJson(Map<String, dynamic> json) {
    final pillars =
        (json['pillars'] as List<dynamic>? ?? const [])
            .map((item) => IrnPillar.fromJson(_asMap(item)))
            .toList(growable: false)
          ..sort((a, b) => compareIrnCodes(a.code, b.code));

    final criteria =
        (json['criteria'] as List<dynamic>? ?? const [])
            .map((item) => IrnCriterion.fromJson(_asMap(item)))
            .toList(growable: false)
          ..sort((a, b) => compareIrnCodes(a.code, b.code));

    return IrnReferential(
      id: _asString(json['id']),
      version: _asString(json['version']),
      importedAt: _asDateTime(json['importedAt']),
      source: IrnSource.fromJson(_asMap(json['source'])),
      pillars: List.unmodifiable(pillars),
      criteria: List.unmodifiable(criteria),
      importWarnings: List.unmodifiable(
        (json['importWarnings'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      ),
    );
  }

  String get license => source.license;
  String? get checksumSha256 => source.checksumSha256;
  String get sourceUrl => source.url;
}

class IrnSource {
  final String type;
  final String url;
  final String projectPath;
  final String defaultBranch;
  final String filePath;
  final String? commitSha;
  final String? checksumSha256;
  final String license;

  const IrnSource({
    required this.type,
    required this.url,
    required this.projectPath,
    required this.defaultBranch,
    required this.filePath,
    required this.license,
    this.commitSha,
    this.checksumSha256,
  });

  factory IrnSource.fromJson(Map<String, dynamic> json) {
    return IrnSource(
      type: _asString(json['type'], fallback: 'unknown'),
      url: _asString(json['url']),
      projectPath: _asString(json['projectPath']),
      defaultBranch: _asString(json['defaultBranch']),
      filePath: _asString(json['filePath']),
      commitSha: _asNullableString(json['commitSha']),
      checksumSha256: _asNullableString(json['checksumSha256']),
      license: _asString(json['license'], fallback: 'Non renseignée'),
    );
  }
}

class IrnPillar {
  final String id;
  final String code;
  final String label;
  final String description;

  const IrnPillar({
    required this.id,
    required this.code,
    required this.label,
    this.description = '',
  });

  factory IrnPillar.fromJson(Map<String, dynamic> json) {
    return IrnPillar(
      id: _asString(json['id']),
      code: _asString(json['code']),
      label: _asString(json['label']),
      description: _asString(json['description']),
    );
  }
}

class IrnCriterion {
  final String id;
  final String code;
  final String sourceCode;
  final String pillarId;
  final String label;
  final String shortLabel;
  final String description;
  final CriterionScope scope;
  final String sourceScope;
  final String answerMode;
  final String regulatoryReferences;
  final String recommendations;
  final bool active;
  final CriterionSourceLocation source;

  const IrnCriterion({
    required this.id,
    required this.code,
    required this.sourceCode,
    required this.pillarId,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.scope,
    required this.sourceScope,
    required this.answerMode,
    required this.regulatoryReferences,
    required this.recommendations,
    required this.active,
    required this.source,
  });

  factory IrnCriterion.fromJson(Map<String, dynamic> json) {
    return IrnCriterion(
      id: _asString(json['id']),
      code: _asString(json['code']),
      sourceCode: _asString(
        json['sourceCode'],
        fallback: _asString(json['code']),
      ),
      pillarId: _asString(json['pillarId']),
      label: _asString(json['label']),
      shortLabel: _asString(json['shortLabel']),
      description: _asString(json['description']),
      scope: CriterionScope.fromJson(_asNullableString(json['scope'])),
      sourceScope: _asString(json['sourceScope']),
      answerMode: _asString(json['answerMode'], fallback: 'R_NR'),
      regulatoryReferences: _asString(json['regulatoryReferences']),
      recommendations: _asString(json['recommendations']),
      active: json['active'] is bool ? json['active'] as bool : true,
      source: CriterionSourceLocation.fromJson(_asMap(json['source'])),
    );
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    return code.toLowerCase().contains(q) ||
        sourceCode.toLowerCase().contains(q) ||
        pillarId.toLowerCase().contains(q) ||
        label.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        sourceScope.toLowerCase().contains(q) ||
        recommendations.toLowerCase().contains(q);
  }
}

class CriterionSourceLocation {
  final String sheet;
  final int? row;

  const CriterionSourceLocation({this.sheet = '', this.row});

  factory CriterionSourceLocation.fromJson(Map<String, dynamic> json) {
    final rowValue = json['row'];
    return CriterionSourceLocation(
      sheet: _asString(json['sheet']),
      row: rowValue is int
          ? rowValue
          : int.tryParse(rowValue?.toString() ?? ''),
    );
  }
}

int compareIrnCodes(String a, String b) {
  final left = _parseIrnCode(a);
  final right = _parseIrnCode(b);
  if (left.$1 != right.$1) {
    return left.$1.compareTo(right.$1);
  }
  if (left.$2 != right.$2) {
    return left.$2.compareTo(right.$2);
  }
  return a.compareTo(b);
}

(int, int) _parseIrnCode(String code) {
  final match = RegExp(r'^RES-(\d+)(?:[.-](\d+))?$').firstMatch(code);
  if (match == null) {
    return (999, 999);
  }
  return (
    int.tryParse(match.group(1) ?? '') ?? 999,
    int.tryParse(match.group(2) ?? '0') ?? 0,
  );
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _asNullableString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _asDateTime(Object? value) {
  final text = _asNullableString(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text);
}
