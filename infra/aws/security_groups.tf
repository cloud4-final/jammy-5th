resource "aws_security_group" "edge" {
  name        = "jammy-edge-sg"
  description = "Edge HAProxy: web + Tailscale"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Tailscale direct" # 거점과 직접 연결 (없으면 중계 경유로 느려짐)
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "WireGuard wg-aws from sites" # 거점 호스트 5대가 먼저 접속 (#46)
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = var.site_public_cidrs
  }

  egress {
    description = "All outbound" # 서버에서 밖으로 나가는 건 전부 허용
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jammy-edge-sg", Component = "edge" }
}

# 건물 공인 IP /32 — 값은 커밋하지 않음: 로컬 terraform.tfvars, CI는 시크릿 SITE_PUBLIC_CIDRS (#55)
variable "site_public_cidrs" {
  type        = list(string)
  description = "WireGuard 접속을 허용할 거점 건물 공인 IP 목록"
  sensitive   = true
}

resource "aws_security_group" "hub" {
  name        = "jammy-hub-sg"
  description = "WireGuard hub: site-to-site relay only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "WireGuard wg2"
    from_port   = 51830
    to_port     = 51830
    protocol    = "udp"
    cidr_blocks = var.site_public_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jammy-hub-sg", Component = "hub" }
}
