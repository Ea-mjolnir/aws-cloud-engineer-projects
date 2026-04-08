# Well-Architected Review — Static Website + CDN

## Security Pillar
- S3 bucket is fully private. No public access.
- CloudFront OAC is the ONLY entity allowed to read S3.
- HTTPS enforced via viewer_protocol_policy = "redirect-to-https".

## Cost Optimization Pillar
- Estimated monthly cost: < $0.50
- PriceClass_100 limits CDN to US/EU edge locations.

## Reliability Pillar
- CloudFront serves from 400+ global edge locations.
- S3 provides 99.999999999% durability.

## Performance Efficiency Pillar
- Compression enabled (Brotli/Gzip via CloudFront).
- Cache TTL = 86400s (1 day).

## Operational Excellence Pillar
- 100% infrastructure managed by Terraform.
- All resources tagged.

## Trade-offs Considered
- No custom domain yet (added in future iteration).
- Default CloudFront cert used.
