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

  egress {
    description = "All outbound" # 서버에서 밖으로 나가는 건 전부 허용
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jammy-edge-sg", Component = "edge" }
}

# 건물 공인 IP가 정해지면 /32로 좁힘 (고정 IP 여부 확인 중, #52)
variable "site_public_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"] # 등록 안 된 키의 패킷에는 응답 안 함
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
