"""
SQLAlchemy engine, session factory, and init helper.
"""

from __future__ import annotations
import logging
from contextlib import contextmanager

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, scoped_session

from ..config import DATABASE_URL
from .models import Base

logger = logging.getLogger(__name__)

_connect_args: dict = {}
if DATABASE_URL.startswith("sqlite"):
    # Allow multi-threaded use of the same SQLite connection (needed for
    # background threads in the job runner).
    _connect_args = {"check_same_thread": False}

engine = create_engine(
    DATABASE_URL,
    connect_args=_connect_args,
    echo=False,
    pool_pre_ping=True,
)

# Enable WAL mode for SQLite — greatly improves read concurrency
if DATABASE_URL.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def _set_wal_mode(dbapi_conn, _):
        dbapi_conn.execute("PRAGMA journal_mode=WAL")
        dbapi_conn.execute("PRAGMA synchronous=NORMAL")

_SessionFactory = sessionmaker(bind=engine, autoflush=True, autocommit=False, expire_on_commit=False)
Session = scoped_session(_SessionFactory)


def init_db() -> None:
    """Create all tables (idempotent — only creates what does not yet exist)."""
    logger.info("Initialising database at %s", DATABASE_URL)
    Base.metadata.create_all(engine)
    logger.info("Database ready")


@contextmanager
def get_db():
    """Context manager that yields a Session and auto-commits or rolls back."""
    db = Session()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        Session.remove()
