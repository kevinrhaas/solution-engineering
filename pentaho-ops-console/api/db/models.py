"""
SQLAlchemy declarative models for the ops-console database.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    Column, DateTime, Float, Integer, String, Text, UniqueConstraint
)
from sqlalchemy.orm import declarative_base

Base = declarative_base()


def _uuid() -> str:
    return str(uuid.uuid4())


# ── Profiles ─────────────────────────────────────────────────────────────────

class Profile(Base):
    """Mirror of a .env profile file."""
    __tablename__ = "profiles"

    id         = Column(String(36),  primary_key=True, default=_uuid)
    name       = Column(String(200), nullable=False, unique=True, index=True)
    server_type = Column(String(50), nullable=False, default="")
    raw_env    = Column(Text,        nullable=False, default="")
    created_at = Column(DateTime,    nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime,    nullable=False, default=datetime.utcnow,
                        onupdate=datetime.utcnow)


# ── Instances ─────────────────────────────────────────────────────────────────

class Instance(Base):
    """Mirror of a *-runtime.state file."""
    __tablename__ = "instances"

    id               = Column(String(36),  primary_key=True, default=_uuid)
    name             = Column(String(200), nullable=False, index=True, default="")
    profile_name     = Column(String(200), nullable=False, index=True, default="")
    state_file       = Column(String(300), nullable=False, index=True, default="",
                              unique=True)
    ec2_instance_id  = Column(String(50),  nullable=False, default="")
    instance_ip      = Column(String(50),  nullable=False, default="")
    public_ip        = Column(String(50),  nullable=False, default="")
    instance_state   = Column(String(50),  nullable=False, default="")
    deploy_phase     = Column(String(50),  nullable=False, default="")
    server_type      = Column(String(50),  nullable=False, default="")
    pentaho_version  = Column(String(50),  nullable=False, default="")
    pdc_version      = Column(String(50),  nullable=False, default="")
    instance_type    = Column(String(50),  nullable=False, default="")
    environment      = Column(String(100), nullable=False, default="")
    db_type          = Column(String(50),  nullable=False, default="")
    server_url       = Column(String(300), nullable=False, default="")
    created_date     = Column(String(50),  nullable=False, default="")
    raw_state        = Column(Text,        nullable=False, default="")
    extra_json       = Column(Text,        nullable=False, default="{}")
    synced_at        = Column(DateTime,    nullable=False, default=datetime.utcnow,
                              onupdate=datetime.utcnow)


# ── Jobs ─────────────────────────────────────────────────────────────────────

class JobRecord(Base):
    """Persistent record of a job execution (written when job finishes)."""
    __tablename__ = "jobs"

    id           = Column(String(20),  primary_key=True)   # short uuid from runner
    script       = Column(Text,        nullable=False, default="")
    args_json    = Column(Text,        nullable=False, default="[]")   # JSON array
    cwd          = Column(Text,        nullable=False, default="")
    extra_env_json = Column(Text,      nullable=False, default="{}")   # JSON dict
    status       = Column(String(20),  nullable=False, default="pending", index=True)
    exit_code    = Column(Integer,     nullable=True)
    started_at   = Column(Float,       nullable=True)
    finished_at  = Column(Float,       nullable=True)
    output_json  = Column(Text,        nullable=False, default="[]")   # JSON list of lines
    created_at   = Column(DateTime,    nullable=False, default=datetime.utcnow, index=True)


# ── Secrets ───────────────────────────────────────────────────────────────────

class Secret(Base):
    """Encrypted credentials and keys stored in the database."""
    __tablename__ = "secrets"

    id         = Column(String(36),  primary_key=True, default=_uuid)
    kind       = Column(String(50),  nullable=False, index=True)
    # kind values: 'ssh_key' | 'aws_credentials' | 'git_token'
    name       = Column(String(200), nullable=False, default="")
    # name: filename for ssh_key; aws profile name for aws_credentials; 'default' for git_token
    value_enc  = Column(Text,        nullable=False, default="")  # Fernet or plain
    meta_json  = Column(Text,        nullable=False, default="{}")
    created_at = Column(DateTime,    nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime,    nullable=False, default=datetime.utcnow,
                        onupdate=datetime.utcnow)

    __table_args__ = (UniqueConstraint("kind", "name", name="uq_secret_kind_name"),)


# ── App Settings ──────────────────────────────────────────────────────────────

class AppSetting(Base):
    """Simple key/value store for application settings."""
    __tablename__ = "app_settings"

    key        = Column(String(200), primary_key=True)
    value      = Column(Text,        nullable=False, default="")
    updated_at = Column(DateTime,    nullable=False, default=datetime.utcnow,
                        onupdate=datetime.utcnow)
