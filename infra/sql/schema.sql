-- AI Coach schema (MySQL 8.0.16+)
-- NOTE: Run this script against your target database (schema) as a user with DDL privileges.
-- It defines tables, basic FKs/INDEX/UNIQUE, value-range CHECKs, and append-only triggers.

-- ========= Safety & session =========
SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ========= Users =========
CREATE TABLE IF NOT EXISTS users (
  user_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  email VARCHAR(255) UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ========= Baseline profiles (IPIP) =========
CREATE TABLE IF NOT EXISTS baseline_profiles (
  user_id BIGINT NOT NULL,
  administered_at DATETIME NOT NULL,
  -- T scores (0..100)
  O_T TINYINT UNSIGNED,
  C_T TINYINT UNSIGNED,
  E_T TINYINT UNSIGNED,
  A_T TINYINT UNSIGNED,
  N_T TINYINT UNSIGNED,
  -- 0..1 scores
  O_p01 DECIMAL(5,4),
  C_p01 DECIMAL(5,4),
  E_p01 DECIMAL(5,4),
  A_p01 DECIMAL(5,4),
  N_p01 DECIMAL(5,4),
  -- metadata
  norm_version VARCHAR(32) NOT NULL,
  PRIMARY KEY (user_id, administered_at),
  CONSTRAINT fk_baseline_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT ck_baseline_p01_range CHECK (
    O_p01 BETWEEN 0 AND 1 AND C_p01 BETWEEN 0 AND 1 AND E_p01 BETWEEN 0 AND 1 AND A_p01 BETWEEN 0 AND 1 AND N_p01 BETWEEN 0 AND 1
  ),
  CONSTRAINT ck_baseline_t_range CHECK (
    O_T BETWEEN 0 AND 100 AND C_T BETWEEN 0 AND 100 AND E_T BETWEEN 0 AND 100 AND A_T BETWEEN 0 AND 100 AND N_T BETWEEN 0 AND 100
  )
);

CREATE INDEX IF NOT EXISTS idx_baseline_user ON baseline_profiles(user_id);

-- ========= Daily text estimates (per observation) =========
CREATE TABLE IF NOT EXISTS text_personality_estimates (
  user_id BIGINT NOT NULL,
  observed_at DATETIME NOT NULL,
  -- normalized estimates per observation
  O_T TINYINT UNSIGNED,
  C_T TINYINT UNSIGNED,
  E_T TINYINT UNSIGNED,
  A_T TINYINT UNSIGNED,
  N_T TINYINT UNSIGNED,
  O_p01 DECIMAL(5,4),
  C_p01 DECIMAL(5,4),
  E_p01 DECIMAL(5,4),
  A_p01 DECIMAL(5,4),
  N_p01 DECIMAL(5,4),
  -- observation variance proxy (optional, average per traits in T scale)
  obs_var_T DECIMAL(8,3),
  lang_detected VARCHAR(8),
  lang_expected VARCHAR(8),
  tokens INT,
  mt_qe DECIMAL(5,4),
  ood_score DECIMAL(5,4),
  PRIMARY KEY (user_id, observed_at),
  CONSTRAINT fk_text_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT ck_text_p01_range CHECK (
    O_p01 BETWEEN 0 AND 1 AND C_p01 BETWEEN 0 AND 1 AND E_p01 BETWEEN 0 AND 1 AND A_p01 BETWEEN 0 AND 1 AND N_p01 BETWEEN 0 AND 1
  ),
  CONSTRAINT ck_text_t_range CHECK (
    O_T BETWEEN 0 AND 100 AND C_T BETWEEN 0 AND 100 AND E_T BETWEEN 0 AND 100 AND A_T BETWEEN 0 AND 100 AND N_T BETWEEN 0 AND 100
  )
);

CREATE INDEX IF NOT EXISTS idx_text_user_time ON text_personality_estimates(user_id, observed_at);

-- ========= Ocean time-series (Posterior; append-only) =========
CREATE TABLE IF NOT EXISTS ocean_timeseries (
  user_id BIGINT NOT NULL,
  date DATE NOT NULL,
  -- posterior means (T / p01)
  O_T TINYINT UNSIGNED,
  C_T TINYINT UNSIGNED,
  E_T TINYINT UNSIGNED,
  A_T TINYINT UNSIGNED,
  N_T TINYINT UNSIGNED,
  O_p01 DECIMAL(5,4),
  C_p01 DECIMAL(5,4),
  E_p01 DECIMAL(5,4),
  A_p01 DECIMAL(5,4),
  N_p01 DECIMAL(5,4),
  -- posterior variance in T scale (single representative; optional)
  posterior_var_T DECIMAL(8,3),
  PRIMARY KEY (user_id, date),
  CONSTRAINT fk_ts_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT ck_ts_p01_range CHECK (
    O_p01 BETWEEN 0 AND 1 AND C_p01 BETWEEN 0 AND 1 AND E_p01 BETWEEN 0 AND 1 AND A_p01 BETWEEN 0 AND 1 AND N_p01 BETWEEN 0 AND 1
  ),
  CONSTRAINT ck_ts_t_range CHECK (
    O_T BETWEEN 0 AND 100 AND C_T BETWEEN 0 AND 100 AND E_T BETWEEN 0 AND 100 AND A_T BETWEEN 0 AND 100 AND N_T BETWEEN 0 AND 100
  )
);

CREATE INDEX IF NOT EXISTS idx_ts_user_date ON ocean_timeseries(user_id, date);

-- Append-only triggers for ocean_timeseries
DELIMITER //
CREATE TRIGGER IF NOT EXISTS ocean_timeseries_no_update
BEFORE UPDATE ON ocean_timeseries
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='ocean_timeseries is append-only';
END//

CREATE TRIGGER IF NOT EXISTS ocean_timeseries_no_delete
BEFORE DELETE ON ocean_timeseries
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='ocean_timeseries is append-only';
END//
DELIMITER ;

-- ========= Features (optional; derived) =========
CREATE TABLE IF NOT EXISTS ocean_features (
  user_id BIGINT NOT NULL,
  date DATE NOT NULL,
  trait CHAR(1) NOT NULL CHECK (trait IN ('O','C','E','A','N')),
  ewma_T DECIMAL(6,2),
  slope_T_7d DECIMAL(6,2),
  var_T_14d DECIMAL(6,2),
  change_flag TINYINT(1),
  PRIMARY KEY (user_id, date, trait),
  CONSTRAINT fk_feat_ts FOREIGN KEY (user_id, date) REFERENCES ocean_timeseries(user_id, date)
);

-- ========= Intervention plans =========
CREATE TABLE IF NOT EXISTS intervention_plans (
  plan_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  planned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  technique ENUM('CBT','WOOP','IFTHEN') NOT NULL,
  tone VARCHAR(32),
  length VARCHAR(32),
  cta TEXT,
  llm_prompt TEXT,
  evidence_tags TEXT,
  CONSTRAINT fk_plan_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  INDEX idx_plan_user_time (user_id, planned_at)
);

-- ========= Behavior events (idempotent) =========
CREATE TABLE IF NOT EXISTS behavior_events (
  event_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  event_type ENUM('sent','viewed','clicked','completed') NOT NULL,
  event_ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  idempotency_key CHAR(36) NOT NULL,
  details JSON,
  CONSTRAINT fk_evt_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  UNIQUE KEY uq_behavior_idem (idempotency_key),
  INDEX idx_evt_user_time (user_id, event_ts)
);

-- ========= Audit log =========
CREATE TABLE IF NOT EXISTS audit_log (
  audit_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  occurred_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  user_id BIGINT NULL,
  module VARCHAR(64) NOT NULL,
  action VARCHAR(64) NOT NULL,
  payload JSON,
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  INDEX idx_audit_time (occurred_at),
  INDEX idx_audit_module (module)
);

-- ========= Helpful roles (optional) =========
-- CREATE ROLE pipeline_writer, analyst_reader;
-- GRANT SELECT, INSERT ON your_db.* TO pipeline_writer;
-- GRANT SELECT ON your_db.* TO analyst_reader;

-- ========= End =========

