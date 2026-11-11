# GitHub 신분증을 믿는다는 협약
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = { Component = "ci" }
}

# 누가 출입증을 받을 수 있나: 우리 저장소의 PR만
data "aws_iam_policy_document" "gha_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:cloud4-final@348168592/jammy-5th@1434057848:pull_request"]
    }
  }
}

resource "aws_iam_role" "gha_plan" {
  name                 = "jammy-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.gha_plan_trust.json
  max_session_duration = 3600 # 1시간
  tags                 = { Component = "ci" }
}

# 할 수 있는 일 1: 전부 읽기 (plan용)
resource "aws_iam_role_policy_attachment" "gha_plan_read" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 할 수 있는 일 2: tfstate 잠금 파일만 쓰기
resource "aws_iam_role_policy" "gha_plan_lock" {
  name = "tfstate-lock"
  role = aws_iam_role.gha_plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::jammy-hybrid-tfstate-2026/aws/terraform.tfstate.tflock"
    }]
  })
}

# PR plan 역할은 백업 객체 내용을 읽지 못하게 함 (버킷 설정·목록은 plan에 필요해 유지)
resource "aws_iam_role_policy" "gha_plan_deny_backup_read" {
  name = "deny-backup-object-read"
  role = aws_iam_role.gha_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyBackupObjectRead"
      Effect   = "Deny"
      Action   = ["s3:GetObject*"]
      Resource = "${aws_s3_bucket.this["backup"].arn}/*"
    }]
  })
}
