-- =============================================================================
-- Pentaho Quartz Scheduler PostgreSQL Schema - Part A (Database Creation)
-- =============================================================================
-- This script creates the Quartz database for Pentaho Server 11.0.0.0

\set passwd 'YourSecurePassword'

-- Create Quartz database
CREATE DATABASE quartz
    OWNER postgres
    ENCODING 'UTF8'
    LC_COLLATE 'en_US.UTF-8'
    LC_CTYPE 'en_US.UTF-8'
    TEMPLATE template0;

-- Create Quartz user
CREATE USER pentaho_user WITH ENCRYPTED PASSWORD :'passwd';

-- Grant privileges
GRANT CONNECT ON DATABASE quartz TO pentaho_user;

\echo 'Quartz database and user created successfully'
