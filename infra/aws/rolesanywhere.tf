# 거점 인증서를 믿는 기준: 자체 CA 인증서(공개)만 등록, CA 개인키는 레포 밖
resource "aws_rolesanywhere_trust_anchor" "sites" {
  name    = "jammy-sites"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = file("${path.module}/files/jammy-ca.crt")
    }
  }

  tags = { Component = "lease" }
}

locals {
  sites = toset(["a", "b"])
}

# 거점 역할 신뢰: 우리 trust anchor + 인증서 CN이 site-<거점>일 때만
data "aws_iam_policy_document" "site_trust" {
  for_each = local.sites

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_rolesanywhere_trust_anchor.sites.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/x509Subject/CN"
      values   = ["site-${each.key}"]
    }
  }
}

resource "aws_iam_role" "site" {
  for_each           = local.sites
  name               = "jammy-site-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.site_trust[each.key].json
  tags               = { Component = "lease" }
}

# 권한: lease 아이템 db-primary 조회·수정만 (SQS는 ④에서 추가)
data "aws_iam_policy_document" "site_lease" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.lease.arn]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "dynamodb:LeadingKeys"
      values   = ["db-primary"]
    }
  }
}

resource "aws_iam_role_policy" "site_lease" {
  for_each = local.sites
  name     = "lease-renew"
  role     = aws_iam_role.site[each.key].id
  policy   = data.aws_iam_policy_document.site_lease.json
}

resource "aws_rolesanywhere_profile" "sites" {
  name             = "jammy-sites"
  enabled          = true
  role_arns        = [for r in aws_iam_role.site : r.arn]
  duration_seconds = 3600
  tags             = { Component = "lease" }
}
