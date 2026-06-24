"""
Order API Lambda.

Flow:
1. API Gateway invokes this on POST /order and GET /order/{id}
2. On POST: check DynamoDB for an existing idempotency key. If found, return
   the cached response (prevents duplicate orders on client retries).
   Otherwise write the order to Aurora via the RDS Data API (no persistent
   DB connection needed from Lambda -> avoids connection-pool exhaustion,
   a classic Lambda+RDS scaling problem) and cache the result in DynamoDB.
3. On GET: read the order back from Aurora.

This demonstrates a deliberate consistency tradeoff:
- Aurora (strong consistency, ACID) for the order record itself
- DynamoDB (eventually consistent by default) for idempotency/session data,
  where a rare duplicate check miss is an acceptable tradeoff for low latency
"""
import json
import os
import time
import uuid
import boto3

rds_data = boto3.client("rds-data")
dynamodb = boto3.client("dynamodb")

CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
DB_NAME = os.environ["AURORA_DB_NAME"]
TABLE_NAME = os.environ["SESSIONS_TABLE_NAME"]

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY,
    customer_id TEXT NOT NULL,
    item TEXT NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'CREATED',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


def _execute(sql, params=None):
    kwargs = {
        "resourceArn": CLUSTER_ARN,
        "secretArn": SECRET_ARN,
        "database": DB_NAME,
        "sql": sql,
    }
    if params:
        kwargs["parameters"] = params
    return rds_data.execute_statement(**kwargs)


def _ensure_schema():
    _execute(CREATE_TABLE_SQL)


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _get_idempotent_result(customer_id, idempotency_key):
    item = dynamodb.get_item(
        TableName=TABLE_NAME,
        Key={
            "pk": {"S": f"CUSTOMER#{customer_id}"},
            "sk": {"S": f"IDEMPOTENCY#{idempotency_key}"},
        },
    ).get("Item")
    if item:
        return json.loads(item["response_body"]["S"])
    return None


def _store_idempotent_result(customer_id, idempotency_key, response_body):
    dynamodb.put_item(
        TableName=TABLE_NAME,
        Item={
            "pk": {"S": f"CUSTOMER#{customer_id}"},
            "sk": {"S": f"IDEMPOTENCY#{idempotency_key}"},
            "response_body": {"S": json.dumps(response_body)},
            "expires_at": {"N": str(int(time.time()) + 86400)},  # 24h TTL
        },
    )


def create_order(event):
    body = json.loads(event.get("body") or "{}")
    customer_id = body.get("customer_id")
    item = body.get("item")
    amount = body.get("amount")
    idempotency_key = event.get("headers", {}).get("idempotency-key") or body.get(
        "idempotency_key"
    )

    if not customer_id or not item or amount is None:
        return _response(400, {"error": "customer_id, item, and amount are required"})

    if not idempotency_key:
        idempotency_key = str(uuid.uuid4())

    cached = _get_idempotent_result(customer_id, idempotency_key)
    if cached:
        cached["idempotent_replay"] = True
        return _response(200, cached)

    _ensure_schema()
    order_id = str(uuid.uuid4())

    _execute(
        "INSERT INTO orders (id, customer_id, item, amount) VALUES (:id, :customer_id, :item, :amount)",
        params=[
            {"name": "id", "value": {"stringValue": order_id}},
            {"name": "customer_id", "value": {"stringValue": customer_id}},
            {"name": "item", "value": {"stringValue": item}},
            {"name": "amount", "value": {"doubleValue": float(amount)}},
        ],
    )

    result = {
        "order_id": order_id,
        "customer_id": customer_id,
        "item": item,
        "amount": amount,
        "status": "CREATED",
        "idempotent_replay": False,
    }
    _store_idempotent_result(customer_id, idempotency_key, result)
    return _response(201, result)


def get_order(event):
    order_id = event.get("pathParameters", {}).get("id")
    if not order_id:
        return _response(400, {"error": "order id is required"})

    result = _execute(
        "SELECT id, customer_id, item, amount, status, created_at FROM orders WHERE id = :id",
        params=[{"name": "id", "value": {"stringValue": order_id}}],
    )
    records = result.get("records", [])
    if not records:
        return _response(404, {"error": "order not found"})

    row = records[0]
    return _response(
        200,
        {
            "order_id": row[0].get("stringValue"),
            "customer_id": row[1].get("stringValue"),
            "item": row[2].get("stringValue"),
            "amount": row[3].get("doubleValue"),
            "status": row[4].get("stringValue"),
            "created_at": row[5].get("stringValue"),
        },
    )


def handler(event, context):
    try:
        method = event.get("requestContext", {}).get("http", {}).get("method") or event.get(
            "httpMethod"
        )
        path = event.get("rawPath") or event.get("path") or ""

        if method == "POST" and path.endswith("/order"):
            return create_order(event)
        if method == "GET" and "/order/" in path:
            return get_order(event)

        return _response(404, {"error": "not found"})
    except Exception as exc:  # noqa: BLE001 - surface errors to the caller for the demo
        return _response(500, {"error": str(exc)})
