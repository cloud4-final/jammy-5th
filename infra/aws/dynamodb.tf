resource "aws_dynamodb_table" "lease" {
  name         = "jammy-lease"
  billing_mode = "PAY_PER_REQUEST" # 온디맨드: 쓴 만큼만 과금
  hash_key     = "lease_id"

  attribute {
    name = "lease_id"
    type = "S"
  }

  # expires_at에 TTL 기능은 켜지 않음 (만료 시 아이템 삭제됨)
  deletion_protection_enabled = false # 8주차 destroy 리허설 대상

  tags = {
    Component = "lease"
  }
}

# 문지기: 우리 계정 사람 + MFA
resource "aws_iam_role" "lease_operator" {
  name                 = "jammy-lease-operator"
  max_session_duration = 3600 # 빌린 권한은 최대 1시간

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { Bool = { "aws:MultiFactorAuthPresent" = "true" } }
    }]
  })

  tags = { Component = "lease" }
}

# 역할 권한: lease 테이블만
resource "aws_iam_role_policy" "lease_operator" {
  name = "lease-takeover"
  role = aws_iam_role.lease_operator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"] # PutItem 제거: 통째 덮어쓰기 차단
      Resource = aws_dynamodb_table.lease.arn
      Condition = {
        # db-primary 키만 읽기·쓰기
        "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["db-primary"] }
      }
    }]
  })
}

# 입장권: admins 그룹은 이 역할을 빌릴 수 있음
resource "aws_iam_group_policy" "admins_assume_lease_operator" {
  name  = "assume-lease-operator"
  group = "admins"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.lease_operator.arn
    }]
  })
}
