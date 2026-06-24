"""
ETL sync Lambda.

Runs on a schedule (e.g. every 5 minutes via EventBridge) and demonstrates
OLTP -> OLAP separation:
  Aurora (transactional, row-by-row order writes)
    -> this Lambda reads orders created since the last run
    -> writes them into Redshift Serverless via the Redshift Data API

This is a deliberately simple "near-real-time ETL" rather than a full
CDC pipeline (e.g. DMS or Aurora zero-ETL) - appropriate for a demo, and
something you can explicitly call out as a production upgrade path.
"""
import os
import boto3

rds_data = boto3.client("rds-data")
redshift_data = boto3.client("redshift-data")

AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_DB_NAME = os.environ["AURORA_DB_NAME"]

REDSHIFT_WORKGROUP = os.environ["REDSHIFT_WORKGROUP_NAME"]
REDSHIFT_SECRET_ARN = os.environ["REDSHIFT_SECRET_ARN"]
REDSHIFT_DB_NAME = os.environ["REDSHIFT_DB_NAME"]

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS orders_analytics (
    id VARCHAR(64),
    customer_id VARCHAR(128),
    item VARCHAR(256),
    amount DECIMAL(10,2),
    status VARCHAR(32),
    created_at TIMESTAMP,
    synced_at TIMESTAMP DEFAULT GETDATE()
);
"""


def _fetch_recent_orders(minutes_back=10):
    sql = """
        SELECT id, customer_id, item, amount, status, created_at
        FROM orders
        WHERE created_at >= now() - interval '%d minutes'
    """ % minutes_back
    result = rds_data.execute_statement(
        resourceArn=AURORA_CLUSTER_ARN,
        secretArn=AURORA_SECRET_ARN,
        database=AURORA_DB_NAME,
        sql=sql,
    )
    return result.get("records", [])


def _redshift_execute(sql):
    return redshift_data.execute_statement(
        WorkgroupName=REDSHIFT_WORKGROUP,
        SecretArn=REDSHIFT_SECRET_ARN,
        Database=REDSHIFT_DB_NAME,
        Sql=sql,
    )


def _ensure_redshift_schema():
    _redshift_execute(CREATE_TABLE_SQL)


def _escape(value):
    return value.replace("'", "''") if isinstance(value, str) else value


def handler(event, context):
    _ensure_redshift_schema()
    records = _fetch_recent_orders()

    synced = 0
    for row in records:
        order_id = row[0].get("stringValue")
        customer_id = row[1].get("stringValue")
        item = row[2].get("stringValue")
        amount = row[3].get("doubleValue")
        status = row[4].get("stringValue")
        created_at = row[5].get("stringValue")

        insert_sql = f"""
            INSERT INTO orders_analytics (id, customer_id, item, amount, status, created_at)
            VALUES ('{_escape(order_id)}', '{_escape(customer_id)}', '{_escape(item)}',
                    {amount}, '{_escape(status)}', '{_escape(created_at)}')
        """
        _redshift_execute(insert_sql)
        synced += 1

    return {"synced_rows": synced}
