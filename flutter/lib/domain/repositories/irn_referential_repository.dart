import '../models/irn_referential.dart';

abstract class IrnReferentialRepository {
  Future<IrnReferential> getActiveReferential();
}
