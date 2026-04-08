output "s3_bucket_name" {
  description = "The S3 bucket hosting website files"
  value       = aws_s3_bucket.website.id
}

output "cloudfront_domain" {
  description = "CloudFront URL — your live website"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "Use this to invalidate the cache after updates"
  value       = aws_cloudfront_distribution.website.id
}
