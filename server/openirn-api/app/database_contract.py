from __future__ import annotations


REQUIRED_TABLES = (
    "schema_migrations",
    "tenants",
    "users",
    "user_credentials",
    "sync_snapshots",
    "campaign_states",
    "campaign_revisions",
    "critical_functions",
    "information_systems",
    "information_assets",
    "terminals",
    "authorized_devices",
    "device_enrollment_requests",
    "device_enrollment_codes",
    "api_sessions",
    "auth_attempts",
    "api_rate_limit_buckets",
    "device_audit_log",
    "official_referentials",
    "official_referential_history",
    "sync_events",
    "backup_audit_log",
    "id_aliases",
)

REQUIRED_MIGRATIONS = {
    156: "uuid_entity_ids_runtime_migration",
    161: "delete_legacy_revoked_authorized_devices",
    167: "authorized_device_unique_identity_view",
    168: "terminal_identity_table",
    169: "invalidate_legacy_default_pins",
    170: "enrollment_anti_abuse_rate_limit_buckets",
    171: "reusable_enrollment_invitations",
}

RUNTIME_REQUIRED_PRIVILEGES = frozenset({"SELECT", "INSERT", "UPDATE", "DELETE"})
RUNTIME_FORBIDDEN_PRIVILEGES = frozenset(
    {
        "ALL PRIVILEGES",
        "ALTER",
        "CREATE",
        "CREATE ROUTINE",
        "CREATE TEMPORARY TABLES",
        "CREATE VIEW",
        "DROP",
        "EVENT",
        "EXECUTE",
        "INDEX",
        "REFERENCES",
        "TRIGGER",
    }
)
