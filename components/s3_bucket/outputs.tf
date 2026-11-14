output "name" {
  value = aws_s3_bucket.this.bucket
}

output "arn" {
  value = aws_s3_bucket.this.arn
}

output "versioning_ids" {
  description = "[] when versioning = false."
  value       = aws_s3_bucket_versioning.this[*].id
}
