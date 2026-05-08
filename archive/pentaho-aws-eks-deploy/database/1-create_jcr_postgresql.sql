-- =============================================================================
-- Pentaho JCR (Jackrabbit Content Repository) PostgreSQL Schema
-- =============================================================================
-- This script creates the JCR database and user for Pentaho Server 11.0.0.0

\set passwd 'YourSecurePassword'

-- Create JCR database
CREATE DATABASE jackrabbit
    OWNER postgres
    ENCODING 'UTF8'
    LC_COLLATE 'en_US.UTF-8'
    LC_CTYPE 'en_US.UTF-8'
    TEMPLATE template0;

-- Create JCR user
CREATE USER jcr_user WITH ENCRYPTED PASSWORD :'passwd';

-- Grant privileges
GRANT CONNECT ON DATABASE jackrabbit TO jcr_user;

-- Connect to the JCR database and set up schema
\c jackrabbit

-- Grant schema privileges
GRANT CREATE ON SCHEMA public TO jcr_user;
GRANT USAGE ON SCHEMA public TO jcr_user;

-- Create JCR tables (these will be created automatically by Jackrabbit)
-- But we ensure proper permissions are set

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO jcr_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO jcr_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO jcr_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO jcr_user;

\echo 'JCR database and user created successfully'
