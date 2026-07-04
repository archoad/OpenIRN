-- Example MariaDB bootstrap for OpenIRN.
-- Run as a MariaDB administrator, then replace the password and restrict the host.

CREATE DATABASE IF NOT EXISTS openirn
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'openirn_api'@'localhost'
    IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP
    ON openirn.* TO 'openirn_api'@'localhost';

FLUSH PRIVILEGES;
