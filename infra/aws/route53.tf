# 도메인: 가비아에서 구매, 네임서버만 Route 53으로 위임
variable "domain_name" {
  type    = string
  default = "jammy.cloud"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = { Name = "jammy-zone", Component = "network" }
}

# 입구마다 HAProxy(80)가 응답하는지 확인
resource "aws_route53_health_check" "edge" {
  for_each = aws_eip.edge

  ip_address        = each.value.public_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 30 # 10초는 추가 요금
  failure_threshold = 3  # 연속 3번 실패 시 장애 판정

  tags = { Name = "jammy-edge-${each.key}-hc", Component = "edge" }
}

# 다중값 응답: 살아 있는 입구 주소만 응답 (전부 죽으면 전부 응답 = fail-open)
resource "aws_route53_record" "edge" {
  for_each = aws_eip.edge

  zone_id         = aws_route53_zone.main.zone_id
  name            = var.domain_name
  type            = "A"
  ttl             = 60
  records         = [each.value.public_ip]
  set_identifier  = "edge-${each.key}"
  health_check_id = aws_route53_health_check.edge[each.key].id

  multivalue_answer_routing_policy = true
}

output "route53_name_servers" {
  description = "가비아 '타사 네임서버'에 입력할 4개"
  value       = aws_route53_zone.main.name_servers
}
