#!/usr/bin/env bash
# Quick smoke test: create an order, then fetch it back.
# Usage: ./scripts/smoke_test.sh https://xxxx.execute-api.us-east-1.amazonaws.com
set -euo pipefail

API_URL="${1:?Usage: smoke_test.sh <api-url>}"

echo "Creating order..."
RESPONSE=$(curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "demo-customer-1", "item": "widget", "amount": 19.99}')

echo "Response: $RESPONSE"

ORDER_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['order_id'])")

echo "Fetching order $ORDER_ID ..."
curl -s "${API_URL}/order/${ORDER_ID}" | python3 -m json.tool

echo "Re-sending the same order to verify idempotency..."
curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -d "{\"customer_id\": \"demo-customer-1\", \"item\": \"widget\", \"amount\": 19.99, \"idempotency_key\": \"smoke-test-key-1\"}" | python3 -m json.tool

curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -d "{\"customer_id\": \"demo-customer-1\", \"item\": \"widget\", \"amount\": 19.99, \"idempotency_key\": \"smoke-test-key-1\"}" | python3 -m json.tool

echo "Done. The second identical request above should show \"idempotent_replay\": true"
