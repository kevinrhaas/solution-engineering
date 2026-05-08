"""
Manage API — Container lifecycle, logs, monitoring, and diagnostics.

All endpoints invoke the existing shell scripts from pentaho-11-docker-deploy/.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..config import DEPLOY_SCRIPTS_DIR, PDC_AUTOMATION_SCRIPTS_DIR
from ..runner import runner
from .profiles import _parse_env_file, _parse_state_file, _state_file_for

router = APIRouter(prefix="/api/manage", tags=["manage"])


def _require_env(profile_name: str):
    env_file = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not env_file.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")
    return env_file.name


def _state_env(state_file: str) -> dict[str, str]:
    """Return env dict with STATE_FILE for instance-level ops."""
    if not state_file:
        return {}
    return {"STATE_FILE": str(DEPLOY_SCRIPTS_DIR / state_file)}


class ManageRequest(BaseModel):
    profile: str
    state_file: str = ""


class LogsRequest(BaseModel):
    profile: str
    state_file: str = ""
    duration: str = ""
    lines: str = ""


class PdcAutomationRequest(BaseModel):
    profile: str
    action: str
    state_file: str = ""
    payload_json: str = ""
    params: dict[str, str] = Field(default_factory=dict)


PDC_AUTOMATION_ACTIONS: dict[str, dict[str, str]] = {
    "preflight": {
        "script": "00-preflight.sh",
        "label": "Preflight",
        "description": "Validate tooling, credentials, and API connectivity.",
    },
    "datasource": {
        "script": "10-manage-datasource.sh",
        "label": "Data Source",
        "description": "Create or inspect PDC data source metadata.",
    },
    "list-datasources": {
        "script": "10-list-datasources.sh",
        "label": "List Data Sources",
        "description": "List all PDC datasources with their Object IDs (_id) needed for ingest.",
    },
    "ingest": {
        "script": "20-ingest.sh",
        "label": "Ingest",
        "description": "Trigger metadata ingest or re-ingest jobs.",
    },
    "collection": {
        "script": "30-create-collection.sh",
        "label": "Collection",
        "description": "Create/update dataset collections and membership.",
    },
    "profile": {
        "script": "40-profile.sh",
        "label": "Profile",
        "description": "Run collection or entity data profiling jobs.",
    },
    "aggregate": {
        "script": "50-aggregate.sh",
        "label": "Aggregate",
        "description": "Run collection-level data aggregation.",
    },
    "results": {
        "script": "60-get-results.sh",
        "label": "Results",
        "description": "Fetch profiling and aggregation results for reporting.",
    },
    "tagging": {
        "script": "70-tag-entities.sh",
        "label": "Tagging",
        "description": "Apply tags to scoped PDC entities.",
    },
    "optional": {
        "script": "80-optional-jobs.sh",
        "label": "Optional Jobs",
        "description": "Run discovery, identification, PII, or trust-score jobs.",
    },
    "run-all": {
        "script": "run-all.sh",
        "label": "Run All",
        "description": "Run the full automation sequence using provided parameters.",
    },
}


# ── Container lifecycle ──────────────────────────────────────────────────────

@router.post("/restart")
def restart_container(req: ManageRequest):
    """Restart the Pentaho Docker container."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "90-restart-pentaho-container.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/up")
def start_container(req: ManageRequest):
    """Start the Pentaho Docker container."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "91-up-pentaho-container.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/down")
def stop_container(req: ManageRequest):
    """Stop the Pentaho Docker container."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "92-down-pentaho-container.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── Logs ─────────────────────────────────────────────────────────────────────

@router.post("/logs/catalina")
def tail_catalina(req: LogsRequest):
    """Tail the Tomcat catalina.out log."""
    env_name = _require_env(req.profile)
    args = [env_name]
    if req.lines:
        args.append(req.lines)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "93-tail-catalina-log.sh",
        args=args,
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/logs/docker")
def docker_logs(req: LogsRequest):
    """Get Docker container logs."""
    env_name = _require_env(req.profile)
    args = [env_name]
    if req.duration:
        args.extend(["", req.duration])  # empty container-name, then duration
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "94-get-docker-logs.sh",
        args=args,
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── Diagnostics ──────────────────────────────────────────────────────────────

@router.post("/monitor")
def monitor_resources(req: ManageRequest):
    """Monitor resource utilization on the EC2 instance."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "97-monitor-resources.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/diagnose")
def diagnose_container(req: ManageRequest):
    """Run container diagnostics."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "98-diagnose-container.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── PDC datasource lookup ─────────────────────────────────────────────────────

