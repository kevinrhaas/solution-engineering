# Pentaho Content Archive

This repository contains exported Pentaho content snapshots from various server instances, including datasource definitions, repository exports, and configuration backups used for demonstration, migration, and disaster recovery.

## Project Structure

```
pentaho-content/
├── 10.80.230.123/
│   └── datasources-2025-02-12/
│       ├── analysis/           # Mondrian schema datasources
│       ├── dsw/                # Data Source Wizard connections
│       ├── jdbc/               # JDBC datasource definitions
│       └── metadata/           # Metadata datasources
├── yes/
│   └── content-2025-02-12_*.zip.error.txt  # Failed content exports
├── archive/                    # Older exports and backups
└── README.md
```

## What's Inside

**Datasource Exports:**
- **Analysis** - Mondrian cube schema definitions with connection bindings
- **DSW** - Data Source Wizard-created connections (CSV, JSON, etc.)
- **JDBC** - Direct database connections (PostgreSQL, MySQL, SQL Server, etc.)
- **Metadata** - Pentaho Metadata Model datasources

**Repository Content:**
- Point-in-time snapshots of `/public` and other repository folders
- Includes .xanalyzer reports, .xdash dashboards, and .locale files
- Used for backup, migration between servers, and version control

## Purpose

**Development & Testing:**
- Reference implementations for datasource configurations
- Sample content for testing new Pentaho installations
- Baseline for comparing configuration changes

**Disaster Recovery:**
- Backup snapshots of production content and datasources
- Quick restore capability for critical reports and dashboards
- Version history for rollback scenarios

**Migration:**
- Transfer content between development, staging, and production environments
- Export from legacy versions for upgrade validation
- Cross-server content synchronization

## Usage Examples

### Pull Datasource Definitions

```bash
../pdc-analysis/utility/pull-datasources.sh 10.80.230.123:80 admin password 10.80.230.123/datasources-2025-02-12 yes
```

**What happens:**
1. Connects to Pentaho Server REST API
2. Exports all datasource types separately (analysis, dsw, jdbc, metadata)
3. Saves to organized directory structure
4. Optionally unzips exports for inspection

**Output Structure:**
```
<output-dir>/
├── analysis/       # .xmi files
├── dsw/            # .dsw files
├── jdbc/           # .jdbc files
└── metadata/       # .xmi files
```

### Pull Repository Content

```bash
../pdc-analysis/utility/pull-content.sh 10.80.230.123:80 admin password / content-2025-02-12 yes
```

**What happens:**
1. Initiates server-side repository export
2. Downloads exported ZIP file
3. Saves to specified directory with timestamp
4. Optionally unzips for direct access

**Note:** Content export API has known issues in some Pentaho versions. The 10.80.230.123 instance shows directory export failures (see `yes/` folder for error logs). This functionality works reliably in Pentaho 11.x+.

### Push Content to Repository

```bash
# From pdc-analysis project
cd ../pdc-analysis/utility
./push-file.sh ../content/public/pdc-analysis /public/pdc-analysis 10.80.230.123:80 admin password
```

## Server Instances

### 10.80.230.123:80
- **Version:** Pentaho Business Analytics (legacy version with known export API issues)
- **Content:** Datasource definitions successfully exported
- **Known Issues:** Directory-based content export fails with API errors
- **Last Export:** February 12, 2025 (datasources only)

### 10.80.230.193:80
- **Version:** Pentaho 11.x (stable)
- **Usage:** Primary target for cube publishing and content deployment
- **Features:** Full REST API support, reliable export/import

## Important Notes

**File Freshness:**
- Files are point-in-time snapshots and may become outdated
- Always verify against current server state before using for migration
- Check timestamps in directory names for snapshot age

**Safe Operations:**
- Exported files are read-only snapshots; safe to inspect and modify locally
- Outputs can be deleted and regenerated via utility scripts
- No server-side changes occur during pull operations

**Version Compatibility:**
- Datasource definitions may require adjustments when migrating across major versions
- Analyzer reports (.xanalyzer) generally portable across versions
- Mondrian schemas may need syntax updates for newer Pentaho versions

**Security:**
- Exported datasources may contain connection credentials
- Review files before committing to version control
- Use environment variables or property files for sensitive data in production

## Utility Scripts Reference

All utility scripts are located in `../pdc-analysis/utility/`:

- **pull-datasources.sh** - Export datasource definitions by type
- **pull-content.sh** - Export repository content (folders, reports, dashboards)
- **push-file.sh** - Upload files to Pentaho repository (binary mode)
- **publish-analyzer-cube.sh** - Deploy Mondrian schemas with cache refresh

See [pdc-analysis README](../pdc-analysis/README.md) for detailed script documentation.

## Troubleshooting

**Content Export Fails:**
- Verify Pentaho version supports directory export API
- Check server logs (catalina.out) for detailed error messages
- Try exporting smaller directory paths instead of full repository
- Use Pentaho 11.x+ for reliable content export functionality

**Datasource Import Fails:**
- Validate XML/JSON syntax in datasource files
- Ensure referenced JDBC drivers installed on target server
- Check database connection parameters (host, port, credentials)
- Verify datasource ID uniqueness in target environment

**Permission Errors:**
- Confirm user has admin privileges or appropriate repository ACLs
- Check repository folder permissions on target server
- Verify REST API authentication (username/password)

## Maintenance

**Regular Tasks:**
- Export datasources monthly for disaster recovery
- Tag exports with server version and date
- Document any manual configuration not captured in exports
- Test restore procedures periodically

**Cleanup:**
- Archive old exports to separate directory
- Remove error files after investigation
- Consolidate duplicate exports from same server/date

## Related Projects

- **pdc-analysis** - Source of utility scripts and Pentaho content
- **pentaho-11-docker-deploy** - Container-based Pentaho server deployment
- **pentaho-docker-deploy** - Legacy Docker deployment scripts
