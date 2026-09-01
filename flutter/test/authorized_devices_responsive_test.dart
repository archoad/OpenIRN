import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/device_enrollment_request.dart';
import 'package:openirn/domain/models/device_enrollment_invitation.dart';
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

  for (final language in OpenIrnLanguage.values) {
    testWidgets(
      'reusable invitation controls fit on a phone in ${language.code}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await OpenIrnLocalizations.instance.setLanguage(
          language,
          persist: false,
        );

        var revoked = false;
        final invitation = DeviceEnrollmentInvitation(
          tenantId: 'tenant-a',
          tenantDisplayName: 'Certification workspace with a long name',
          enrollmentId: 'enrollment-certification',
          label: 'Microsoft Store certification reusable invitation',
          mode: 'reusable_until_revoked',
          status: 'active',
          createdByUserId: 'administrator-a',
          createdAt: DateTime.utc(2026, 9, 1, 10),
          expiresAt: null,
          maxActiveDevices: 10,
          activeDeviceCount: 2,
          useCount: 3,
          lastUsedAt: DateTime.utc(2026, 9, 1, 11),
          revokedAt: null,
          revokedByUserId: '',
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
                    child: ReusableEnrollmentInvitationCard(
                      invitation: invitation,
                      working: false,
                      canRevoke: true,
                      onRevoke: () => revoked = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final revokeLabel = OpenIrnLocalizations.instance.tr(
          'authorized_devices.invitations.revoke',
        );
        expect(tester.takeException(), isNull);
        expect(find.text(revokeLabel), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(revokeLabel)).dy,
          greaterThan(
            tester.getBottomLeft(find.textContaining('Microsoft Store')).dy,
          ),
        );

        await tester.tap(find.text(revokeLabel));
        expect(revoked, isTrue);
      },
    );
  }
}
