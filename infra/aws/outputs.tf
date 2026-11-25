output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = { for k, s in aws_subnet.public : k => s.id }
}

output "edge_public_ips" {
  value = { for k, e in aws_eip.edge : k => e.public_ip } # { a = "...", c = "..." }
}

output "gha_plan_role_arn" {
  value = aws_iam_role.gha_plan.arn
}

output "hub_public_ip" {
  value = aws_eip.hub.public_ip # 거점 설정의 Endpoint (UDP 51830)
}
