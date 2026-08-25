-- OpenIRN API MariaDB schema
-- MariaDB is the only supported server database backend.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version INT NOT NULL,
    name VARCHAR(191) NOT NULL,
    applied_at VARCHAR(40) NOT NULL DEFAULT '',
    PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR(80) NOT NULL,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    display_name VARCHAR(255) NOT NULL DEFAULT '',
    description TEXT NOT NULL,
    permanent TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
    tenant_id VARCHAR(80) NOT NULL,
    user_id VARCHAR(160) NOT NULL,
    first_name VARCHAR(255) NOT NULL DEFAULT '',
    last_name VARCHAR(255) NOT NULL DEFAULT '',
    email VARCHAR(255) NOT NULL DEFAULT '',
    role VARCHAR(64) NOT NULL DEFAULT 'reader',
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    PRIMARY KEY (tenant_id, user_id),
    KEY idx_users_tenant_active_role (tenant_id, active, role),
    CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_credentials (
    tenant_id VARCHAR(80) NOT NULL,
    user_id VARCHAR(160) NOT NULL,
    algorithm VARCHAR(64) NOT NULL DEFAULT 'pbkdf2_sha256',
    iterations INT NOT NULL,
    salt VARCHAR(191) NOT NULL,
    pin_hash VARCHAR(191) NOT NULL,
    requires_change TINYINT(1) NOT NULL DEFAULT 0,
    updated_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, user_id),
    CONSTRAINT fk_user_credentials_user FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sync_snapshots (
    tenant_id VARCHAR(80) NOT NULL,
    server_sync_id VARCHAR(160) NOT NULL,
    device_id VARCHAR(160) NOT NULL,
    received_at VARCHAR(40) NOT NULL,
    payload_sha256 VARCHAR(64) NOT NULL,
    campaign_count INT NOT NULL DEFAULT 0,
    payload_json LONGTEXT NOT NULL,
    envelope_json LONGTEXT NOT NULL,
    PRIMARY KEY (tenant_id, server_sync_id),
    KEY idx_sync_snapshots_tenant_received (tenant_id, received_at),
    KEY idx_sync_snapshots_tenant_device_received (tenant_id, device_id, received_at),
    CONSTRAINT fk_sync_snapshots_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS campaign_states (
    tenant_id VARCHAR(80) NOT NULL,
    campaign_id VARCHAR(160) NOT NULL,
    server_revision INT NOT NULL DEFAULT 1,
    server_sync_id VARCHAR(160) NOT NULL,
    device_id VARCHAR(160) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    received_at VARCHAR(40) NOT NULL,
    payload_sha256 VARCHAR(64) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    conflict_policy VARCHAR(64) NOT NULL DEFAULT 'last_write_wins',
    PRIMARY KEY (tenant_id, campaign_id),
    KEY idx_campaign_states_tenant_updated (tenant_id, updated_at, received_at),
    CONSTRAINT fk_campaign_states_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS campaign_revisions (
    tenant_id VARCHAR(80) NOT NULL,
    campaign_id VARCHAR(160) NOT NULL,
    server_revision INT NOT NULL,
    server_sync_id VARCHAR(160) NOT NULL,
    device_id VARCHAR(160) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    received_at VARCHAR(40) NOT NULL,
    payload_sha256 VARCHAR(64) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    conflict_policy VARCHAR(64) NOT NULL DEFAULT 'last_write_wins',
    conflict_detected TINYINT(1) NOT NULL DEFAULT 0,
    conflict_reason TEXT NULL,
    PRIMARY KEY (tenant_id, campaign_id, server_revision),
    KEY idx_campaign_revisions_tenant_campaign_received (tenant_id, campaign_id, received_at),
    CONSTRAINT fk_campaign_revisions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS critical_functions (
    tenant_id VARCHAR(80) NOT NULL,
    function_id VARCHAR(160) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    description TEXT NOT NULL,
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, function_id),
    KEY idx_critical_functions_tenant_name (tenant_id, name),
    CONSTRAINT fk_critical_functions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS information_systems (
    tenant_id VARCHAR(80) NOT NULL,
    system_id VARCHAR(160) NOT NULL,
    function_id VARCHAR(160) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    description TEXT NOT NULL,
    owner VARCHAR(255) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, system_id),
    KEY idx_information_systems_tenant_function (tenant_id, function_id),
    KEY idx_information_systems_tenant_name (tenant_id, name),
    CONSTRAINT fk_information_systems_function FOREIGN KEY (tenant_id, function_id) REFERENCES critical_functions(tenant_id, function_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS information_assets (
    tenant_id VARCHAR(80) NOT NULL,
    asset_id VARCHAR(160) NOT NULL,
    system_id VARCHAR(160) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    asset_type VARCHAR(120) NOT NULL DEFAULT '',
    description TEXT NOT NULL,
    criticality VARCHAR(80) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, asset_id),
    KEY idx_information_assets_tenant_system (tenant_id, system_id),
    KEY idx_information_assets_tenant_name (tenant_id, name),
    CONSTRAINT fk_information_assets_system FOREIGN KEY (tenant_id, system_id) REFERENCES information_systems(tenant_id, system_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS terminals (
    device_id VARCHAR(160) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    platform VARCHAR(64) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    updated_at VARCHAR(40) NOT NULL,
    last_seen_at VARCHAR(40) NULL,
    PRIMARY KEY (device_id),
    KEY idx_terminals_updated (updated_at),
    KEY idx_terminals_last_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS authorized_devices (
    tenant_id VARCHAR(80) NOT NULL,
    device_id VARCHAR(160) NOT NULL,
    name VARCHAR(255) NOT NULL,
    platform VARCHAR(64) NOT NULL DEFAULT '',
    token_hash VARCHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at VARCHAR(40) NOT NULL,
    last_seen_at VARCHAR(40) NULL,
    revoked_at VARCHAR(40) NULL,
    invited_by_user_id VARCHAR(160) NULL,
    enrollment_id VARCHAR(160) NULL,
    PRIMARY KEY (tenant_id, device_id),
    UNIQUE KEY uq_authorized_devices_token_hash (token_hash),
    KEY idx_authorized_devices_tenant_status (tenant_id, status, last_seen_at),
    KEY idx_authorized_devices_device_identity (device_id, status, last_seen_at),
    CONSTRAINT fk_authorized_devices_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_enrollment_requests (
    tenant_id VARCHAR(80) NOT NULL,
    request_id VARCHAR(160) NOT NULL,
    device_id VARCHAR(160) NOT NULL DEFAULT '',
    device_name VARCHAR(255) NOT NULL DEFAULT '',
    platform VARCHAR(64) NOT NULL DEFAULT '',
    requester_note TEXT NOT NULL,
    requester_ip VARCHAR(80) NOT NULL DEFAULT '',
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    requested_at VARCHAR(40) NOT NULL,
    decided_at VARCHAR(40) NULL,
    decided_by_user_id VARCHAR(160) NULL,
    decision_note TEXT NOT NULL,
    enrollment_id VARCHAR(160) NULL,
    PRIMARY KEY (tenant_id, request_id),
    KEY idx_device_enrollment_requests_tenant_status (tenant_id, status, requested_at),
    CONSTRAINT fk_device_enrollment_requests_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_enrollment_codes (
    tenant_id VARCHAR(80) NOT NULL,
    enrollment_id VARCHAR(160) NOT NULL,
    code_hash VARCHAR(64) NOT NULL,
    created_by_user_id VARCHAR(160) NULL,
    label VARCHAR(255) NOT NULL DEFAULT '',
    expires_at VARCHAR(40) NOT NULL,
    consumed_at VARCHAR(40) NULL,
    consumed_by_device_id VARCHAR(160) NULL,
    created_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, enrollment_id),
    UNIQUE KEY uq_device_enrollment_codes_code_hash (code_hash),
    KEY idx_device_enrollment_codes_tenant_expires (tenant_id, expires_at),
    CONSTRAINT fk_device_enrollment_codes_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS api_sessions (
    tenant_id VARCHAR(80) NOT NULL,
    session_id VARCHAR(160) NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    device_id VARCHAR(160) NOT NULL,
    user_id VARCHAR(160) NOT NULL,
    created_at VARCHAR(40) NOT NULL,
    expires_at VARCHAR(40) NOT NULL,
    last_seen_at VARCHAR(40) NULL,
    revoked_at VARCHAR(40) NULL,
    PRIMARY KEY (tenant_id, session_id),
    UNIQUE KEY uq_api_sessions_token_hash (token_hash),
    KEY idx_api_sessions_tenant_device_expires (tenant_id, device_id, expires_at),
    CONSTRAINT fk_api_sessions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS auth_attempts (
    tenant_id VARCHAR(80) NOT NULL,
    attempt_id VARCHAR(160) NOT NULL,
    device_id VARCHAR(160) NOT NULL DEFAULT '',
    user_id VARCHAR(160) NOT NULL DEFAULT '',
    ip_address VARCHAR(80) NOT NULL DEFAULT '',
    successful TINYINT(1) NOT NULL DEFAULT 0,
    reason VARCHAR(160) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, attempt_id),
    KEY idx_auth_attempts_tenant_device_created (tenant_id, device_id, created_at),
    KEY idx_auth_attempts_tenant_user_created (tenant_id, user_id, created_at),
    KEY idx_auth_attempts_tenant_ip_created (tenant_id, ip_address, created_at),
    CONSTRAINT fk_auth_attempts_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS api_rate_limit_buckets (
    tenant_id VARCHAR(80) NOT NULL,
    scope VARCHAR(80) NOT NULL,
    subject_hash VARCHAR(64) NOT NULL,
    window_started_at VARCHAR(40) NOT NULL,
    request_count INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at VARCHAR(40) NOT NULL,
    PRIMARY KEY (tenant_id, scope, subject_hash, window_started_at),
    KEY idx_api_rate_limit_buckets_updated (updated_at),
    CONSTRAINT fk_api_rate_limit_buckets_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_audit_log (
    id BIGINT NOT NULL AUTO_INCREMENT,
    tenant_id VARCHAR(80) NOT NULL,
    device_id VARCHAR(160) NULL,
    event_type VARCHAR(160) NOT NULL,
    created_at VARCHAR(40) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    PRIMARY KEY (id),
    KEY idx_device_audit_log_tenant_created (tenant_id, created_at),
    CONSTRAINT fk_device_audit_log_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS official_referentials (
    tenant_id VARCHAR(80) NOT NULL,
    referential_id VARCHAR(160) NOT NULL,
    version VARCHAR(191) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    source_url TEXT NOT NULL,
    project_path VARCHAR(255) NOT NULL,
    default_branch VARCHAR(191) NOT NULL,
    file_path VARCHAR(512) NOT NULL,
    source_blob_id VARCHAR(191) NOT NULL DEFAULT '',
    source_sha256 VARCHAR(64) NOT NULL,
    canonical_sha256 VARCHAR(64) NOT NULL,
    downloaded_at VARCHAR(40) NOT NULL,
    imported_at VARCHAR(40) NOT NULL,
    pillar_count INT NOT NULL DEFAULT 0,
    criterion_count INT NOT NULL DEFAULT 0,
    import_warnings_json LONGTEXT NOT NULL,
    validation_report_json LONGTEXT NOT NULL,
    payload_json LONGTEXT NOT NULL,
    PRIMARY KEY (tenant_id, referential_id),
    KEY idx_official_referentials_tenant_active (tenant_id, active, imported_at),
    CONSTRAINT fk_official_referentials_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS official_referential_history (
    tenant_id VARCHAR(80) NOT NULL,
    history_id VARCHAR(160) NOT NULL,
    referential_id VARCHAR(160) NOT NULL,
    version VARCHAR(191) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 0,
    source_url TEXT NOT NULL,
    project_path VARCHAR(255) NOT NULL,
    default_branch VARCHAR(191) NOT NULL,
    file_path VARCHAR(512) NOT NULL,
    source_blob_id VARCHAR(191) NOT NULL DEFAULT '',
    source_sha256 VARCHAR(64) NOT NULL,
    canonical_sha256 VARCHAR(64) NOT NULL,
    downloaded_at VARCHAR(40) NOT NULL,
    imported_at VARCHAR(40) NOT NULL,
    pillar_count INT NOT NULL DEFAULT 0,
    criterion_count INT NOT NULL DEFAULT 0,
    triggered_by_user_id VARCHAR(160) NOT NULL DEFAULT '',
    import_warnings_json LONGTEXT NOT NULL,
    validation_report_json LONGTEXT NOT NULL,
    payload_json LONGTEXT NOT NULL,
    PRIMARY KEY (tenant_id, history_id),
    KEY idx_official_referential_history_tenant_imported (tenant_id, imported_at, history_id),
    KEY idx_official_referential_history_tenant_active (tenant_id, active, imported_at),
    CONSTRAINT fk_official_referential_history_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sync_events (
    id BIGINT NOT NULL AUTO_INCREMENT,
    tenant_id VARCHAR(80) NOT NULL,
    event_type VARCHAR(160) NOT NULL,
    -- Historique : certaines lignes anciennes de sync_events peuvent
    -- contenir des identifiants non normalisés plus longs que les UUID actuels.
    -- Ces colonnes ne sont pas indexées : on les conserve en LONGTEXT pour
    -- préserver intégralement les journaux historiques.
    server_sync_id LONGTEXT NULL,
    campaign_id LONGTEXT NULL,
    device_id LONGTEXT NULL,
    created_at VARCHAR(40) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    PRIMARY KEY (id),
    KEY idx_sync_events_tenant_created (tenant_id, created_at),
    CONSTRAINT fk_sync_events_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS backup_audit_log (
    id BIGINT NOT NULL AUTO_INCREMENT,
    tenant_id VARCHAR(80) NOT NULL DEFAULT 'default',
    backup_name VARCHAR(255) NOT NULL DEFAULT '',
    event_type VARCHAR(160) NOT NULL,
    reason VARCHAR(160) NOT NULL DEFAULT '',
    triggered_by_user_id VARCHAR(160) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL,
    sha256 VARCHAR(64) NOT NULL DEFAULT '',
    size_bytes BIGINT NOT NULL DEFAULT 0,
    payload_json LONGTEXT NOT NULL,
    PRIMARY KEY (id),
    KEY idx_backup_audit_log_tenant_created (tenant_id, created_at),
    KEY idx_backup_audit_log_tenant_reason_created (tenant_id, reason, created_at),
    CONSTRAINT fk_backup_audit_log_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS id_aliases (
    entity_type VARCHAR(80) NOT NULL,
    scope_id VARCHAR(160) NOT NULL DEFAULT '',
    old_id VARCHAR(191) NOT NULL,
    new_id VARCHAR(191) NOT NULL,
    created_at VARCHAR(40) NOT NULL DEFAULT '',
    PRIMARY KEY (entity_type, scope_id, old_id),
    KEY idx_id_aliases_new_id (entity_type, scope_id, new_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
