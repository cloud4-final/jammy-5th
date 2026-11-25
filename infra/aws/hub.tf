# WireGuard 허브: 거점 간 트래픽(주 DB → B2 5432, A → B1 7422)만 중계 (#52)
resource "aws_instance" "hub" {
  depends_on = [aws_iam_role_policy.hub]

  ami                    = var.edge_ami_id # 입구와 같은 우분투 24.04 (x86)
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public["a"].id
  vpc_security_group_ids = [aws_security_group.hub.id]
  iam_instance_profile   = aws_iam_instance_profile.hub.name

  user_data = templatefile("${path.module}/userdata/hub.sh.tftpl", {
    hostname    = "jammy-hub"
    key_param   = aws_ssm_parameter.hub_private_key.name
    peers_param = aws_ssm_parameter.hub_peers.name
  })
  user_data_replace_on_change = true

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    encrypted = true
    tags      = { Name = "jammy-hub-root", Component = "hub" }
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "jammy-hub", Component = "hub" }
}

# 고정 주소: 거점 설정의 Endpoint
resource "aws_eip" "hub" {
  domain   = "vpc"
  instance = aws_instance.hub.id
  tags     = { Name = "jammy-hub-eip", Component = "hub" }
}

# 개인키: Terraform은 자리만 만들고, 실제 값은 CLI로 덮어씀 (tfstate에 비밀값 없음)
resource "aws_ssm_parameter" "hub_private_key" {
  name  = "/jammy/hub/wg-private-key"
  type  = "SecureString"
  value = "placeholder"
  tags  = { Name = "jammy-hub-wg-private-key", Component = "hub" }

  lifecycle {
    ignore_changes = [value]
  }
}

# 피어 목록([Peer] 칸): 공개키·터널 주소라 비밀 아님. 바뀌어도 인스턴스 교체 없음
resource "aws_ssm_parameter" "hub_peers" {
  name  = "/jammy/hub/wg-peers"
  type  = "String"
  tier  = "Standard"
  value = file("${path.module}/files/wg-hub-peers.conf")
  tags  = { Name = "jammy-hub-wg-peers", Component = "hub" }
}
