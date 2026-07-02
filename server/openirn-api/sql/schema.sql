-- OpenIRN API SQLite schema
-- Target: replace JSON files under /var/lib/openirn-api with an auditable SQLite store.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS tenants (
    id TEXT PRIMARY KEY,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    display_name TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    permanent INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS users (
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    first_name TEXT NOT NULL DEFAULT '',
    last_name TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL DEFAULT 'reader',
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    PRIMARY KEY (tenant_id, user_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_users_tenant_active_role
    ON users(tenant_id, active, role);

CREATE TABLE IF NOT EXISTS user_credentials (
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    algorithm TEXT NOT NULL DEFAULT 'pbkdf2_sha256',
    iterations INTEGER NOT NULL,
    salt TEXT NOT NULL,
    pin_hash TEXT NOT NULL,
    requires_change INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, user_id),
    FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_snapshots (
    tenant_id TEXT NOT NULL,
    server_sync_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    received_at TEXT NOT NULL,
    payload_sha256 TEXT NOT NULL,
    campaign_count INTEGER NOT NULL DEFAULT 0,
    payload_json TEXT NOT NULL,
    envelope_json TEXT NOT NULL,
    PRIMARY KEY (tenant_id, server_sync_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_snapshots_tenant_received
    ON sync_snapshots(tenant_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_snapshots_tenant_device_received
    ON sync_snapshots(tenant_id, device_id, received_at DESC);

CREATE TABLE IF NOT EXISTS campaign_states (
    tenant_id TEXT NOT NULL,
    campaign_id TEXT NOT NULL,
    server_revision INTEGER NOT NULL DEFAULT 1,
    server_sync_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    payload_sha256 TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    conflict_policy TEXT NOT NULL DEFAULT 'last_write_wins',
    PRIMARY KEY (tenant_id, campaign_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_campaign_states_tenant_updated
    ON campaign_states(tenant_id, updated_at DESC, received_at DESC);

CREATE TABLE IF NOT EXISTS campaign_revisions (
    tenant_id TEXT NOT NULL,
    campaign_id TEXT NOT NULL,
    server_revision INTEGER NOT NULL,
    server_sync_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    payload_sha256 TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    conflict_policy TEXT NOT NULL DEFAULT 'last_write_wins',
    conflict_detected INTEGER NOT NULL DEFAULT 0,
    conflict_reason TEXT,
    PRIMARY KEY (tenant_id, campaign_id, server_revision),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_campaign_revisions_tenant_campaign_received
    ON campaign_revisions(tenant_id, campaign_id, received_at DESC);



CREATE TABLE IF NOT EXISTS authorized_devices (
    tenant_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    name TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    token_hash TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL,
    last_seen_at TEXT,
    revoked_at TEXT,
    invited_by_user_id TEXT,
    enrollment_id TEXT,
    PRIMARY KEY (tenant_id, device_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_authorized_devices_tenant_status
    ON authorized_devices(tenant_id, status, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS device_enrollment_codes (
    tenant_id TEXT NOT NULL,
    enrollment_id TEXT NOT NULL,
    code_hash TEXT NOT NULL UNIQUE,
    created_by_user_id TEXT,
    label TEXT NOT NULL DEFAULT '',
    expires_at TEXT NOT NULL,
    consumed_at TEXT,
    consumed_by_device_id TEXT,
    created_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, enrollment_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_device_enrollment_codes_tenant_expires
    ON device_enrollment_codes(tenant_id, expires_at DESC);


CREATE TABLE IF NOT EXISTS api_sessions (
    tenant_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    device_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    last_seen_at TEXT,
    revoked_at TEXT,
    PRIMARY KEY (tenant_id, session_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_api_sessions_tenant_device_expires
    ON api_sessions(tenant_id, device_id, expires_at DESC);

CREATE TABLE IF NOT EXISTS auth_attempts (
    tenant_id TEXT NOT NULL,
    attempt_id TEXT NOT NULL,
    device_id TEXT NOT NULL DEFAULT '',
    user_id TEXT NOT NULL DEFAULT '',
    ip_address TEXT NOT NULL DEFAULT '',
    successful INTEGER NOT NULL DEFAULT 0,
    reason TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, attempt_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_auth_attempts_tenant_device_created
    ON auth_attempts(tenant_id, device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_attempts_tenant_user_created
    ON auth_attempts(tenant_id, user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_attempts_tenant_ip_created
    ON auth_attempts(tenant_id, ip_address, created_at DESC);

CREATE TABLE IF NOT EXISTS device_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL,
    device_id TEXT,
    event_type TEXT NOT NULL,
    created_at TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_device_audit_log_tenant_created
    ON device_audit_log(tenant_id, created_at DESC);


CREATE TABLE IF NOT EXISTS official_referentials (
    tenant_id TEXT NOT NULL,
    referential_id TEXT NOT NULL,
    version TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    source_url TEXT NOT NULL,
    project_path TEXT NOT NULL,
    default_branch TEXT NOT NULL,
    file_path TEXT NOT NULL,
    source_blob_id TEXT NOT NULL DEFAULT '',
    source_sha256 TEXT NOT NULL,
    canonical_sha256 TEXT NOT NULL,
    downloaded_at TEXT NOT NULL,
    imported_at TEXT NOT NULL,
    pillar_count INTEGER NOT NULL DEFAULT 0,
    criterion_count INTEGER NOT NULL DEFAULT 0,
    import_warnings_json TEXT NOT NULL DEFAULT '[]',
    validation_report_json TEXT NOT NULL DEFAULT '{}',
    payload_json TEXT NOT NULL,
    PRIMARY KEY (tenant_id, referential_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_official_referentials_tenant_active
    ON official_referentials(tenant_id, active, imported_at DESC);


CREATE TABLE IF NOT EXISTS official_referential_history (
    tenant_id TEXT NOT NULL,
    history_id TEXT NOT NULL,
    referential_id TEXT NOT NULL,
    version TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 0,
    source_url TEXT NOT NULL,
    project_path TEXT NOT NULL,
    default_branch TEXT NOT NULL,
    file_path TEXT NOT NULL,
    source_blob_id TEXT NOT NULL DEFAULT '',
    source_sha256 TEXT NOT NULL,
    canonical_sha256 TEXT NOT NULL,
    downloaded_at TEXT NOT NULL,
    imported_at TEXT NOT NULL,
    pillar_count INTEGER NOT NULL DEFAULT 0,
    criterion_count INTEGER NOT NULL DEFAULT 0,
    triggered_by_user_id TEXT NOT NULL DEFAULT '',
    import_warnings_json TEXT NOT NULL DEFAULT '[]',
    validation_report_json TEXT NOT NULL DEFAULT '{}',
    payload_json TEXT NOT NULL,
    PRIMARY KEY (tenant_id, history_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_official_referential_history_tenant_imported
    ON official_referential_history(tenant_id, imported_at DESC, history_id DESC);
CREATE INDEX IF NOT EXISTS idx_official_referential_history_tenant_active
    ON official_referential_history(tenant_id, active, imported_at DESC);

CREATE TABLE IF NOT EXISTS sync_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    server_sync_id TEXT,
    campaign_id TEXT,
    device_id TEXT,
    created_at TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_events_tenant_created
    ON sync_events(tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS backup_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL DEFAULT 'default',
    backup_name TEXT NOT NULL DEFAULT '',
    event_type TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    triggered_by_user_id TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    sha256 TEXT NOT NULL DEFAULT '',
    size_bytes INTEGER NOT NULL DEFAULT 0,
    payload_json TEXT NOT NULL DEFAULT '{}',
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_backup_audit_log_tenant_created
    ON backup_audit_log(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_backup_audit_log_tenant_reason_created
    ON backup_audit_log(tenant_id, reason, created_at DESC);

INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (1, 'initial_sqlite_sync_store');
INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (2, 'device_enrollment_store');
INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (3, 'official_referential_store');
INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (4, 'api_session_store');
INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (5, 'auth_attempt_rate_limit_store');
INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (6, 'official_referential_history_store');
INSERT OR IGNORE INTO schema_migrations(version, name)
VALUES (7, 'backup_audit_log_store');

