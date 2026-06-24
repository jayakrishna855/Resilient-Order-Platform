# Resilient Order Platform

A fault-tolerant, distributed order-processing system built on AWS managed
database services — **Aurora PostgreSQL (Multi-AZ)**, **DynamoDB**, and
**Redshift Serverless** — deployed entirely via **Terraform**, with an
automated Aurora failover test used to measure real recovery time rather
than just assume it.

This is a portfolio/demo project, intentionally scoped to be buildable in a
single day while still exercising real distributed-systems tradeoffs:
consistency model selection, OLTP/OLAP separation, idempotency under
at-least-once delivery, and observability of failure modes.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the diagram and the
consistency tradeoffs made at each layer.

**Summary:**
- **API Gateway (HTTP API) → Lambda** — stateless request handling
- **Aurora PostgreSQL, Multi-AZ, Serverless v2** — system of record for orders. Strong consistency, ACID. Reached via the **RDS Data API**, so Lambda never holds a persistent DB connection (avoids the classic Lambda-concurrency-exhausts-the-connection-pool failure mode).
- **DynamoDB** — idempotency keys and session/cart state. On-demand capacity, single-table design (`pk`/`sk`), TTL-based expiry.
- **Redshift Serverless** — analytics warehouse, populated every 5 minutes by a scheduled Lambda that reads recent Aurora orders and batch-inserts them. Demonstrates deliberate OLTP/OLAP separation rather than running analytics queries against the transactional database.
- **CloudWatch dashboard + alarms** — Aurora replica lag, Aurora failover events, DynamoDB throttling, Lambda errors/duration.

## What this project actually proves (not just claims)

The centerpiece artifact is `scripts/failover_test.py`. It load-tests the
live API while triggering a real Aurora failover (`aws rds
failover-db-cluster`) and measures:

- exact timestamp of the first failed request
- exact timestamp of the first successful request afterward
- total measured downtime
- full per-request latency log (`failover_results.csv`)

This turns "the system is fault-tolerant" from a claim into a number you can
cite in an interview, e.g.:

> "Aurora failover completed in ~24 seconds with zero data loss, measured
> via an automated load test that triggered a real failover against the
> live cluster."

## Repo structure

```
resilient-order-platform/
├── terraform/              # All infrastructure (VPC, Aurora, DynamoDB, Redshift, Lambda, API GW, CloudWatch)
├── lambda/
│   ├── order_api/          # POST /order, GET /order/{id}
│   └── etl_sync/           # Scheduled Aurora -> Redshift sync
├── scripts/
│   ├── failover_test.py    # The key proof artifact - load test + failover trigger + downtime measurement
│   └── smoke_test.sh       # Basic end-to-end sanity check after deploy
└── docs/
    └── ARCHITECTURE.md     # Diagram + consistency tradeoff writeup
```

## Deploying

Prerequisites: Terraform >= 1.5, AWS CLI configured with credentials that
have permission to create VPCs, RDS, DynamoDB, Redshift Serverless, Lambda,
API Gateway, IAM, and CloudWatch resources.

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This provisions everything, including a NAT gateway (~$0.045/hr) and Aurora
Serverless v2 capacity (scales to 0.5 ACU minimum). Expect this to cost a few
dollars if you tear it down within a day — see "Cleanup" below.

Note the `api_endpoint` output when `apply` finishes.

## Verifying it works

```bash
./scripts/smoke_test.sh https://<api_endpoint from terraform output>
```

This creates an order, fetches it back, and demonstrates idempotent replay
on a duplicate request.

## Running the failover test

In one terminal, start the load test (it will trigger the failover itself
20 seconds in, by default):

```bash
python3 scripts/failover_test.py \
  --api-url https://<api_endpoint> \
  --cluster-id $(terraform -chdir=terraform output -raw aurora_cluster_id) \
  --duration 180 \
  --trigger-failover
```

Watch the per-request log for the failure window, then check the summary at
the end for measured downtime. Open the CloudWatch dashboard (URL in
`terraform output cloudwatch_dashboard_url`) to see the `Failover` metric and
replica lag spike at the same timestamp.

## Design decisions worth discussing in an interview

1. **Why RDS Data API instead of a direct Postgres connection from Lambda?**
   Lambda's concurrency model means a traffic spike can spawn hundreds of
   concurrent executions, each wanting a DB connection — this exhausts
   Aurora's connection limit quickly. The Data API is HTTP-based and
   connectionless, which avoids this entirely (the tradeoff is added
   per-query latency, acceptable here).

2. **Why DynamoDB for idempotency instead of a unique constraint in Aurora?**
   Centralizes a high-volume, simple key-value check off the relational
   database, freeing Aurora's connection/IOPS budget for the order writes
   themselves. Also naturally expires old keys via TTL.

3. **Why is Redshift sync scheduled rather than real-time CDC?**
   A 5-minute lag is an explicit, acceptable tradeoff for analytics
   workloads. The natural production upgrade path is DynamoDB Streams /
   Aurora zero-ETL integration with Redshift, called out here rather than
   over-built for a demo.

4. **What's the actual fault-tolerance mechanism being tested?**
   Aurora Multi-AZ keeps a synchronously replicated reader in a second AZ.
   On a triggered or real failure, Aurora promotes that reader to writer and
   updates the cluster endpoint's DNS — client reconnects transparently
   after a short interruption. The failover test measures exactly how short.

## Known limitations / explicit non-goals (called out, not hidden)

- Single-region only — no Aurora Global Database or DynamoDB Global Tables.
  This is the natural "what would you do next" answer in an interview.
- No ElastiCache layer in front of Aurora reads.
- No authentication on the API (demo-only, not for public deployment with
  real data).
- ETL sync uses simple polling, not true CDC.

## Cleanup

```bash
cd terraform
terraform destroy
```

Confirm in the AWS console that the Aurora cluster, NAT gateway, and
Redshift Serverless namespace are gone — these are the costliest pieces if
left running.
