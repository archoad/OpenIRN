enum IrnAnswer {
  notAnswered,
  resilient,
  nonResilient;

  String get label {
    switch (this) {
      case IrnAnswer.notAnswered:
        return 'N.C.';
      case IrnAnswer.resilient:
        return 'R';
      case IrnAnswer.nonResilient:
        return 'NR';
    }
  }

  String get longLabel {
    switch (this) {
      case IrnAnswer.notAnswered:
        return 'Non coté';
      case IrnAnswer.resilient:
        return 'Résilient';
      case IrnAnswer.nonResilient:
        return 'Non résilient';
    }
  }

  bool get isCounted => this != IrnAnswer.notAnswered;
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
  final int resilientCriteria;
  final int nonResilientCriteria;
  final int notAnsweredCriteria;

  const IrnScoreSummary({
    required this.totalCriteria,
    required this.answeredCriteria,
    required this.resilientCriteria,
    required this.nonResilientCriteria,
    required this.notAnsweredCriteria,
  });

  double? get officialScore {
    if (answeredCriteria == 0) {
      return null;
    }
    return resilientCriteria * 100 / answeredCriteria;
  }

  double get completionRate {
    if (totalCriteria == 0) {
      return 0;
    }
    return answeredCriteria / totalCriteria;
  }

  String get formattedOfficialScore {
    final score = officialScore;
    if (score == null) {
      return 'N/A';
    }
    return '${score.toStringAsFixed(1)} %';
  }
}
