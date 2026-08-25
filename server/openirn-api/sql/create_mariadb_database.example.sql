-- Example MariaDB bootstrap for OpenIRN.
-- Run as a MariaDB administrator, replace both passwords and restrict the host.

CREATE DATABASE IF NOT EXISTS openirn
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'openirn_runtime'@'localhost'
    IDENTIFIED BY 'CHANGE_ME_RUNTIME_PASSWORD';

CREATE USER IF NOT EXISTS 'openirn_migration'@'localhost'
    IDENTIFIED BY 'CHANGE_ME_MIGRATION_PASSWORD';

GRANT SELECT, INSERT, UPDATE, DELETE
    ON openirn.* TO 'openirn_runtime'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
    ON openirn.* TO 'openirn_migration'@'localhost';

FLUSH PRIVILEGES;
