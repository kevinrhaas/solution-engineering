"""
Provision API — EC2 creation, Pentaho deployment, plugin management, teardown.

All endpoints invoke the existing shell scripts from pentaho-11-docker-deploy/.
"""

import os
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..config import DEPLOY_SCRIPTS_DIR
from ..runner import runner

router = APIRouter(prefix="/api/provision", tags=["provision"])


def _require_env(profile_name: str):
    """Validate that the .env file exists and return its filename."""
    env_file = DEPLOY_SCRIPTS_DIR / f"{profile_name}.env"
    if not env_file.exists():
        raise HTTPException(404, f"Profile not found: {profile_name}")
    return env_file.name


class ProvisionRequest(BaseModel):
    profile: str  # name without .env extension
    state_file: str = ""  # optional: specific state file for instance-level ops


def _state_env(state_file: str) -> dict[str, str]:
    """Return env dict with STATE_FILE pointing to the state file, if given."""
    if not state_file:
        return {}
    return {"STATE_FILE": str(DEPLOY_SCRIPTS_DIR / state_file)}


# ── Full pipeline ────────────────────────────────────────────────────────────

@router.post("/preflight")
def preflight_check(req: ProvisionRequest):
    """Run preflight checks for a profile."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "00-preflight-check.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/full-deploy")
def full_deploy(req: ProvisionRequest):
    """Run the full deployment pipeline (EC2 + Pentaho + plugins)."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "00-full-deploy.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


# ── Step-by-step ─────────────────────────────────────────────────────────────

@router.post("/auth")
def authenticate(req: ProvisionRequest):
    """Authenticate with AWS via Okta."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "01-auth-okta-aws.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/create-ec2")
def create_ec2(req: ProvisionRequest):
    """Create EC2 instance."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "02-create-ec2.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/check-ec2")
def check_ec2(req: ProvisionRequest):
    """Check if EC2 instance is ready."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "03-check-ec2.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/deploy-pentaho")
def deploy_pentaho(req: ProvisionRequest):
    """Deploy Pentaho server to EC2."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "10-deploy-pentaho.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/deploy-plugins")
def deploy_all_plugins(req: ProvisionRequest):
    """Deploy all configured plugins."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "20-deploy-all-plugins.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


class PluginRequest(BaseModel):
    profile: str
    plugin_url: str
    no_restart: bool = False
    state_file: str = ""


@router.post("/deploy-plugin")
def deploy_single_plugin(req: PluginRequest):
    """Deploy a single plugin."""
    env_name = _require_env(req.profile)
    args = [env_name, req.plugin_url]
    if req.no_restart:
        args.append("--no-restart")
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "21-deploy-plugin.sh",
        args=args,
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── PDC (Pentaho Data Catalog) ───────────────────────────────────────────────

@router.post("/full-deploy-pdc")
def full_deploy_pdc(req: ProvisionRequest):
    """Run the full PDC deployment pipeline (EC2 + PDC)."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "00-full-deploy-pdc.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
    )
    return {"job_id": job.id}


@router.post("/deploy-pdc")
def deploy_pdc(req: ProvisionRequest):
    """Deploy PDC to EC2 instance."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "30-deploy-pdc.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── EC2 lifecycle ────────────────────────────────────────────────────────────

@router.post("/start-ec2")
def start_ec2(req: ProvisionRequest):
    """Start a stopped EC2 instance for the selected profile/state."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "04-start-ec2.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


@router.post("/stop-ec2")
def stop_ec2(req: ProvisionRequest):
    """Stop a running EC2 instance for the selected profile/state."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "05-stop-ec2.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}


# ── Teardown ─────────────────────────────────────────────────────────────────

@router.post("/teardown")
def teardown(req: ProvisionRequest):
    """Terminate EC2 instance and clean up resources."""
    env_name = _require_env(req.profile)
    job = runner.start(
        script=DEPLOY_SCRIPTS_DIR / "99-teardown.sh",
        args=[env_name],
        cwd=DEPLOY_SCRIPTS_DIR,
        env=_state_env(req.state_file),
    )
    return {"job_id": job.id}

