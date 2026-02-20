CREATE DATABASE url_shortener;
\connect url_shortener;

-- Read DB passwords from container environment variables into psql variables.
-- These are set by docker/podman-compose from the .env file.
\getenv AUTH_DB_PASS AUTH_DB_PASS
\getenv LINKS_DB_PASS LINKS_DB_PASS
\getenv ANALYTICS_DB_PASS ANALYTICS_DB_PASS

CREATE SCHEMA IF NOT EXISTS auth_schema;
CREATE SCHEMA IF NOT EXISTS links_schema;
CREATE SCHEMA IF NOT EXISTS analytics_schema;

-- Create roles without passwords first (IF NOT EXISTS must be inside a DO block).
-- Passwords are set via ALTER ROLE below, outside dollar-quoting, so psql
-- variable interpolation (:'VAR') works reliably.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'auth_user') THEN
    CREATE ROLE auth_user LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'links_user') THEN
    CREATE ROLE links_user LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'analytics_user') THEN
    CREATE ROLE analytics_user LOGIN;
  END IF;
END $$;

-- Set passwords outside the DO block so psql variable substitution works.
ALTER ROLE auth_user WITH PASSWORD :'AUTH_DB_PASS';
ALTER ROLE links_user WITH PASSWORD :'LINKS_DB_PASS';
ALTER ROLE analytics_user WITH PASSWORD :'ANALYTICS_DB_PASS';

GRANT USAGE, CREATE ON SCHEMA auth_schema TO auth_user;
GRANT USAGE, CREATE ON SCHEMA links_schema TO links_user;
GRANT USAGE, CREATE ON SCHEMA analytics_schema TO analytics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth_schema GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO auth_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA links_schema GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO links_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics_schema GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO analytics_user;
