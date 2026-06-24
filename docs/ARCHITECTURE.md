```mermaid
flowchart LR
    Client[Client / curl / load test script]

    subgraph API["API Layer"]
        APIGW[API Gateway HTTP API]
        OrderLambda[Order API Lambda]
    end

    subgraph OLTP["Transactional Path"]
        Aurora[(Aurora PostgreSQL\nMulti-AZ\nServerless v2)]
        Dynamo[(DynamoDB\nidempotency + sessions)]
    end

    subgraph Analytics["Analytics Path"]
        ETLLambda[ETL Sync Lambda\nEventBridge schedule: 5 min]
        Redshift[(Redshift Serverless\nanalytics warehouse)]
    end

    subgraph Observability["Observability"]
        CW[CloudWatch Alarms + Dashboard]
        SNS[SNS Topic]
    end

    Client --> APIGW --> OrderLambda
    OrderLambda -->|RDS Data API\nstrong consistency| Aurora
    OrderLambda -->|idempotency check\neventual consistency| Dynamo

    ETLLambda -->|read recent orders| Aurora
    ETLLambda -->|batch insert| Redshift

    Aurora --> CW
    Dynamo --> CW
    OrderLambda --> CW
    CW --> SNS
```

**Consistency tradeoff made explicit:**
- Aurora is used for the order record itself: strong consistency, ACID transactions, relational integrity (a financial/order record should never be "eventually" correct).
- DynamoDB is used for idempotency keys and session/cart state: default eventual consistency is an acceptable tradeoff here in exchange for single-digit-millisecond latency, since a rare duplicate-check miss only risks a harmless duplicate order rather than data corruption.
- Redshift is fed asynchronously and is allowed to lag the source of truth (Aurora) by minutes — OLAP workloads do not need real-time consistency with OLTP.
