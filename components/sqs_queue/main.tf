# One SQS queue (billed per request: ≈ $0 idle), e.g. a dead-letter queue for events that could not be delivered.

resource "aws_sqs_queue" "this" {
  name                      = var.name
  message_retention_seconds = var.retention_seconds
}
