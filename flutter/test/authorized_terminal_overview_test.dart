import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/authorized_device.dart';
import 'package:openirn/domain/models/authorized_terminal_overview.dart';
import 'package:openirn/domain/models/device_enrollment_request.dart';

void main() {
  test('combines a consumed request with its authorized device', () {
    final device = _device(deviceId: 'device-a', enrollmentId: 'enrollment-a');
    final request = _request(
      requestId: 'request-a',
      deviceId: 'device-a',
      enrollmentId: 'enrollment-a',
      status: 'consumed',
      requestedAt: DateTime.utc(2026, 9, 10, 10),
    );

    final overviews = AuthorizedTerminalOverview.combine(
      devices: [device],
      requests: [request],
    );

    expect(overviews, hasLength(1));
    expect(overviews.single.device, same(device));
    expect(overviews.single.request, same(request));
    expect(overviews.single.requestCount, 1);
  });

  test('keeps the pending request when a device has request history', () {
    final consumed = _request(
      requestId: 'request-consumed',
      deviceId: 'device-a',
      enrollmentId: 'enrollment-a',
      status: 'consumed',
      requestedAt: DateTime.utc(2026, 9, 10, 11),
    );
    final pending = _request(
      requestId: 'request-pending',
      deviceId: 'device-a',
      enrollmentId: '',
      status: 'pending',
      requestedAt: DateTime.utc(2026, 9, 10, 10),
    );

    final overview = AuthorizedTerminalOverview.combine(
      devices: [_device(deviceId: 'device-a', enrollmentId: 'enrollment-a')],
      requests: [consumed, pending],
    ).single;

    expect(overview.request?.requestId, 'request-pending');
    expect(overview.requestCount, 2);
    expect(overview.hasPendingRequest, isTrue);
  });

  test('uses the enrollment identifier when matching legacy device data', () {
    final overview = AuthorizedTerminalOverview.combine(
      devices: [_device(deviceId: 'device-a', enrollmentId: 'enrollment-a')],
      requests: [
        _request(
          requestId: 'request-a',
          deviceId: '',
          enrollmentId: 'enrollment-a',
          status: 'consumed',
          requestedAt: DateTime.utc(2026, 9, 10, 10),
        ),
      ],
    ).single;

    expect(overview.device?.deviceId, 'device-a');
    expect(overview.request?.requestId, 'request-a');
  });
}

AuthorizedDevice _device({
  required String deviceId,
  required String enrollmentId,
}) {
  return AuthorizedDevice(
    tenantId: 'tenant-a',
    deviceId: deviceId,
    tenantDisplayName: 'Espace A',
    name: 'Portable Alice',
    platform: 'windows',
    status: 'active',
    createdAt: DateTime.utc(2026, 9, 10, 10, 5),
    lastSeenAt: DateTime.utc(2026, 9, 10, 10, 10),
    revokedAt: null,
    invitedByUserId: 'admin-a',
    enrollmentId: enrollmentId,
  );
}

DeviceEnrollmentRequest _request({
  required String requestId,
  required String deviceId,
  required String enrollmentId,
  required String status,
  required DateTime requestedAt,
}) {
  return DeviceEnrollmentRequest(
    tenantId: 'tenant-a',
    requestId: requestId,
    deviceId: deviceId,
    tenantDisplayName: 'Espace A',
    deviceName: 'Portable Alice',
    platform: 'windows',
    requesterEmail: 'alice@example.test',
    requesterNote: '',
    status: status,
    requestedAt: requestedAt,
    decidedAt: status == 'pending' ? null : requestedAt,
    decidedByUserId: status == 'pending' ? '' : 'admin-a',
    decisionNote: '',
    enrollmentId: enrollmentId,
  );
}