@router.get("/pdc-datasources")
def list_pdc_datasources(profile: str, state_file: str = "", query: str = "", limit: int = 50):
    """Fetch available datasources from the PDC instance for a given profile."""
    import json
    import ssl
    import urllib.parse
    import urllib.request

    env_name = _require_env(profile)
    env_path = DEPLOY_SCRIPTS_DIR / env_name
    env_vars = _parse_env_file(env_path)

    # Resolve PDC base URL
    base_url = (
        env_vars.get("PDC_API_BASE_URL")
        or env_vars.get("PDC_SERVER_URL")
        or env_vars.get("PDC_URL")
        or env_vars.get("PENTAHO_HOST")
    )
    if not base_url:
        state_path = _state_file_for(env_path)
        state_data = _parse_state_file(state_path)
        instance_ip = state_data.get("PRIVATE_IP", "") or state_data.get("PUBLIC_IP", "")
        if instance_ip:
            base_url = f"https://{instance_ip}"
    if not base_url:
        raise HTTPException(400, "Cannot determine PDC server URL for this profile")

    base_url = base_url.rstrip("/")
    username = env_vars.get("PDC_API_USERNAME") or env_vars.get("PDC_USERNAME") or "admin"
    password = env_vars.get("PDC_API_PASSWORD") or env_vars.get("PDC_PASSWORD") or "Welcome123!"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    # Authenticate
    auth_data = urllib.parse.urlencode({
        "client_id": "pdc-client",
        "grant_type": "password",
        "username": username,
        "password": password,
    }).encode()
    auth_req = urllib.request.Request(
        f"{base_url}/api/public/v1/auth",
        data=auth_data,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(auth_req, context=ctx, timeout=15) as resp:
            auth_json = json.loads(resp.read())
            # PDC returns {"message":"OK","data":{"accessToken":"..."}}
            token = (
                auth_json.get("data", {}).get("accessToken")
                or auth_json.get("access_token")
                or auth_json.get("accessToken")
            )
            if not token:
                raise ValueError(f"No token in response: {list(auth_json.keys())}")
    except Exception as exc:
        raise HTTPException(502, f"PDC auth failed: {exc}")

    # List datasources via POST filter (v2 then v1 fallback).
    # Older PDC instances may not have the filter endpoint; in that case we fall back
    # to v1 search + entities lookup when a query is provided.
    filter_body = json.dumps({"filters": {"resourceNames": ["*"]}}).encode()
    items: list = []
    last_error: str = ""
    for api_version in ("v2", "v1"):
        ds_req = urllib.request.Request(
            f"{base_url}/api/public/{api_version}/data-sources/filter",
            data=filter_body,
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(ds_req, context=ctx, timeout=15) as resp:
                data = json.loads(resp.read())
            raw = data if isinstance(data, list) else data.get("data", data.get("content", []))
            if isinstance(raw, list):
                items = raw
                break
        except Exception as exc:
            last_error = str(exc)
            continue

    # Filter list unsupported: use search fallback for name-based lookup.
    q = query.strip()
    if not items and last_error:
        if not q:
            raise HTTPException(
                400,
                "This PDC version does not support list-all datasource APIs. "
                "Provide a datasource name query to search and resolve IDs.",
            )

        search_payload = json.dumps({
            "searchTerm": q,
            "searchFacets": {"index": ["pdc_entities"], "type": ["RESOURCE"]},
            "page": 1,
            "perPage": max(1, min(limit, 200)),
        }).encode()
        search_req = urllib.request.Request(
            f"{base_url}/api/public/v1/search",
            data=search_payload,
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )

        try:
            with urllib.request.urlopen(search_req, context=ctx, timeout=15) as resp:
                search_data = json.loads(resp.read())
        except Exception as exc:
            raise HTTPException(502, f"PDC datasource search failed: {exc}")

        ids = [i.get("id") for i in search_data.get("data", []) if i.get("id")]
        if not ids:
            return []

        entities_req = urllib.request.Request(
            f"{base_url}/api/public/v1/entities/by-ids",
            data=json.dumps({"ids": ids}).encode(),
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(entities_req, context=ctx, timeout=15) as resp:
                entities_data = json.loads(resp.read())
        except Exception as exc:
            raise HTTPException(502, f"PDC entity lookup failed: {exc}")

        items = [
            {
                "_id": ent.get("resourceId", ""),
                "resourceName": ent.get("name", ""),
                "databaseType": ent.get("metadata", {}).get("resource", {}).get("type", ""),
                "pId": "",
            }
            for ent in entities_data.get("data", [])
            if ent.get("resourceId")
        ]

    normalized = [
        {
            "_id": item.get("_id", ""),
            "resourceName": item.get("resourceName", ""),
            "databaseType": item.get("databaseType", ""),
            "pId": item.get("pId", ""),
        }
        for item in items
        if item.get("_id")
    ]

    if q:
        q_lower = q.lower()
        normalized = [i for i in normalized if q_lower in i.get("resourceName", "").lower()]

    # Deduplicate by ObjectId while preserving order.
    seen: set[str] = set()
    out: list[dict[str, str]] = []
    for i in normalized:
        oid = i.get("_id", "")
        if not oid or oid in seen:
            continue
        seen.add(oid)
        out.append(i)
    return out


@router.get("/pdc-datasource-resolve")
def resolve_pdc_datasource(profile: str, name: str, state_file: str = ""):
    """Resolve a datasource ObjectId by datasource name using search + entity lookup."""
    matches = list_pdc_datasources(profile=profile, state_file=state_file, query=name, limit=50)
    if not matches:
        raise HTTPException(404, f"No datasource found for name: {name}")

    needle = name.strip().lower()
    preferred = next(
        (m for m in matches if m.get("resourceName", "").strip().lower() == needle),
        matches[0],
    )
    return {
        "_id": preferred.get("_id", ""),
        "resourceName": preferred.get("resourceName", ""),
        "databaseType": preferred.get("databaseType", ""),
        "matches": matches,
    }


# ── PDC lifecycle ─────────────────────────────────────────────────────────────

@router.post("/pdc-restart")
def restart_pdc(req: ManageRequest):
    """Restart PDC services (pdc.sh down + pdc.sh up)."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "39-restart-pdc-services.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── SSH info (returns command, doesn't start interactive session) ────────────

@router.get("/ssh-command/{profile}")
def get_ssh_command(profile: str, state_file: str = ""):
    """Return the SSH command for connecting to the container or instance."""
    env_name = _require_env(profile)
    import re
    env_path = DEPLOY_SCRIPTS_DIR / env_name

    # Use explicit state_file if provided, else fall back to legacy derivation
    if state_file:
        state_path = DEPLOY_SCRIPTS_DIR / state_file
    else:
        state_name = re.sub(r"\.env$", "-runtime.state", env_name)
        state_path = DEPLOY_SCRIPTS_DIR / state_name

    info = {}
    for path in [env_path, state_path]:
        if path.exists():
            for line in path.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    info[k.strip()] = v.strip().strip('"').strip("'")

    instance_ip = (info.get("PUBLIC_IP") or info.get("PRIVATE_IP")
                   or info.get("INSTANCE_PUBLIC_IP") or info.get("PENTAHO_HOST") or "")
    key_file = info.get("KEY_PATH") or info.get("KEY_PAIR_FILE") or info.get("SSH_KEY") or ""
    ssh_user = info.get("SSH_USER", "ubuntu")
    db_type = info.get("DB_TYPE", "postgres")
    container_name = f"pentaho-server-{db_type}-pentaho-server-1"

    return {
        "instance_ssh": f"ssh -i {key_file} {ssh_user}@{instance_ip}" if instance_ip else None,
        "container_ssh": f"ssh -i {key_file} {ssh_user}@{instance_ip} -t 'docker exec -it {container_name} bash'" if instance_ip else None,
        "instance_ip": instance_ip,
        "key_file": key_file,
    }


@router.get("/pdc-automation/actions")
def list_pdc_automation_actions():
    """Return all configured PDC automation actions available in Manage page."""
    out = []
    for action, meta in PDC_AUTOMATION_ACTIONS.items():
        out.append({
            "action": action,
            "script": meta["script"],
            "label": meta["label"],
            "description": meta["description"],
        })
    return out


@router.post("/pdc-automation/run")
def run_pdc_automation_action(req: PdcAutomationRequest):
    """Execute a discrete PDC automation script through the standard JobRunner."""
    env_name = _require_env(req.profile)
    action = req.action.strip().lower()
    if action not in PDC_AUTOMATION_ACTIONS:
        raise HTTPException(400, f"Unsupported action: {req.action}")

    script = PDC_AUTOMATION_SCRIPTS_DIR / PDC_AUTOMATION_ACTIONS[action]["script"]
    if not script.exists():
        raise HTTPException(500, f"Automation script not found: {script}")

    env_path = DEPLOY_SCRIPTS_DIR / env_name
    args = [str(env_path)]
    if req.payload_json:
        args.extend(["--payload-json", req.payload_json])
    for key, value in sorted(req.params.items()):
        if not key:
            continue
        if key == "dry-run" and value.strip().lower() in {"1", "true", "yes", "on"}:
            args.append("--dry-run")
            continue
        args.extend(["--param", f"{key}={value}"])

    # Auto-inject missing PDC env vars from state file / defaults
    extra_env = _state_env(req.state_file)
    env_vars = _parse_env_file(env_path)
    if not any(env_vars.get(k) for k in ("PDC_API_BASE_URL", "PDC_SERVER_URL", "PDC_URL", "PENTAHO_HOST")):
        state_path = _state_file_for(env_path)
        state_data = _parse_state_file(state_path)
        instance_ip = state_data.get("PRIVATE_IP", "") or state_data.get("PUBLIC_IP", "")
        if instance_ip:
            extra_env = {**extra_env, "PDC_SERVER_URL": f"https://{instance_ip}"}
    if not any(env_vars.get(k) for k in ("PDC_API_USERNAME", "PDC_USERNAME")):
        extra_env = {**extra_env, "PDC_API_USERNAME": "admin"}
    if not any(env_vars.get(k) for k in ("PDC_API_PASSWORD", "PDC_PASSWORD")):
        extra_env = {**extra_env, "PDC_API_PASSWORD": "Welcome123!"}

    job = runner.start(
        script=script,
        args=args,
        cwd=PDC_AUTOMATION_SCRIPTS_DIR,
        env=extra_env,
    )
    return {"job_id": job.id}
