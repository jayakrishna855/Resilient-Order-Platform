# DynamoDB stores idempotency keys + cart/session state.
# Partition key design: pk = "CUSTOMER#<id>", sk = "CART" | "IDEMPOTENCY#<key>"
# This single-table pattern avoids hot partitions by spreading load across
# customer IDs rather than a global counter or fixed key.
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-sessions"
  billing_mode = "PAY_PER_REQUEST" # on-demand: no capacity planning needed for a demo workload

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES" # feeds the ETL/analytics Lambda

  tags = {
    Name = "${var.project_name}-sessions"
  }
}
