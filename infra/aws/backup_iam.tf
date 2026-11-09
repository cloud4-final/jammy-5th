# pgBackRest(거점 Data VM)용. 키는 Terraform 밖에서 발급 (tfstate에 비밀 키 안 남김)
resource "aws_iam_user" "pgbackrest" {
  name = "jammy-pgbackrest"
  path = "/service/"
  tags = { Name = "jammy-pgbackrest", Component = "backup" }
}

data "aws_iam_policy_document" "pgbackrest" {
  statement {
    sid       = "ListRepoPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this["backup"].arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["pgbackrest/*"] # 목록도 이 경로만
    }
  }
  statement {
    sid       = "RepoObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.this["backup"].arn}/pgbackrest/*"]
  }
}

resource "aws_iam_user_policy" "pgbackrest" {
  name   = "pgbackrest-repo"
  user   = aws_iam_user.pgbackrest.name
  policy = data.aws_iam_policy_document.pgbackrest.json
}
