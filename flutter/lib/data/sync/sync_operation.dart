enum SyncStatus { localOnly, pendingPush, synced, conflict, rejected }

enum SyncOperationType { upsert, delete }

class SyncOperation {
  final String id;
  final String entityType;
  final String entityId;
  final SyncOperationType operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  const SyncOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
  });
}
