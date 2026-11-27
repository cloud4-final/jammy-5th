# 입구 이미지: 의도적으로 갱신할 때만 PR로 바꾼다 (우분투 24.04, Canonical)
variable "edge_ami_id" {
  type    = string
  default = "ami-05b2d28c4a1614552"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.edge_ami_id))
    error_message = "edge_ami_id는 ami-로 시작해야 합니다."
  }
}

# 입구 서버 목록: 서브넷 이름과 같게
locals {
  edges = toset(["a", "c"])

  # wg-aws 터널 주소: 거점 호스트 설정의 피어 주소와 같아야 함 (#46)
  edge_wg_address = { a = "10.100.0.11", c = "10.100.0.12" }
}

resource "aws_instance" "edge" {
  for_each = local.edges # 목록 개수만큼 찍어 냄

  # 첫 부팅 때 SSM 읽기 권한이 먼저 있어야 함 (IAM 반영 지연은 별도 한계)
  depends_on = [aws_iam_role_policy.edge_ssm_minimal]

  ami                    = var.edge_ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[each.key].id # a는 서브넷 a, c는 서브넷 c
  vpc_security_group_ids = [aws_security_group.edge.id]
  iam_instance_profile   = aws_iam_instance_profile.edge.name

  # 템플릿 빈칸 채우기
  user_data = templatefile("${path.module}/userdata/edge.sh.tftpl", {
    hostname       = "jammy-edge-${each.key}"
    ts_param       = "/jammy/tailscale/edge-authkey-${each.key}"
    cfg_param      = aws_ssm_parameter.haproxy_cfg.name
    wg_key_param   = aws_ssm_parameter.edge_wg_private_key[each.key].name # 자기 키 경로만
    wg_peers_param = aws_ssm_parameter.edge_wg_peers.name
    wg_address     = local.edge_wg_address[each.key]
  })
  user_data_replace_on_change = true

  credit_specification {
    cpu_credits = "standard" # 크레딧 초과 과금 방지
  }

  root_block_device {
    encrypted = true
    tags      = { Name = "jammy-edge-${each.key}-root", Component = "edge" }
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 강제
  }

  tags = { Name = "jammy-edge-${each.key}", Component = "edge" }
}

resource "aws_eip" "edge" {
  for_each = local.edges
  domain   = "vpc"
  instance = aws_instance.edge[each.key].id
  tags     = { Name = "jammy-edge-${each.key}-eip", Component = "edge" }
}

# 이름표만 바뀜: 기존 edge_a / EIP를 새 주소로 옮김 (EIP 유지)
moved {
  from = aws_instance.edge_a
  to   = aws_instance.edge["a"]
}
moved {
  from = aws_eip.edge_a
  to   = aws_eip.edge["a"]
}

# HAProxy 설정 원본 → SSM 파라미터 (#43)
resource "aws_ssm_parameter" "haproxy_cfg" {
  name  = "/jammy/edge/haproxy-cfg"
  type  = "String"                                 # 비밀 아님 → 암호화 불필요
  tier  = "Standard"                               # 무료, 최대 4KB
  value = file("${path.module}/files/haproxy.cfg") # 레포 파일 내용을 그대로 올림
  tags  = { Name = "jammy-edge-haproxy-cfg", Component = "edge" }
}

# 입구 wg-aws 개인키: 자리만 만들고 값은 입구가 첫 부팅 때 생성 (교체해도 같은 키, #46)
resource "aws_ssm_parameter" "edge_wg_private_key" {
  for_each = local.edges
  name     = "/jammy/edge/wg-private-key-${each.key}"
  type     = "SecureString"
  value    = "placeholder"
  tags     = { Name = "jammy-edge-${each.key}-wg-private-key", Component = "edge" }

  lifecycle {
    ignore_changes = [value]
  }
}

# 입구 wg-aws 피어 목록(거점 호스트 5대): 비밀 아님, a·c 공용
resource "aws_ssm_parameter" "edge_wg_peers" {
  name  = "/jammy/edge/wg-peers"
  type  = "String"
  tier  = "Standard"
  value = file("${path.module}/files/wg-edge-peers.conf")
  tags  = { Name = "jammy-edge-wg-peers", Component = "edge" }
}
