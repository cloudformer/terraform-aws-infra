# A private container image repository; old images expire, destroy deletes it with its images (they are rebuilt
# from source, never the only copy of anything).

resource "aws_ecr_repository" "this" {
  name         = var.name
  force_delete = true # destroy must work
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last ${var.keep_images} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.keep_images }
      action       = { type = "expire" }
    }]
  })
}
