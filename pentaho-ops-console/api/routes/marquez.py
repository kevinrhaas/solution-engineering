"""
Reverse proxy for Marquez OpenLineage UI and API.
Accessible at /marquez/ via the ops console port (8000) so no additional
firewall rules are needed.

  UI:  http://<ops-console>:8000/marquez/
  API: http://<ops-console>:8000/marquez/api/v1/lineage  (for testing)
"""

import httpx
from fastapi import APIRouter, Request, Response

router = APIRouter()

MARQUEZ_WEB = "http://10.80.230.17:8080"


@router.get("/marquez", include_in_schema=False)
@router.get("/marquez/{path:path}", include_in_schema=False)
async def proxy_marquez(request: Request, path: str = ""):
    url = f"{MARQUEZ_WEB}/{path}"
    if request.url.query:
        url += "?" + request.url.query

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in ("host", "content-length", "transfer-encoding")
    }

    async with httpx.AsyncClient(follow_redirects=True, timeout=30) as client:
        resp = await client.request(
            method=request.method,
            url=url,
            headers=forward_headers,
            content=await request.body(),
        )

    content = resp.content
    content_type = resp.headers.get("content-type", "")

    # Rewrite base href so the SPA resolves assets relative to /marquez/
    if "text/html" in content_type:
        content = content.replace(b'<base href="/">', b'<base href="/marquez/">')
        content = content.replace(b"<base href='/'>", b"<base href='/marquez/'>")

    # Drop hop-by-hop headers that must not be forwarded
    skip = {"content-length", "transfer-encoding", "content-encoding"}
    headers = {k: v for k, v in resp.headers.items() if k.lower() not in skip}

    return Response(content=content, status_code=resp.status_code,
                    media_type=content_type, headers=headers)
