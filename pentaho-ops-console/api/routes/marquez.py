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
    # Marquez emits self-closing <base href="/"/> (XML style) — handle both forms
    if "text/html" in content_type:
        content = content.replace(b'<base href="/"/>', b'<base href="/marquez/"/>')
        content = content.replace(b'<base href="/">', b'<base href="/marquez/">')
        content = content.replace(b"<base href='/'/>", b"<base href='/marquez/'/>")
        content = content.replace(b"<base href='/'>", b"<base href='/marquez/'>")
        # Inject a basename shim before the bundle so React Router works under /marquez/.
        # Strategy:
        #   1. replaceState strips /marquez from the URL on first load so React Router
        #      initialises at the correct path (e.g. /jobs) rather than /marquez/jobs.
        #   2. pushState/replaceState are wrapped to add /marquez back, keeping URLs
        #      reload-safe in the address bar.
        #   3. A capture-phase popstate listener strips /marquez before the history
        #      package reads window.location, so Back/Forward also work correctly.
        shim = b"""<script>(function(){
var P='/marquez';
var _ps=history.pushState,_rs=history.replaceState;
function strip(p){return p.startsWith(P)?p.slice(P.length)||'/':p;}
function pfx(u){return(u&&typeof u==='string'&&u.startsWith('/')&&!u.startsWith(P))?P+u:u;}
if(window.location.pathname.startsWith(P)){
  _rs.call(history,history.state,'',strip(window.location.pathname)+window.location.search+window.location.hash);
}
history.pushState=function(s,t,u){return _ps.call(this,s,t,pfx(u));};
history.replaceState=function(s,t,u){return _rs.call(this,s,t,pfx(u));};
window.addEventListener('popstate',function(e){
  if(window.location.pathname.startsWith(P)){
    _rs.call(history,e.state,'',strip(window.location.pathname)+window.location.search+window.location.hash);
  }
},true);
}());</script>"""
        content = content.replace(b'<script src="./bundle.js">', shim + b'<script src="./bundle.js">')

    # Drop hop-by-hop headers that must not be forwarded
    skip = {"content-length", "transfer-encoding", "content-encoding"}
    headers = {k: v for k, v in resp.headers.items() if k.lower() not in skip}

    return Response(content=content, status_code=resp.status_code,
                    media_type=content_type, headers=headers)
