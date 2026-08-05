"""Auth table DDL shared by SQLite and Postgres."""

AUTH_SCHEMA_SQL_POSTGRES = """
CREATE TABLE IF NOT EXISTS auth_users (
  id TEXT NOT NULL,
  username TEXT NOT NULL UNIQUE,
  tenant_user_id TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL,
  status TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
  password_changed_at TIMESTAMPTZ,
  failed_login_count INTEGER NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_user_id TEXT,
  PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_auth_users_username ON auth_users (username);
CREATE INDEX IF NOT EXISTS idx_auth_users_tenant ON auth_users (tenant_user_id);

CREATE TABLE IF NOT EXISTS auth_sessions (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ,
  user_agent TEXT,
  PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires ON auth_sessions (expires_at);

CREATE TABLE IF NOT EXISTS auth_audit_log (
  id TEXT NOT NULL,
  actor_user_id TEXT,
  action TEXT NOT NULL,
  target_user_id TEXT,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_auth_audit_created ON auth_audit_log (created_at DESC);

CREATE TABLE IF NOT EXISTS auth_settings (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"""

AUTH_SCHEMA_SQL_SQLITE = """
CREATE TABLE IF NOT EXISTS auth_users (
  id TEXT NOT NULL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  tenant_user_id TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL,
  status TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  must_change_password INTEGER NOT NULL DEFAULT 1,
  password_changed_at TEXT,
  failed_login_count INTEGER NOT NULL DEFAULT 0,
  locked_until TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  created_by_user_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_auth_users_username ON auth_users (username);
CREATE INDEX IF NOT EXISTS idx_auth_users_tenant ON auth_users (tenant_user_id);

CREATE TABLE IF NOT EXISTS auth_sessions (
  id TEXT NOT NULL PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL,
  last_seen_at TEXT,
  user_agent TEXT
);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires ON auth_sessions (expires_at);

CREATE TABLE IF NOT EXISTS auth_audit_log (
  id TEXT NOT NULL PRIMARY KEY,
  actor_user_id TEXT,
  action TEXT NOT NULL,
  target_user_id TEXT,
  details TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_auth_audit_created ON auth_audit_log (created_at);

CREATE TABLE IF NOT EXISTS auth_settings (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
"""
