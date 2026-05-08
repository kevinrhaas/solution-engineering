"""
Jobs API — list jobs, get job status, stream live output, cancel jobs.
"""

import json

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from starlette.responses import StreamingResponse

from ..runner import JobStatus, runner

router = APIRouter(prefix="/api/jobs", tags=["jobs"])


class BulkDeleteRequest(BaseModel):
    ids: list[str]


@router.post("/bulk-delete")
def bulk_delete_jobs(body: BulkDeleteRequest):
    """Delete multiple completed/failed/cancelled jobs by ID."""
    deleted = []
    skipped = []
    for jid in body.ids:
        job = runner.get(jid)
        if not job:
            skipped.append(jid)
            continue
        if job.status in (JobStatus.COMPLETED, JobStatus.FAILED, JobStatus.CANCELLED):
            runner.remove(jid)
            deleted.append(jid)
        else:
            skipped.append(jid)
    return {"deleted": deleted, "skipped": skipped}


@router.get("")
def list_jobs():
    """List all jobs with basic status info."""
    return [
        {
            "id": j.id,
            "script": j.script,
            "status": j.status,
            "exit_code": j.exit_code,
            "started_at": j.started_at,
            "finished_at": j.finished_at,
            "output_lines": len(j.output),
        }
        for j in runner.list_jobs()
    ]


@router.get("/{job_id}")
def get_job(job_id: str):
    """Get full job details including all output."""
    job = runner.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return {
        "id": job.id,
        "script": job.script,
        "args": job.args,
        "status": job.status,
        "exit_code": job.exit_code,
        "started_at": job.started_at,
        "finished_at": job.finished_at,
        "output": [
            {"timestamp": l.timestamp, "stream": l.stream, "text": l.text}
            for l in job.output
        ],
    }


@router.get("/{job_id}/stream")
async def stream_job(job_id: str, from_index: int = 0):
    """Stream job output as Server-Sent Events (SSE)."""
    job = runner.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")

    async def event_stream():
        async for line in runner.stream_output(job_id, from_index):
            data = json.dumps(
                {"stream": line.stream, "text": line.text, "ts": line.timestamp}
            )
            yield f"data: {data}\n\n"

        # Send final status event
        final = runner.get(job_id)
        if final:
            data = json.dumps(
                {"event": "done", "status": final.status, "exit_code": final.exit_code}
            )
            yield f"event: done\ndata: {data}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@router.post("/{job_id}/cancel")
def cancel_job(job_id: str):
    """Cancel a running job."""
    if runner.cancel(job_id):
        return {"status": "cancelled"}
    raise HTTPException(400, "Job not running or not found")
