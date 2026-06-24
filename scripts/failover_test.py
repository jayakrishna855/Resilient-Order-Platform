#!/usr/bin/env python3
"""
Failover load test.

Hits the order API continuously while you manually trigger (or this script
triggers) an Aurora failover, and records:
  - request latency over time
  - error count / error windows
  - total downtime (first failed request -> first successful request after)

Usage:
    python3 scripts/failover_test.py \
        --api-url https://xxxx.execute-api.us-east-1.amazonaws.com \
        --cluster-id resilient-order-platform-aurora \
        --duration 180 \
        --trigger-failover

If --trigger-failover is omitted, the script just measures while you trigger
the failover manually from another terminal with:
    aws rds failover-db-cluster --db-cluster-identifier <cluster-id>
"""
import argparse
import csv
import json
import subprocess
import time
import urllib.error
import urllib.request
import uuid


def send_order(api_url):
    payload = json.dumps(
        {
            "customer_id": "loadtest-customer",
            "item": "widget",
            "amount": 9.99,
            "idempotency_key": str(uuid.uuid4()),
        }
    ).encode()

    req = urllib.request.Request(
        f"{api_url}/order",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            elapsed_ms = (time.time() - start) * 1000
            return True, resp.status, elapsed_ms
    except Exception as exc:  # noqa: BLE001
        elapsed_ms = (time.time() - start) * 1000
        return False, str(exc), elapsed_ms


def trigger_failover(cluster_id):
    print(f"[t=0] Triggering failover on cluster {cluster_id} ...")
    subprocess.run(
        ["aws", "rds", "failover-db-cluster", "--db-cluster-identifier", cluster_id],
        check=True,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--cluster-id", required=False)
    parser.add_argument("--duration", type=int, default=180, help="seconds to run")
    parser.add_argument("--interval", type=float, default=1.0, help="seconds between requests")
    parser.add_argument("--trigger-failover", action="store_true")
    parser.add_argument("--failover-at", type=int, default=20, help="seconds into the run to trigger failover")
    parser.add_argument("--output", default="failover_results.csv")
    args = parser.parse_args()

    results = []
    start_time = time.time()
    failover_triggered = False
    first_failure_t = None
    first_recovery_t_after_failure = None

    print(f"Starting load test against {args.api_url} for {args.duration}s ...")

    while time.time() - start_time < args.duration:
        t = time.time() - start_time

        if args.trigger_failover and not failover_triggered and t >= args.failover_at:
            trigger_failover(args.cluster_id)
            failover_triggered = True

        ok, status, elapsed_ms = send_order(args.api_url)
        results.append({"t": round(t, 2), "ok": ok, "status": status, "latency_ms": round(elapsed_ms, 1)})

        if not ok and first_failure_t is None:
            first_failure_t = t
            print(f"[t={t:.1f}s] FIRST FAILURE: {status}")
        if ok and first_failure_t is not None and first_recovery_t_after_failure is None:
            first_recovery_t_after_failure = t
            print(f"[t={t:.1f}s] FIRST RECOVERY after failure")

        status_label = "OK" if ok else "FAIL"
        print(f"[t={t:6.1f}s] {status_label:4s} status={status} latency={elapsed_ms:.0f}ms")

        time.sleep(args.interval)

    with open(args.output, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["t", "ok", "status", "latency_ms"])
        writer.writeheader()
        writer.writerows(results)

    total = len(results)
    failures = sum(1 for r in results if not r["ok"])
    print("\n--- SUMMARY ---")
    print(f"Total requests:   {total}")
    print(f"Failed requests:  {failures}")
    if first_failure_t is not None and first_recovery_t_after_failure is not None:
        downtime = first_recovery_t_after_failure - first_failure_t
        print(f"Measured downtime: {downtime:.1f}s (first failure -> first recovery)")
    else:
        print("No downtime window detected (failover may not have caused observable errors).")
    print(f"Raw results written to {args.output}")


if __name__ == "__main__":
    main()
