#!/usr/bin/env python3
"""
load-lineage.py  —  Fetch PDC lineage events (OpenLineage format) and load
into stg_lineage_event + stg_lineage_connection on the bidb_ext PostgreSQL DB.

Usage:
    python3 load-lineage.py

Environment / hardcoded config matches pdc_analysis.properties.
"""

import hashlib
import json
import sys
import urllib.request
import urllib.error
import ssl

# ─── Config ────────────────────────────────────────────────────────────────────
PDC_HOST      = "https://10.80.230.246"
PDC_USER      = "admin"
PDC_PASS      = "Welcome123!"
PAGE_SIZE     = 100

DB_HOST       = "airlinesample.cyj079bqebpx.us-west-2.rds.amazonaws.com"
DB_PORT       = 5432
DB_NAME       = "postgres"
DB_USER       = "postgres"
DB_PASS       = "Password1"
DB_SCHEMA     = "bidb_ext_dev"

# Skip SSL verification (self-signed on PDC server)
SSL_CTX = ssl.create_default_context()
SSL_CTX.check_hostname = False
SSL_CTX.verify_mode = ssl.CERT_NONE


# ─── Helpers ───────────────────────────────────────────────────────────────────
def md5(s: str) -> str:
    return hashlib.md5(s.encode()).hexdigest()


def fetch_json(url: str, headers: dict) -> dict:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, context=SSL_CTX) as r:
        return json.loads(r.read())


def get_token() -> str:
    url = f"{PDC_HOST}/keycloak/realms/pdc/protocol/openid-connect/token"
    body = (
        f"client_id=pdc-client&grant_type=password"
        f"&username={PDC_USER}&password={PDC_PASS}&scope=openid"
    ).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, context=SSL_CTX) as r:
        return json.loads(r.read())["access_token"]


def parse_name_parts(name: str):
    """Split 'db.schema.table' into (db, schema, table), best-effort."""
    if not name:
        return "", "", ""
    # Skip filesystem-style paths
    if "/" in name or "\\" in name or ":" in name.split(".")[0]:
        return "", "", ""
    parts = name.split(".")
    if len(parts) >= 3:
        return parts[-3], parts[-2], parts[-1]
    elif len(parts) == 2:
        return "", parts[0], parts[1]
    else:
        return "", "", parts[0]


# ─── Fetch all events ──────────────────────────────────────────────────────────
def fetch_all_events(token: str):
    headers = {"Authorization": f"Bearer {token}"}
    page = 1
    all_events = []
    while True:
        url = f"{PDC_HOST}/lineage/api/events?perPage={PAGE_SIZE}&page={page}"
        data = fetch_json(url, headers)["data"]
        events = data.get("events", [])
        all_events.extend(events)
        page_info = data.get("pageInfo", {})
        has_next = page_info.get("hasNextPage", False)
        total = page_info.get("totalCount", "?")
        print(f"  Page {page}: {len(events)} events | total so far: {len(all_events)} / {total}")
        if not has_next:
            break
        page += 1
    return all_events


