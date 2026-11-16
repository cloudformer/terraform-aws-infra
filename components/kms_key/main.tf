# One customer managed KMS key (≈ $1 a month, billed by the hour) and its alias.

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days # destroy schedules the deletion; it can be cancelled until then
  enable_key_rotation     = true
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
