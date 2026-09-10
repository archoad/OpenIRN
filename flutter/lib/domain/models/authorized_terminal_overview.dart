import 'authorized_device.dart';
import 'device_enrollment_request.dart';

class AuthorizedTerminalOverview {
  final AuthorizedDevice? device;
  final DeviceEnrollmentRequest? request;
  final int requestCount;

  const AuthorizedTerminalOverview({
    required this.device,
    required this.request,
    required this.requestCount,
  });

  bool get hasPendingRequest => request?.isPending ?? false;

  String get deviceId =>
      device?.deviceId.trim() ?? request?.deviceId.trim() ?? '';

  DateTime? get latestActivity {
    final dates = <DateTime>[
      if (request?.requestedAt != null) request!.requestedAt!,
      if (device?.lastSeenAt != null) device!.lastSeenAt!,
      if (device?.createdAt != null) device!.createdAt!,
    ];
    if (dates.isEmpty) {
      return null;
    }
    return dates.reduce(
      (latest, value) => value.isAfter(latest) ? value : latest,
    );
  }

  static List<AuthorizedTerminalOverview> combine({
    required List<AuthorizedDevice> devices,
    required List<DeviceEnrollmentRequest> requests,
  }) {
    final builders = <_AuthorizedTerminalOverviewBuilder>[];
    final byDeviceId = <String, _AuthorizedTerminalOverviewBuilder>{};
    final byEnrollmentId = <String, _AuthorizedTerminalOverviewBuilder>{};

    for (final device in devices) {
      final builder = _AuthorizedTerminalOverviewBuilder(device: device);
      builders.add(builder);
      final deviceId = device.deviceId.trim();
      if (deviceId.isNotEmpty) {
        byDeviceId[deviceId] = builder;
      }
      final enrollmentId = device.enrollmentId.trim();
      if (enrollmentId.isNotEmpty) {
        byEnrollmentId[enrollmentId] = builder;
      }
    }

    for (final request in requests) {
      final deviceId = request.deviceId.trim();
      final enrollmentId = request.enrollmentId.trim();
      var builder = deviceId.isEmpty ? null : byDeviceId[deviceId];
      builder ??= enrollmentId.isEmpty ? null : byEnrollmentId[enrollmentId];
      if (builder == null) {
        builder = _AuthorizedTerminalOverviewBuilder();
        builders.add(builder);
        if (deviceId.isNotEmpty) {
          byDeviceId[deviceId] = builder;
        }
        if (enrollmentId.isNotEmpty) {
          byEnrollmentId[enrollmentId] = builder;
        }
      }
      builder.addRequest(request);
    }

    final result = builders
        .map((builder) => builder.build())
        .toList(growable: false);
    result.sort((left, right) {
      final priorityComparison = _priority(left).compareTo(_priority(right));
      if (priorityComparison != 0) {
        return priorityComparison;
      }
      final leftActivity = left.latestActivity;
      final rightActivity = right.latestActivity;
      if (leftActivity != null && rightActivity != null) {
        final activityComparison = rightActivity.compareTo(leftActivity);
        if (activityComparison != 0) {
          return activityComparison;
        }
      } else if (leftActivity != null) {
        return -1;
      } else if (rightActivity != null) {
        return 1;
      }
      return left.deviceId.compareTo(right.deviceId);
    });
    return result;
  }

  static int _priority(AuthorizedTerminalOverview overview) {
    if (overview.hasPendingRequest) {
      return 0;
    }
    if (overview.device?.isActive ?? false) {
      return 1;
    }
    if (overview.device != null) {
      return 2;
    }
    return 3;
  }
}

class _AuthorizedTerminalOverviewBuilder {
  final AuthorizedDevice? device;
  DeviceEnrollmentRequest? request;
  int requestCount = 0;

  _AuthorizedTerminalOverviewBuilder({this.device});

  void addRequest(DeviceEnrollmentRequest candidate) {
    requestCount += 1;
    final current = request;
    if (current == null || _prefer(candidate, current)) {
      request = candidate;
    }
  }

  AuthorizedTerminalOverview build() => AuthorizedTerminalOverview(
    device: device,
    request: request,
    requestCount: requestCount,
  );

  static bool _prefer(
    DeviceEnrollmentRequest candidate,
    DeviceEnrollmentRequest current,
  ) {
    if (candidate.isPending != current.isPending) {
      return candidate.isPending;
    }
    final candidateDate = candidate.requestedAt;
    final currentDate = current.requestedAt;
    if (candidateDate == null) {
      return false;
    }
    if (currentDate == null) {
      return true;
    }
    return candidateDate.isAfter(currentDate);
  }
}
