import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/device_enrollment_request.dart';
import 'package:openirn/l10n/openirn_localizations.dart';
import 'package:openirn/presentation/admin/authorized_devices_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await OpenIrnLocalizations.instance.initialize();
  });

  for (final language in [OpenIrnLanguage.es, OpenIrnLanguage.de]) {
    testWidgets(
      'pending enrollment actions fit below details on a phone in ${language.code}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await OpenIrnLocalizations.instance.setLanguage(
          language,
          persist: false,
        );

        var approved = false;
        var rejected = false;
        final request = DeviceEnrollmentRequest(
          tenantId: 'tenant-a',
          requestId: 'request-a',
          deviceId: 'device-a',
          tenantDisplayName:
              'Espacio de trabajo / Arbeitsbereich con un nombre muy largo',
          deviceName: 'iPhone profesional mit einem sehr langen Namen',
          platform: 'ios',
          requesterNote:
              'Solicitud de emparejamiento detallada / ausführliche Kopplungsanfrage.',
          status: 'pending',
          requestedAt: DateTime.utc(2026, 8, 25, 14, 30),
          decidedAt: null,
          decidedByUserId: '',
          decisionNote: '',
          enrollmentId: '',
        );

        await tester.pumpWidget(
          OpenIrnLocalizationScope(
            controller: OpenIrnLocalizations.instance,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: MediaQuery(
                    data: const MediaQueryData(
                      size: Size(390, 844),
                      textScaler: TextScaler.linear(1.2),
                    ),
                    child: EnrollmentRequestCard(
                      request: request,
                      working: false,
                      onApprove: () => approved = true,
                      onReject: () => rejected = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final approveLabel = OpenIrnLocalizations.instance.tr('common.approve');
        final rejectLabel = OpenIrnLocalizations.instance.tr('common.reject');
        expect(tester.takeException(), isNull);
        expect(find.text(approveLabel), findsOneWidget);
        expect(find.text(rejectLabel), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(approveLabel)).dy,
          greaterThan(tester.getBottomLeft(find.textContaining('iOS')).dy),
        );

        await tester.tap(find.text(approveLabel));
        await tester.tap(find.text(rejectLabel));
        expect(approved, isTrue);
        expect(rejected, isTrue);
      },
    );
  }
}
