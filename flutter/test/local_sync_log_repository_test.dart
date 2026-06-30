import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_sync_log_repository.dart';
import 'package:openirn/domain/models/sync_log_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await const LocalSyncLogRepository().clear();
  });

  test('stores sync log events newest first', () async {
    const repository = LocalSyncLogRepository();

    await repository.appendEvent(
      SyncLogEvent.create(
        type: SyncLogEventType.pushSucceeded,
        tenantId: 'archoad',
        deviceId: 'device-a',
        title: 'Push OK',
        message: 'Snapshot envoyé.',
        serverSyncId: 'sync-1',
        campaignCount: 2,
        now: DateTime.utc(2026, 6, 24, 10),
      ),
    );
    await repository.appendEvent(
      SyncLogEvent.create(
        type: SyncLogEventType.pullSucceeded,
        tenantId: 'archoad',
        deviceId: 'device-a',
        title: 'Pull OK',
        message: 'Snapshots récupérés.',
        snapshotCount: 3,
        now: DateTime.utc(2026, 6, 24, 11),
      ),
    );

    final events = await repository.loadEvents();

    expect(events, hasLength(2));
    expect(events.first.type, SyncLogEventType.pullSucceeded);
    expect(events.last.type, SyncLogEventType.pushSucceeded);
    expect(events.last.serverSyncId, 'sync-1');
  });

  test('clear removes events', () async {
    const repository = LocalSyncLogRepository();
    await repository.appendEvent(
      SyncLogEvent.create(
        type: SyncLogEventType.connectionTest,
        tenantId: 'archoad',
        deviceId: 'device-a',
        title: 'Test',
        message: 'OK',
      ),
    );

    await repository.clear();

    expect(await repository.loadEvents(), isEmpty);
  });
}