# ─── Transform ─────────────────────────────────────────────────────────────────
def transform(events):
    stg_events = []
    stg_connections = []

    for e in events:
        eid = e.get("_id", "")
        if not eid:
            continue

        et_raw = e.get("eventTime", "")
        event_time = et_raw[:19].replace("T", " ") if et_raw else None
        event_date = et_raw[:10] if et_raw else None
        event_type = e.get("eventType", "")
        run_id = (e.get("run") or {}).get("runId", "")

        job = e.get("job") or {}
        job_name = job.get("name", "")
        jf = (job.get("facets") or {}).get("jobType") or {}
        integration    = jf.get("integration", "")
        job_type       = jf.get("jobType", "")
        processing_type = jf.get("processingType", "")

        inputs  = e.get("inputs", [])
        outputs = e.get("outputs", [])

        in_names    = "|".join(i.get("name", "") for i in inputs)
        out_names   = "|".join(o.get("name", "") for o in outputs)
        in_namespace  = inputs[0].get("namespace", "") if inputs else ""
        out_namespace = outputs[0].get("namespace", "") if outputs else ""
        input_count   = len(inputs)
        output_count  = len(outputs)

        stg_events.append({
            "event_nk":       eid,
            "event_time":     event_time,
            "event_type":     event_type,
            "run_id":         run_id,
            "job_name":       job_name,
            "processing_type": processing_type,
            "integration":    integration,
            "job_type":       job_type,
            "in_namespace":   in_namespace,
            "in_names":       in_names,
            "out_namespace":  out_namespace,
            "out_names":      out_names,
            "input_count":    input_count,
            "output_count":   output_count,
            "record_count":   0,
            "event_date":     event_date,
        })

        # Connections: cartesian product of inputs × outputs
        for inp in inputs:
            orig_name = inp.get("name", "")
            orig_ns   = inp.get("namespace", "")
            orig_db, orig_schema, orig_table = parse_name_parts(orig_name)
            for out in outputs:
                dest_name = out.get("name", "")
                dest_ns   = out.get("namespace", "")
                dest_db, dest_schema, dest_table = parse_name_parts(dest_name)
                cnk = md5(f"{eid}|{orig_name}|{dest_name}")
                stg_connections.append({
                    "connection_nk": cnk,
                    "event_nk":     eid,
                    "run_id":       run_id,
                    "orig_namespace": orig_ns,
                    "orig_name":    orig_name,
                    "orig_db":      orig_db,
                    "orig_schema":  orig_schema,
                    "orig_table":   orig_table,
                    "dest_namespace": dest_ns,
                    "dest_name":    dest_name,
                    "dest_db":      dest_db,
                    "dest_schema":  dest_schema,
                    "dest_table":   dest_table,
                })

    return stg_events, stg_connections


# ─── Load ──────────────────────────────────────────────────────────────────────
def load(stg_events, stg_connections):
    try:
        import psycopg2
    except ImportError:
        print("ERROR: psycopg2 not installed. Run: pip3 install psycopg2-binary")
        sys.exit(1)

    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS
    )
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute(f"SET search_path TO {DB_SCHEMA}, public")

    print(f"\nTruncating stg tables...")
    cur.execute("TRUNCATE TABLE stg_lineage_event")
    cur.execute("TRUNCATE TABLE stg_lineage_connection")

    print(f"Inserting {len(stg_events)} events...")
    for row in stg_events:
        cur.execute("""
            INSERT INTO stg_lineage_event
                (event_nk, event_time, event_type, run_id, job_name, processing_type,
                 integration, job_type, in_namespace, in_names, out_namespace, out_names,
                 input_count, output_count, record_count, event_date)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (event_nk) DO NOTHING
        """, (
            row["event_nk"], row["event_time"], row["event_type"], row["run_id"],
            row["job_name"], row["processing_type"], row["integration"], row["job_type"],
            row["in_namespace"], row["in_names"], row["out_namespace"], row["out_names"],
            row["input_count"], row["output_count"], row["record_count"], row["event_date"],
        ))

    print(f"Inserting {len(stg_connections)} connections...")
    for row in stg_connections:
        cur.execute("""
            INSERT INTO stg_lineage_connection
                (connection_nk, event_nk, run_id, orig_namespace, orig_name,
                 orig_db, orig_schema, orig_table,
                 dest_namespace, dest_name, dest_db, dest_schema, dest_table)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (connection_nk) DO NOTHING
        """, (
            row["connection_nk"], row["event_nk"], row["run_id"],
            row["orig_namespace"], row["orig_name"],
            row["orig_db"], row["orig_schema"], row["orig_table"],
            row["dest_namespace"], row["dest_name"],
            row["dest_db"], row["dest_schema"], row["dest_table"],
        ))

    conn.commit()

    print("\nRefreshing materialized views...")
    for mv in [
        "dim_lineage_event_type",
        "dim_lineage_job",
        "dim_lineage_endpoint",
        "fact_lineage_event",
        "fact_lineage_connection",
    ]:
        print(f"  REFRESH {mv}...")
        cur.execute(f"REFRESH MATERIALIZED VIEW {mv}")
        conn.commit()

    cur.close()
    conn.close()
    print("\nDone.")


# ─── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("Authenticating with PDC Keycloak...")
    token = get_token()
    print("Token acquired.")

    print("\nFetching lineage events (all pages)...")
    events = fetch_all_events(token)
    print(f"Total events fetched: {len(events)}")

    print("\nTransforming...")
    stg_events, stg_connections = transform(events)
    print(f"  Events to load:      {len(stg_events)}")
    print(f"  Connections to load: {len(stg_connections)}")

    load(stg_events, stg_connections)
