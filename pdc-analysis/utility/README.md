# PDC Analysis — Utility Scripts

Command-line tools for managing Pentaho Server repository content, datasources, and server-to-server migrations via the Pentaho REST API.

All scripts use `curl` under the hood and support `host:port` format for servers (port 80) or just `host` (defaults to port 8080). Default credentials are `admin`/`password`.

---

## Quick Reference

| Script | Purpose |
|--------|---------|
| `migrate-server.sh` | Full server-to-server migration (content + /home + datasources) |
| `pull-content.sh` | Smart sync DOWN from server (compare, backup, pull deltas) |
| `push-content.sh` | Smart sync UP to server (compare, backup, push deltas) |
| `sync-content.sh` | Bidirectional sync with conflict resolution |
| `download.sh` | Download a single file or folder |
| `upload.sh` | Upload a single file or folder |
| `pull-datasources.sh` | Export all datasource definitions from server |
| `push-datasources.sh` | Import datasource definitions to server |
| `push-cube.sh` | Publish Mondrian schema with cache refresh |
| `pull-home-files.sh` | Download /home content file-by-file |
| `push-home-files.sh` | Upload /home content to server |

---

## Server Migration

### migrate-server.sh

One-command migration of everything from one Pentaho server to another.

```bash
./migrate-server.sh [flags] <source-server> <target-server> [user] [pass]
```

**Flags:**
| Flag | Description |
|------|-------------|
| `--dry-run` | Preview without making changes |
| `--skip-content` | Skip /public repository content |
| `--skip-home` | Skip /home directory content |
| `--skip-ds` | Skip datasources |
| `--no-git` | Skip git snapshot step |
| `--content-path <path>` | Repository path to migrate (default: `/public`) |
| `--smart-title` | Auto-generate display titles on push |

**Workflow:**
1. **Pull** — downloads /public content, /home files, and datasources from source
2. **Snapshot** — commits pulled content to git (unless `--no-git`)
3. **Push** — uploads everything to target

```bash
# Dry run
./migrate-server.sh --dry-run 10.80.230.123:80 10.80.230.225:80

# Full migration
./migrate-server.sh 10.80.230.123:80 10.80.230.225:80 admin password

# Datasources only
./migrate-server.sh --skip-content --skip-home 10.80.230.123:80 10.80.230.225:80
```

**Migrates:** repository content, /home user files, JDBC connections, Analysis/Mondrian schemas, DSW, Metadata.
**Does not migrate:** server settings, scheduled jobs, user accounts, JNDI datasources, plugins.

---

## Content Sync

### pull-content.sh

Smart sync DOWN — downloads server content, compares against local files, skips identical, backs up changed.

```bash
./pull-content.sh [--dry-run] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

```bash
./pull-content.sh --dry-run ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
./pull-content.sh ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### push-content.sh

Smart sync UP — pulls server state first, then pushes only new or changed local files.

```bash
./push-content.sh [--dry-run] [--smart-title] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

```bash
./push-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
./push-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
```

### sync-content.sh

Bidirectional sync — local-only files pushed, server-only pulled, conflicts resolved by timestamp.

```bash
./sync-content.sh [--dry-run] [--smart-title] [--prefer-local|--prefer-server] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

| Flag | Description |
|------|-------------|
| `--prefer-local` | Local file always wins conflicts |
| `--prefer-server` | Server file always wins conflicts |
| `--smart-title` | Auto-generate display titles for pushed files |

```bash
./sync-content.sh --dry-run --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
./sync-content.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80 admin password
./sync-content.sh --prefer-local --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
```

> **Note:** All sync scripts ignore timestamp comment lines in `.locale` files so Pentaho's auto-generated export timestamps don't trigger false changes.

---

## Single File/Folder Operations

### download.sh

Download a single file or entire folder from the repository.

```bash
./download.sh [--dry-run] <repo-path> <local-path> <server[:port]> [user] [pass]
```

```bash
./download.sh /public/pdc-analysis/utility/main/j-main-script.kjb ./j-main-script.kjb 10.80.230.193:80
./download.sh /public/pdc-analysis ./content/public/pdc-analysis 10.80.230.193:80
```

