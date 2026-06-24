# Resilient Order Platform

A fault-tolerant, distributed order-processing system built on AWS managed
database services  **Aurora PostgreSQL (Multi-AZ)**, **DynamoDB**, and
**Redshift Serverless** deployed entirely via **Terraform**, with an
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



## Cleanup

```bash
cd terraform
terraform destroy
```

Confirm in the AWS console that the Aurora cluster, NAT gateway, and
Redshift Serverless namespace are gone — these are the costliest pieces if
left running.
