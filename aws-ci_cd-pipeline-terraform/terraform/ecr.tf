resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}/api"
  image_tag_mutability = "IMMUTABLE"   # Tags can never be overwritten — audit trail

  image_scanning_configuration {
    scan_on_push = true   # Auto-scan every pushed image for vulnerabilities
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Lifecycle policy — keep last 10 production images, auto-clean old ones
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
