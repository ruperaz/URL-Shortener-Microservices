CREATE DATABASE url_shortener;
\connect url_shortener;

CREATE SCHEMA IF NOT EXISTS auth_schema;
CREATE SCHEMA IF NOT EXISTS links_schema;
CREATE SCHEMA IF NOT EXISTS analytics_schema;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'auth_user') THEN
    CREATE ROLE auth_user LOGIN PASSWORD :'AUTH_DB_PASS';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'links_user') THEN
    CREATE ROLE links_user LOGIN PASSWORD :'LINKS_DB_PASS';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'analytics_user') THEN
    CREATE ROLE analytics_user LOGIN PASSWORD :'ANALYTICS_DB_PASS';
  END IF;
END $$;

GRANT USAGE, CREATE ON SCHEMA auth_schema TO auth_user;
GRANT USAGE, CREATE ON SCHEMA links_schema TO links_user;
GRANT USAGE, CREATE ON SCHEMA analytics_schema TO analytics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth_schema GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO auth_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA links_schema GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO links_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics_schema GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO analytics_user;
