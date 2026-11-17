# EC2가 이 역할을 쓸 수 있다고 허락
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "edge" {
  name               = "jammy-edge-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "edge" {
  name = "jammy-edge-profile"
  role = aws_iam_role.edge.name
}

data "aws_caller_identity" "current" {}

# 입구가 쓰는 SSM 기능만 허용 (관리형 Core 대체, #38)
resource "aws_iam_role_policy" "edge_ssm_minimal" {
  name = "edge-ssm-minimal"
  role = aws_iam_role.edge.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AgentRegister" # SSM에 "나 살아 있음" 등록
        Effect   = "Allow"
        Action   = ["ssm:UpdateInstanceInformation"]
        Resource = "*"
      },
      {
        Sid    = "SessionManager" # ssm-to 접속
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
      {
        Sid    = "RunCommand" # 원격 명령 수신·응답
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadEdgeParams" # 이 경로만 읽기
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = [
          "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:parameter/jammy/tailscale/edge-authkey-*",
          "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.current.account_id}:parameter/jammy/edge/*",
        ]
      },
    ]
  })
}
