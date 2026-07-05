-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 5: Database Schema Creation Script
-- MySQL 8.0
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. DATABASE CREATION
-- ----------------------------------------------------------------------------
DROP DATABASE IF EXISTS dems_db;
CREATE DATABASE dems_db
    CHARACTER SET = utf8mb4
    COLLATE = utf8mb4_unicode_ci;

USE dems_db;

-- ============================================================================
-- 1. REFERENCE / LOOKUP TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 departments
-- ----------------------------------------------------------------------------
CREATE TABLE departments (
    department_id       INT UNSIGNED AUTO_INCREMENT,
    department_name     VARCHAR(100)  NOT NULL,
    department_code     VARCHAR(10)   NOT NULL,
    head_investigator_id INT UNSIGNED NULL,   -- FK added later (circular dep with investigators)
    contact_email       VARCHAR(150)  NULL,
    contact_phone       VARCHAR(20)   NULL,
    created_at          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (department_id),
    UNIQUE KEY uq_department_name (department_name),
    UNIQUE KEY uq_department_code (department_code)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 1.2 roles
-- ----------------------------------------------------------------------------
CREATE TABLE roles (
    role_id          INT UNSIGNED AUTO_INCREMENT,
    role_name        VARCHAR(50)   NOT NULL,
    role_description VARCHAR(255) NULL,
    access_level     TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (role_id),
    UNIQUE KEY uq_role_name (role_name),
    CONSTRAINT chk_roles_access_level CHECK (access_level BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 1.3 evidence_categories
-- ----------------------------------------------------------------------------
CREATE TABLE evidence_categories (
    category_id          INT UNSIGNED AUTO_INCREMENT,
    category_name        VARCHAR(80)  NOT NULL,
    category_description VARCHAR(255) NULL,
    PRIMARY KEY (category_id),
    UNIQUE KEY uq_category_name (category_name)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 1.4 evidence_types
-- ----------------------------------------------------------------------------
CREATE TABLE evidence_types (
    type_id          INT UNSIGNED AUTO_INCREMENT,
    category_id      INT UNSIGNED NOT NULL,
    type_name        VARCHAR(80)  NOT NULL,
    type_description VARCHAR(255) NULL,
    PRIMARY KEY (type_id),
    UNIQUE KEY uq_type_per_category (type_name, category_id),
    CONSTRAINT fk_types_category FOREIGN KEY (category_id)
        REFERENCES evidence_categories (category_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 1.5 evidence_status
-- ----------------------------------------------------------------------------
CREATE TABLE evidence_status (
    status_id    INT UNSIGNED AUTO_INCREMENT,
    status_name  VARCHAR(50) NOT NULL,
    status_order TINYINT UNSIGNED NOT NULL,
    is_terminal  TINYINT(1)  NOT NULL DEFAULT 0,
    PRIMARY KEY (status_id),
    UNIQUE KEY uq_status_name (status_name),
    UNIQUE KEY uq_status_order (status_order),
    CONSTRAINT chk_status_terminal CHECK (is_terminal IN (0,1))
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 1.6 storage_locations
-- ----------------------------------------------------------------------------
CREATE TABLE storage_locations (
    location_id          INT UNSIGNED AUTO_INCREMENT,
    department_id        INT UNSIGNED NOT NULL,
    location_code        VARCHAR(20)  NOT NULL,
    location_name        VARCHAR(100) NOT NULL,
    location_type        ENUM('physical','digital') NOT NULL DEFAULT 'physical',
    security_level        TINYINT UNSIGNED NOT NULL DEFAULT 1,
    capacity              INT UNSIGNED NOT NULL DEFAULT 0,
    current_utilization   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (location_id),
    UNIQUE KEY uq_location_code (location_code),
    CONSTRAINT fk_storage_department FOREIGN KEY (department_id)
        REFERENCES departments (department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_storage_security CHECK (security_level BETWEEN 1 AND 5),
    CONSTRAINT chk_storage_capacity CHECK (capacity >= 0),
    CONSTRAINT chk_storage_utilization CHECK (current_utilization <= capacity)
) ENGINE=InnoDB;

-- ============================================================================
-- 2. CORE ENTITY TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 users
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id        INT UNSIGNED AUTO_INCREMENT,
    username       VARCHAR(50)  NOT NULL,
    email          VARCHAR(150) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    role_id        INT UNSIGNED NOT NULL,
    account_status ENUM('active','locked','disabled') NOT NULL DEFAULT 'active',
    last_login     DATETIME NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_username (username),
    UNIQUE KEY uq_email (email),
    CONSTRAINT fk_users_role FOREIGN KEY (role_id)
        REFERENCES roles (role_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 2.2 investigators
-- ----------------------------------------------------------------------------
CREATE TABLE investigators (
    investigator_id  INT UNSIGNED AUTO_INCREMENT,
    user_id          INT UNSIGNED NOT NULL,
    department_id    INT UNSIGNED NOT NULL,
    badge_number     VARCHAR(20)  NOT NULL,
    full_name        VARCHAR(120) NOT NULL,
    rank_designation VARCHAR(60)  NULL,
    specialization   VARCHAR(100) NULL,
    phone            VARCHAR(20)  NULL,
    date_joined      DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (investigator_id),
    UNIQUE KEY uq_investigator_user (user_id),
    UNIQUE KEY uq_badge_number (badge_number),
    CONSTRAINT fk_investigators_user FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_investigators_department FOREIGN KEY (department_id)
        REFERENCES departments (department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Now that investigators exists, add the circular FK on departments
ALTER TABLE departments
    ADD CONSTRAINT fk_departments_head FOREIGN KEY (head_investigator_id)
        REFERENCES investigators (investigator_id)
        ON DELETE SET NULL ON UPDATE CASCADE;

-- ----------------------------------------------------------------------------
-- 2.3 cases
-- ----------------------------------------------------------------------------
CREATE TABLE cases (
    case_id                    INT UNSIGNED AUTO_INCREMENT,
    case_number                VARCHAR(20)  NOT NULL,
    title                      VARCHAR(200) NOT NULL,
    description                TEXT NULL,
    originating_department_id  INT UNSIGNED NOT NULL,
    lead_investigator_id       INT UNSIGNED NOT NULL,
    case_type   ENUM('ransomware','data_breach','fraud','identity_theft',
                      'network_intrusion','child_exploitation','other')
                NOT NULL DEFAULT 'other',
    priority     ENUM('low','medium','high','critical') NOT NULL DEFAULT 'medium',
    case_status  ENUM('open','under_investigation','pending_court','closed','archived')
                 NOT NULL DEFAULT 'open',
    date_opened  DATE NOT NULL DEFAULT (CURRENT_DATE),
    date_closed  DATE NULL,
    PRIMARY KEY (case_id),
    UNIQUE KEY uq_case_number (case_number),
    CONSTRAINT fk_cases_department FOREIGN KEY (originating_department_id)
        REFERENCES departments (department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cases_lead_investigator FOREIGN KEY (lead_investigator_id)
        REFERENCES investigators (investigator_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_case_dates CHECK (date_closed IS NULL OR date_closed >= date_opened)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 2.4 suspects
-- ----------------------------------------------------------------------------
CREATE TABLE suspects (
    suspect_id     INT UNSIGNED AUTO_INCREMENT,
    full_name      VARCHAR(120) NOT NULL,
    alias          VARCHAR(120) NULL,
    national_id    VARCHAR(30)  NULL,
    address        VARCHAR(255) NULL,
    phone          VARCHAR(20)  NULL,
    email          VARCHAR(150) NULL,
    suspect_status ENUM('person_of_interest','charged','cleared','convicted')
                   NOT NULL DEFAULT 'person_of_interest',
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (suspect_id),
    UNIQUE KEY uq_suspect_national_id (national_id)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 2.5 devices
-- ----------------------------------------------------------------------------
CREATE TABLE devices (
    device_id        INT UNSIGNED AUTO_INCREMENT,
    suspect_id       INT UNSIGNED NULL,
    device_type ENUM('laptop','desktop','smartphone','tablet','usb_drive',
                      'external_hdd','server','cloud_account','other')
                NOT NULL DEFAULT 'other',
    make_model       VARCHAR(100) NULL,
    serial_number    VARCHAR(100) NULL,
    seizure_date     DATE NOT NULL DEFAULT (CURRENT_DATE),
    seizure_location VARCHAR(200) NULL,
    condition_notes  VARCHAR(255) NULL,
    PRIMARY KEY (device_id),
    UNIQUE KEY uq_device_serial (serial_number),
    CONSTRAINT fk_devices_suspect FOREIGN KEY (suspect_id)
        REFERENCES suspects (suspect_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 2.6 digital_evidence
-- ----------------------------------------------------------------------------
CREATE TABLE digital_evidence (
    evidence_id         INT UNSIGNED AUTO_INCREMENT,
    evidence_code       VARCHAR(20)  NOT NULL,
    case_id             INT UNSIGNED NOT NULL,
    device_id           INT UNSIGNED NULL,
    type_id             INT UNSIGNED NOT NULL,
    status_id           INT UNSIGNED NOT NULL,
    current_location_id INT UNSIGNED NOT NULL,
    collected_by        INT UNSIGNED NOT NULL,
    file_hash           CHAR(64) NOT NULL,
    file_size_bytes     BIGINT UNSIGNED NOT NULL,
    description         VARCHAR(255) NULL,
    date_collected       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_court_submitted  TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (evidence_id),
    UNIQUE KEY uq_evidence_code (evidence_code),
    UNIQUE KEY uq_evidence_hash (file_hash),
    CONSTRAINT fk_evidence_case FOREIGN KEY (case_id)
        REFERENCES cases (case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_evidence_device FOREIGN KEY (device_id)
        REFERENCES devices (device_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_evidence_type FOREIGN KEY (type_id)
        REFERENCES evidence_types (type_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_evidence_status FOREIGN KEY (status_id)
        REFERENCES evidence_status (status_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_evidence_location FOREIGN KEY (current_location_id)
        REFERENCES storage_locations (location_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_evidence_collector FOREIGN KEY (collected_by)
        REFERENCES investigators (investigator_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_evidence_filesize CHECK (file_size_bytes > 0),
    CONSTRAINT chk_evidence_court_flag CHECK (is_court_submitted IN (0,1))
) ENGINE=InnoDB;

-- ============================================================================
-- 3. JUNCTION TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 case_departments
-- ----------------------------------------------------------------------------
CREATE TABLE case_departments (
    case_id           INT UNSIGNED NOT NULL,
    department_id     INT UNSIGNED NOT NULL,
    involvement_role  ENUM('originating','supporting','transferred') NOT NULL DEFAULT 'supporting',
    date_added        DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (case_id, department_id),
    CONSTRAINT fk_casedept_case FOREIGN KEY (case_id)
        REFERENCES cases (case_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_casedept_department FOREIGN KEY (department_id)
        REFERENCES departments (department_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 3.2 case_investigators
-- ----------------------------------------------------------------------------
CREATE TABLE case_investigators (
    case_id          INT UNSIGNED NOT NULL,
    investigator_id  INT UNSIGNED NOT NULL,
    role_in_case     ENUM('lead','support') NOT NULL DEFAULT 'support',
    date_assigned    DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (case_id, investigator_id),
    CONSTRAINT fk_caseinv_case FOREIGN KEY (case_id)
        REFERENCES cases (case_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_caseinv_investigator FOREIGN KEY (investigator_id)
        REFERENCES investigators (investigator_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 3.3 case_suspects
-- ----------------------------------------------------------------------------
CREATE TABLE case_suspects (
    case_id                 INT UNSIGNED NOT NULL,
    suspect_id              INT UNSIGNED NOT NULL,
    suspect_status_in_case  ENUM('person_of_interest','charged','cleared') NOT NULL DEFAULT 'person_of_interest',
    date_linked             DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (case_id, suspect_id),
    CONSTRAINT fk_casesus_case FOREIGN KEY (case_id)
        REFERENCES cases (case_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_casesus_suspect FOREIGN KEY (suspect_id)
        REFERENCES suspects (suspect_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ============================================================================
-- 4. LOG / AUDIT TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 chain_of_custody
-- ----------------------------------------------------------------------------
CREATE TABLE chain_of_custody (
    custody_id           BIGINT UNSIGNED AUTO_INCREMENT,
    evidence_id          INT UNSIGNED NOT NULL,
    from_investigator_id INT UNSIGNED NULL,
    to_investigator_id   INT UNSIGNED NOT NULL,
    from_location_id     INT UNSIGNED NULL,
    to_location_id       INT UNSIGNED NOT NULL,
    transfer_reason      VARCHAR(255) NOT NULL,
    transfer_timestamp   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    confirmed            TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (custody_id),
    CONSTRAINT fk_custody_evidence FOREIGN KEY (evidence_id)
        REFERENCES digital_evidence (evidence_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_custody_from_investigator FOREIGN KEY (from_investigator_id)
        REFERENCES investigators (investigator_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_custody_to_investigator FOREIGN KEY (to_investigator_id)
        REFERENCES investigators (investigator_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_custody_from_location FOREIGN KEY (from_location_id)
        REFERENCES storage_locations (location_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_custody_to_location FOREIGN KEY (to_location_id)
        REFERENCES storage_locations (location_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_custody_confirmed CHECK (confirmed IN (0,1))
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 4.2 evidence_access_logs
-- ----------------------------------------------------------------------------
CREATE TABLE evidence_access_logs (
    access_id        BIGINT UNSIGNED AUTO_INCREMENT,
    evidence_id      INT UNSIGNED NOT NULL,
    user_id          INT UNSIGNED NOT NULL,
    access_type      ENUM('view','download','export') NOT NULL DEFAULT 'view',
    access_timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_address       VARCHAR(45) NULL,
    PRIMARY KEY (access_id),
    CONSTRAINT fk_accesslog_evidence FOREIGN KEY (evidence_id)
        REFERENCES digital_evidence (evidence_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_accesslog_user FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 4.3 audit_logs
-- ----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    audit_id     BIGINT UNSIGNED AUTO_INCREMENT,
    table_name   VARCHAR(64) NOT NULL,
    record_id    BIGINT UNSIGNED NOT NULL,
    action_type  ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    old_value    JSON NULL,
    new_value    JSON NULL,
    changed_by   INT UNSIGNED NULL,
    changed_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id),
    CONSTRAINT fk_audit_user FOREIGN KEY (changed_by)
        REFERENCES users (user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ============================================================================
-- 5. INDEXES (performance — beyond those auto-created by UNIQUE/PK/FK)
-- ============================================================================

-- Frequent filter/join columns not already covered by UNIQUE or FK indexes
CREATE INDEX idx_cases_status        ON cases (case_status);
CREATE INDEX idx_cases_priority      ON cases (priority);
CREATE INDEX idx_cases_dates         ON cases (date_opened, date_closed);
CREATE INDEX idx_evidence_case       ON digital_evidence (case_id);
CREATE INDEX idx_evidence_status     ON digital_evidence (status_id);
CREATE INDEX idx_evidence_collected  ON digital_evidence (date_collected);
CREATE INDEX idx_custody_evidence    ON chain_of_custody (evidence_id, transfer_timestamp);
CREATE INDEX idx_accesslog_evidence  ON evidence_access_logs (evidence_id, access_timestamp);
CREATE INDEX idx_accesslog_user      ON evidence_access_logs (user_id, access_timestamp);
CREATE INDEX idx_audit_table_record  ON audit_logs (table_name, record_id);
CREATE INDEX idx_audit_changed_at    ON audit_logs (changed_at);
CREATE INDEX idx_investigators_dept  ON investigators (department_id);
CREATE INDEX idx_devices_suspect     ON devices (suspect_id);

-- ============================================================================
-- END OF PHASE 5 SCRIPT
-- ============================================================================
