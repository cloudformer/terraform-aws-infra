output "name" {
  value = aws_ecr_repository.this.name
}

output "url" {
  description = "<account>.dkr.ecr.<region>.amazonaws.com/<name>: docker push / image_uri without the tag."
  value       = aws_ecr_repository.this.repository_url
}

output "arn" {
  value = aws_ecr_repository.this.arn
}
