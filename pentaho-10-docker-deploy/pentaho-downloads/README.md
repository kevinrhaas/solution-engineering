# Pentaho Downloads Directory

This directory contains the required Pentaho installation files for the deployment process.

## Required Files

Before running the deployment, you must place the following files in this directory:

### 1. Pentaho Server Enterprise Edition
- **Filename:** `pentaho-server-ee-10.2.0.0-222.zip`
- **Description:** Core Pentaho Business Analytics Server
- **Size:** ~2.5GB
- **Source:** [Pentaho Customer Support Portal](https://support.pentaho.com/)

### 2. Pentaho Analyzer Plugin - Example Plugin Install
- **Filename:** `paz-plugin-ee-10.2.0.0-222.zip`
- **Description:** Interactive analysis and visualization plugin
- **Size:** ~200MB
- **Source:** [Pentaho Customer Support Portal](https://support.pentaho.com/)

### 3. DockMaker Tool
- **Filename:** `dock-maker-10.2.0.0-222-public.zip`
- **Description:** Pentaho's official Docker containerization tool
- **Size:** ~50MB
- **Source:** [Pentaho Customer Support Portal](https://support.pentaho.com/)

## Download Instructions

1. **Access the Support Portal:** Log in to [support.pentaho.com](https://support.pentaho.com/) with your Pentaho credentials

2. **Navigate to Downloads:** Go to the Downloads section and select version 10.2.0.0-222

3. **Download Required Files:**
   - Download `dock-maker-10.2.0.0-222-public.zip`
   - Download `pentaho-server-ee-10.2.0.0-222.zip`
   - Download plugins, e.g. `paz-plugin-ee-10.2.0.0-222.zip` 

4. **Place Files:** Copy all three files to this directory

## File Verification

After downloading, verify the files are present:

```bash
ls -la pentaho-downloads/
```

You should see:
```
-rw-r--r--  pentaho-server-ee-10.2.0.0-222.zip
-rw-r--r--  paz-plugin-ee-10.2.0.0-222.zip
-rw-r--r--  dock-maker-10.2.0.0-222-public.zip
-rw-r--r--  README.md
```

## Security Notes

- These files contain proprietary Pentaho software and should not be shared publicly
- The `.gitignore` file excludes `*.zip` files from version control
- Store files securely and follow your organization's software license policies

## Troubleshooting

### File Not Found Errors
If deployment fails with "file not found" errors:
1. Check filenames match exactly (case-sensitive)
2. Ensure files are in this directory, not subdirectories
3. Verify file integrity (not corrupted downloads)

### Download Issues
- Contact Pentaho support if you cannot access the support portal
- Ensure your Pentaho license includes these components
- Try downloading with a different browser if files are corrupted

## Alternative Versions

This deployment is designed for Pentaho 10.2.0.0-222. For other versions:
1. Update filenames in the deployment scripts
2. Adjust version numbers in configuration files
3. Test thoroughly as different versions may have compatibility issues
