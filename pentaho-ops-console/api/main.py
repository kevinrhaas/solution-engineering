"""
Pentaho Ops Console — FastAPI application entry point.
"""

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .db import init_db
from .db.seed import seed_from_files
from .routes import jobs, profiles, provision, migrate, manage, config, marquez
from .runner import runner

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Startup: initialise DB tables, seed from on-disk files, restore jobs."""
    try:
        init_db()
        seed_from_files()
        runner.load_from_db()
    except Exception:
        logger.exception("DB initialisation failed — app will continue without persistence")
    yield


app = FastAPI(
    title="Pentaho Ops Console",
    description="Web UI + API for managing Pentaho server provisioning, migration, and operations.",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS — allow React dev server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount routers
app.include_router(jobs.router)
app.include_router(profiles.router)
app.include_router(provision.router)
app.include_router(migrate.router)
app.include_router(manage.router)
app.include_router(config.router)
app.include_router(marquez.router)


@app.get("/api/health")
def health():
    from .db.engine import engine
    try:
        with engine.connect() as conn:
            conn.execute(__import__("sqlalchemy").text("SELECT 1"))
        db_status = "ok"
    except Exception:
        db_status = "error"
    return {"status": "ok", "db": db_status}


# Serve React static build (production mode)
UI_DIST = Path(__file__).resolve().parent.parent / "ui" / "dist"
if UI_DIST.exists():
    # Serve Vite's hashed static assets (JS, CSS, images)
    if (UI_DIST / "assets").exists():
        app.mount("/assets", StaticFiles(directory=str(UI_DIST / "assets")), name="static-assets")

    # SPA catch-all: serve index.html for client-side routes
    @app.get("/{full_path:path}")
    async def serve_spa(full_path: str):
        file_path = UI_DIST / full_path
        if full_path and file_path.is_file():
            return FileResponse(str(file_path))
        return FileResponse(str(UI_DIST / "index.html"))
