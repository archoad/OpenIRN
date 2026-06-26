import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_assessment_repository.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAssessmentRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves and restores answers for a referential', () async {
      const repository = LocalAssessmentRepository();

      await repository.saveAnswers(
        referentialId: 'adri-irn-v1.1',
        answers: const <String, IrnAnswer>{
          'RES-1.1': IrnAnswer.resilient,
          'RES-1.2': IrnAnswer.nonResilient,
          'RES-1.3': IrnAnswer.notAnswered,
        },
      );

      final restored = await repository.loadAnswers(
        referentialId: 'adri-irn-v1.1',
      );

      expect(restored, hasLength(2));
      expect(restored['RES-1.1'], IrnAnswer.resilient);
      expect(restored['RES-1.2'], IrnAnswer.nonResilient);
      expect(restored.containsKey('RES-1.3'), isFalse);
    });

    test('saves and restores criterion justifications', () async {
      const repository = LocalAssessmentRepository();

      await repository.saveCriterionAnswers(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
        answers: const <String, CriterionAnswer>{
          'RES-2.1': CriterionAnswer(
            criterionId: 'RES-2.1',
            answer: IrnAnswer.resilient,
            justification: 'Contrat et clauses revus par le juridique.',
          ),
          'RES-2.2': CriterionAnswer(
            criterionId: 'RES-2.2',
            answer: IrnAnswer.notAnswered,
            justification: 'À vérifier avec les achats.',
          ),
        },
      );

      final restored = await repository.loadCriterionAnswers(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );

      expect(restored, hasLength(2));
      expect(restored['RES-2.1']?.answer, IrnAnswer.resilient);
      expect(
        restored['RES-2.1']?.justification,
        'Contrat et clauses revus par le juridique.',
      );
      expect(restored['RES-2.2']?.answer, IrnAnswer.notAnswered);
      expect(restored['RES-2.2']?.justification, 'À vérifier avec les achats.');
    });

    test('clears answers for one referential', () async {
      const repository = LocalAssessmentRepository();

      await repository.saveAnswers(
        referentialId: 'adri-irn-v1.1',
        answers: const <String, IrnAnswer>{'RES-2.1': IrnAnswer.resilient},
      );

      await repository.clearAnswers(referentialId: 'adri-irn-v1.1');

      final restored = await repository.loadAnswers(
        referentialId: 'adri-irn-v1.1',
      );
      expect(restored, isEmpty);
    });

    test('isolates answers by campaign', () async {
      const repository = LocalAssessmentRepository();

      await repository.saveAnswers(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
        answers: const <String, IrnAnswer>{'RES-1.1': IrnAnswer.resilient},
      );
      await repository.saveAnswers(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-b',
        answers: const <String, IrnAnswer>{'RES-1.1': IrnAnswer.nonResilient},
      );

      final first = await repository.loadAnswers(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );
      final second = await repository.loadAnswers(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-b',
      );

      expect(first['RES-1.1'], IrnAnswer.resilient);
      expect(second['RES-1.1'], IrnAnswer.nonResilient);
    });
  });
}
