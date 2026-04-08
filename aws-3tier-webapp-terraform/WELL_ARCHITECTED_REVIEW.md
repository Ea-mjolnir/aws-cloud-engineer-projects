# Well-Architected Review — 3-Tier Web App

## Reliability Pillar ✅
- Multi-AZ deployment across 2 availability zones
- Auto Scaling Group: min=1, desired=2, max=4 — self-healing
- ALB health checks replace unhealthy instances automatically
- RDS automated backups retained for 1 day (Free Tier limit)

## Security Pillar ✅
- 3-tier security group isolation: Internet → ALB → App → DB
- EC2 instances have no public IP — only reachable via ALB
- RDS in isolated subnets with no internet route
- DB password managed via environment variable, never in code

## Performance Efficiency Pillar ✅
- CPU-based auto scaling: scale out >70%, scale in <30%
- ALB distributes traffic evenly across instances and AZs

## Cost Optimization Pillar ✅
- t3.micro EC2 + db.t3.micro RDS (Free Tier eligible)
- Scale-in policy removes unused instances automatically
- NAT Gateway: single gateway (HA would use one per AZ — trade-off noted)

## Operational Excellence Pillar ✅
- 100% Terraform IaC — reproducible in any region
- CloudWatch dashboard + 3 alarms for proactive monitoring
- All resources tagged consistently

## Trade-offs Documented
- Single NAT Gateway vs HA — accepted for portfolio project
- RDS multi_az = false — accepted for Free Tier; flip to true for production
- No HTTPS on ALB — requires domain + ACM cert (added in future project)
