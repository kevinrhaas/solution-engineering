"""
JobRunner — Execute shell scripts as async jobs with real-time output streaming.

Each job runs a subprocess, captures stdout/stderr line-by-line, and stores the
output in a buffer that can be streamed to clients via SSE.
"""

from __future__ import annotations
import asyncio
import json
import logging
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path

logger = logging.getLogger(__name__)


class JobStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class OutputLine:
    timestamp: float
    stream: str  # "stdout" or "stderr"
    text: str


@dataclass
class Job:
    id: str
    script: str
    args: list[str]
    cwd: str
    extra_env: dict[str, str] = field(default_factory=dict)
    status: JobStatus = JobStatus.PENDING
    exit_code: int | None = None
    started_at: float | None = None
    finished_at: float | None = None
    output: list[OutputLine] = field(default_factory=list)
    _process: subprocess.Popen | None = field(default=None, repr=False)


class JobRunner:
    """Manages async script execution with output buffering."""

    # Max jobs kept in memory (older ones live only in DB)
    _MAX_MEM = 200

    def __init__(self):
        self._jobs: dict[str, Job] = {}

    # ── DB helpers ────────────────────────────────────────────────────────────

    def load_from_db(self, limit: int = 200) -> None:
        """Restore the most recent terminal jobs from DB into memory on startup."""
        try:
            from .db.engine import get_db
            from .db.models import JobRecord
            with get_db() as db:
                records = (
                    db.query(JobRecord)
                    .filter(JobRecord.status.in_(["completed", "failed", "cancelled"]))
                    .order_by(JobRecord.created_at.desc())
                    .limit(limit)
                    .all()
                )
            for rec in records:
                lines = [
                    OutputLine(timestamp=ol["ts"], stream=ol["stream"], text=ol["text"])
                    for ol in json.loads(rec.output_json or "[]")
                ]
                job = Job(
                    id=rec.id,
                    script=rec.script,
                    args=json.loads(rec.args_json or "[]"),
                    cwd=rec.cwd,
                    extra_env=json.loads(rec.extra_env_json or "{}"),
                    status=JobStatus(rec.status),
                    exit_code=rec.exit_code,
                    started_at=rec.started_at,
                    finished_at=rec.finished_at,
                    output=lines,
                )
                self._jobs[job.id] = job
            logger.info("Restored %d job(s) from database", len(records))
        except Exception:
            logger.exception("Could not restore jobs from DB — starting with empty job list")

    def _persist_job(self, job: Job) -> None:
        """Write (or update) a job record to the database."""
        try:
            from .db.engine import get_db
            from .db.models import JobRecord
            output_payload = json.dumps([
                {"ts": ol.timestamp, "stream": ol.stream, "text": ol.text}
                for ol in job.output
            ])
            with get_db() as db:
                rec = db.query(JobRecord).filter_by(id=job.id).first()
                if rec is None:
                    rec = JobRecord(
                        id=job.id,
                        script=job.script,
                        args_json=json.dumps(job.args),
                        cwd=job.cwd,
                        extra_env_json=json.dumps(job.extra_env),
                    )
                    db.add(rec)
                rec.status = job.status.value
                rec.exit_code = job.exit_code
                rec.started_at = job.started_at
                rec.finished_at = job.finished_at
                rec.output_json = output_payload
        except Exception:
            logger.exception("Failed to persist job %s to DB", job.id)

    # ── Public API ────────────────────────────────────────────────────────────

    def start(self, script: str | Path, args: list[str], cwd: str | Path, env: dict[str, str] | None = None) -> Job:
        """Start a script as a background job. Returns the Job immediately."""
        job_id = uuid.uuid4().hex[:12]
        job = Job(
            id=job_id,
            script=str(script),
            args=[str(a) for a in args],
            cwd=str(cwd),
            extra_env=env or {},
        )
        self._jobs[job_id] = job

        # Evict oldest finished jobs if we're over the in-memory limit
        self._evict_old_jobs()

        thread = threading.Thread(target=self._run, args=(job,), daemon=True)
        thread.start()
        return job

    def _evict_old_jobs(self) -> None:
        """Keep only the most recent _MAX_MEM jobs in memory."""
        finished = [j for j in self._jobs.values()
                    if j.status in (JobStatus.COMPLETED, JobStatus.FAILED, JobStatus.CANCELLED)]
        if len(self._jobs) > self._MAX_MEM and finished:
            # Remove oldest finished job
            oldest = sorted(finished, key=lambda j: j.finished_at or 0)[0]
            del self._jobs[oldest.id]

    def get(self, job_id: str) -> Job | None:
        job = self._jobs.get(job_id)
        if job:
            return job
        # Fall back to DB for older jobs no longer in memory
        return self._load_job_from_db(job_id)

    def _load_job_from_db(self, job_id: str) -> Job | None:
        try:
            from .db.engine import get_db
            from .db.models import JobRecord
            with get_db() as db:
                rec = db.query(JobRecord).filter_by(id=job_id).first()
            if rec is None:
                return None
            lines = [
                OutputLine(timestamp=ol["ts"], stream=ol["stream"], text=ol["text"])
                for ol in json.loads(rec.output_json or "[]")
            ]
            return Job(
                id=rec.id,
                script=rec.script,
                args=json.loads(rec.args_json or "[]"),
                cwd=rec.cwd,
                extra_env=json.loads(rec.extra_env_json or "{}"),
                status=JobStatus(rec.status),
                exit_code=rec.exit_code,
                started_at=rec.started_at,
                finished_at=rec.finished_at,
                output=lines,
            )
        except Exception:
            logger.exception("Could not load job %s from DB", job_id)
            return None

    def list_jobs(self) -> list[Job]:
        return list(self._jobs.values())

    def cancel(self, job_id: str) -> bool:
        """Cancel a running job."""
        job = self._jobs.get(job_id)
        if not job or not job._process:
            return False
        try:
            job._process.terminate()
            job.status = JobStatus.CANCELLED
            job.finished_at = time.time()
            self._persist_job(job)
            return True
        except ProcessLookupError:
            return False

    def remove(self, job_id: str) -> bool:
        """Remove a finished job from the in-memory list (DB record stays)."""
        job = self._jobs.get(job_id)
        if not job:
            return False
        if job.status in (JobStatus.PENDING, JobStatus.RUNNING):
            return False
        del self._jobs[job_id]
        return True

    def _run(self, job: Job):
        """Execute the script in a subprocess, capturing output line-by-line."""
        job.status = JobStatus.RUNNING
        job.started_at = time.time()

        try:
            proc_env = None
            if job.extra_env:
                import os
                proc_env = {**os.environ, **job.extra_env}

            process = subprocess.Popen(
                ["bash", job.script] + job.args,
                cwd=job.cwd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,  # line-buffered
                env=proc_env,
            )
            job._process = process
            # Auto-confirm any interactive prompts (user already confirmed in UI)
            try:
                process.stdin.write("yes\n")
                process.stdin.close()
            except OSError:
                pass

            # Read stdout and stderr in separate threads
            def read_stream(stream, name):
                for line in stream:
                    job.output.append(
                        OutputLine(
                            timestamp=time.time(),
                            stream=name,
                            text=line.rstrip("\n"),
                        )
                    )
                stream.close()

            stdout_thread = threading.Thread(
                target=read_stream, args=(process.stdout, "stdout"), daemon=True
            )
            stderr_thread = threading.Thread(
                target=read_stream, args=(process.stderr, "stderr"), daemon=True
            )
            stdout_thread.start()
            stderr_thread.start()

            process.wait()
            stdout_thread.join(timeout=5)
            stderr_thread.join(timeout=5)

            job.exit_code = process.returncode
            job.status = (
                JobStatus.COMPLETED if process.returncode == 0 else JobStatus.FAILED
            )
        except Exception as exc:
            job.output.append(
                OutputLine(
                    timestamp=time.time(),
                    stream="stderr",
                    text=f"JobRunner error: {exc}",
                )
            )
            job.status = JobStatus.FAILED
            job.exit_code = -1
        finally:
            job.finished_at = time.time()
            job._process = None
            self._persist_job(job)

    async def stream_output(self, job_id: str, from_index: int = 0):
        """Async generator that yields new output lines as they appear."""
        job = self._jobs.get(job_id)
        if not job:
            return

        idx = from_index
        while True:
            # Yield any new lines
            while idx < len(job.output):
                line = job.output[idx]
                idx += 1
                yield line

            # If job is done and we've caught up, stop
            if job.status in (
                JobStatus.COMPLETED,
                JobStatus.FAILED,
                JobStatus.CANCELLED,
            ):
                # Yield any remaining lines
                while idx < len(job.output):
                    line = job.output[idx]
                    idx += 1
                    yield line
                return

            await asyncio.sleep(0.1)


# Singleton instance
runner = JobRunner()