### upload.sh

Upload a single file or folder recursively to the repository.

```bash
./upload.sh [--dry-run] [--smart-title] [--title "Name"] [--include-markdown] <source> <repo-path> <server[:port]> [user] [pass]
```

| Flag | Description |
|------|-------------|
| `--smart-title` | Auto-generate display titles from filenames |
| `--title "Name"` | Set an explicit display title |
| `--include-markdown` | Include `.md` files when uploading folders |

```bash
./upload.sh --smart-title ./content/public/pdc-analysis /public/pdc-analysis 10.80.230.193:80
./upload.sh --title "Main Script" j-main-script.kjb /public/pdc-analysis/utility/main 10.80.230.193:80
```

---

## Datasources

### pull-datasources.sh

Export all datasource definitions (Analysis, DSW, Metadata, JDBC) from a server.

```bash
./pull-datasources.sh [--uncompress] <output-dir> <server[:port]> [user] [pass]
```

```bash
./pull-datasources.sh --uncompress ./datasource-exports 10.80.230.193:80 admin password
```

Creates an organized directory: `analysis/`, `dsw/`, `metadata/`, `jdbc/`.

### push-datasources.sh

Import datasource definitions back to a server. Reads the directory layout created by `pull-datasources.sh`.

```bash
./push-datasources.sh [--dry-run] <input-dir> <server[:port]> [user] [pass]
```

```bash
./push-datasources.sh --dry-run ./datasource-exports 10.80.230.193:80
./push-datasources.sh ./datasource-exports 10.80.230.193:80 admin password
```

### push-cube.sh

Publish a Mondrian schema (analyzer cube) with automatic XMLA binding and cache refresh.

```bash
./push-cube.sh <xml-file> <datasource-name> <server[:port]> [user] [pass]
```

```bash
./push-cube.sh ../analyzer/bidb_ext.xml PDC-BIDB-EXT 10.80.230.193:80 admin password
```

---

## Home Directory Content

These scripts handle `/home/*` user content, which requires special treatment on older Pentaho servers where the standard export API returns 403 for `/home` paths.

### pull-home-files.sh

Downloads files individually via the `/api/repo/files/{pathId}/inline` endpoint, bypassing the directory export restriction.

```bash
./pull-home-files.sh [--dry-run] <local-dir> <repo-path> <server[:port]> [user] [pass]
```

```bash
# List all /home files without downloading
./pull-home-files.sh --dry-run ./home-backup /home 10.80.230.123:80

# Download everything
./pull-home-files.sh ./home-backup /home 10.80.230.123:80 admin password

# Download one user's home directory
./pull-home-files.sh ./admin-files /home/admin 10.80.230.123:80
```

### push-home-files.sh

Uploads /home content file-by-file. Automatically extracts `.ktr`/`.kjb` files from their Pentaho export zip wrappers before uploading (required for Pentaho 11 compatibility).

```bash
./push-home-files.sh [--dry-run] <local-dir> <server[:port]> [user] [pass]
```

```bash
./push-home-files.sh --dry-run ./home-backup 10.80.230.225:80
./push-home-files.sh ./home-backup 10.80.230.225:80 admin password
```

> **Note:** `pull-home-files.sh` downloads `.ktr`/`.kjb` files as zip-wrapped export bundles (file + `exportManifest.xml`). `push-home-files.sh` detects this automatically and extracts the raw XML before uploading. Both scripts are called by `migrate-server.sh` but work standalone.

---

## Common Patterns

**Dry run everything first:**
Every script that modifies data supports `--dry-run`. Always preview before executing.

**Server address format:**
- `10.80.230.193:80` — explicit port (HTTP on 80)
- `10.80.230.193` — defaults to port 8080
- `localhost:8080` — local development server

**Credentials:**
All scripts default to `admin`/`password` if not specified.

**Smart titles:**
`--smart-title` converts filenames like `j-main-script.kjb` → "J Main Script" for cleaner display in the Pentaho console.

**Backup behavior:**
Sync scripts (`pull-content.sh`, `push-content.sh`, `sync-content.sh`) automatically back up files before overwriting to `archive/content-backup/<timestamp>/`.
