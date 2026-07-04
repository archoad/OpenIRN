enum IrnAnswer {
  notAnswered,
  notConcerned,
  nonResilient,
  intention,
  medium,
  result;

  static const ratingValues = <IrnAnswer>[
    IrnAnswer.notConcerned,
    IrnAnswer.nonResilient,
    IrnAnswer.intention,
    IrnAnswer.medium,
    IrnAnswer.result,
  ];

  String get label {
    switch (this) {
      case IrnAnswer.notAnswered:
        return '—';
      case IrnAnswer.notConcerned:
        return 'N.C.';
      case IrnAnswer.nonResilient:
        return 'NR';
      case IrnAnswer.intention:
        return 'Intention';
      case IrnAnswer.medium:
        return 'Moyen';
      case IrnAnswer.result:
        return 'Résultat';
    }
  }

  String get longLabel {
    switch (this) {
      case IrnAnswer.notAnswered:
        return 'Non renseigné';
      case IrnAnswer.notConcerned:
        return 'Non concerné';
      case IrnAnswer.nonResilient:
        return 'Non résilient';
      case IrnAnswer.intention:
        return 'Intention';
      case IrnAnswer.medium:
        return 'Moyen';
      case IrnAnswer.result:
        return 'Résultat';
    }
  }

  int? get scoreValue {
    switch (this) {
      case IrnAnswer.notAnswered:
      case IrnAnswer.notConcerned:
        return null;
      case IrnAnswer.nonResilient:
        return 10;
      case IrnAnswer.intention:
        return 25;
      case IrnAnswer.medium:
        return 50;
      case IrnAnswer.result:
        return 95;
    }
  }

  bool get isAnswered => this != IrnAnswer.notAnswered;
  bool get isScored => scoreValue != null;

  /// Backward-compatible name used by existing UI, exports and quality checks.
  /// It now means "explicitly renseigné", including N.C.
  bool get isCounted => isAnswered;

  String get scoringHelp {
    final score = scoreValue;
    if (this == IrnAnswer.notConcerned) {
      return 'Non concerné — exclu du score';
    }
    if (score == null) {
      return 'Non renseigné';
    }
    return '$longLabel — $score/100';
  }
}

class CriterionAnswer {
  final String criterionId;
  final IrnAnswer answer;
  final String justification;

  const CriterionAnswer({
    required this.criterionId,
    required this.answer,
    this.justification = '',
  });

  bool get hasJustification => justification.trim().isNotEmpty;

  CriterionAnswer copyWith({IrnAnswer? answer, String? justification}) {
    return CriterionAnswer(
      criterionId: criterionId,
      answer: answer ?? this.answer,
      justification: justification ?? this.justification,
    );
  }
}

class IrnScoreSummary {
  final int totalCriteria;
  final int answeredCriteria;
  final int notConcernedCriteria;
  final int nonResilientCriteria;
  final int intentionCriteria;
  final int mediumCriteria;
  final int resultCriteria;
  final int notAnsweredCriteria;
  final int scorePointsTotal;

  const IrnScoreSummary({
    required this.totalCriteria,
    required this.answeredCriteria,
    required this.notConcernedCriteria,
    required this.nonResilientCriteria,
    required this.intentionCriteria,
    required this.mediumCriteria,
    required this.resultCriteria,
    required this.notAnsweredCriteria,
    required this.scorePointsTotal,
  });

  int get scoredCriteria =>
      nonResilientCriteria +
      intentionCriteria +
      mediumCriteria +
      resultCriteria;

  double? get openIrnScore {
    if (scoredCriteria == 0) {
      return null;
    }
    return scorePointsTotal / scoredCriteria;
  }

  /// Backward-compatible alias kept for existing UI/tests/exports.
  /// Prefer [openIrnScore] in new code.
  double? get openIrnRnrScore => openIrnScore;

  /// Backward-compatible alias kept for existing UI/tests/exports.
  double? get officialScore => openIrnScore;

  /// Backward-compatible alias: the former "R" bucket now maps to Résultat.
  int get resilientCriteria => resultCriteria;

  double get completionRate {
    if (totalCriteria == 0) {
      return 0;
    }
    return answeredCriteria / totalCriteria;
  }

  String get formattedOpenIrnScore {
    final score = openIrnScore;
    if (score == null) {
      return 'N/A';
    }
    return '${score.toStringAsFixed(1)} %';
  }

  /// Backward-compatible alias. Prefer [formattedOpenIrnScore].
  String get formattedOpenIrnRnrScore => formattedOpenIrnScore;

  /// Backward-compatible alias. Prefer [formattedOpenIrnScore].
  String get formattedOfficialScore => formattedOpenIrnScore;
}
