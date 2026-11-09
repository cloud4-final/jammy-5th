locals {
  s3_buckets = {
    files  = "jammy-hybrid-files-2026"
    backup = "jammy-hybrid-backup-2026"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.s3_buckets
  bucket   = each.value
  tags     = { Name = each.value, Component = each.key }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule { object_ownership = "BucketOwnerEnforced" } # ACL 끔
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" } # SSE-S3
  }
}

output "s3_bucket_names" {
  value = { for k, b in aws_s3_bucket.this : k => b.id }
}
# 백업 버킷만. 현재 버전은 안 지움 (보관은 pgBackRest expire가 담당)
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket     = aws_s3_bucket.this["backup"].id
  depends_on = [aws_s3_bucket_versioning.this] # 버전 관리 먼저

  rule {
    id     = "pgbackrest-cleanup"
    status = "Enabled"
    filter { prefix = "pgbackrest/" }

    noncurrent_version_expiration { noncurrent_days = 30 } # 지워진 옛 버전 30일 보관
    expiration { expired_object_delete_marker = true }     # 남은 삭제 표시 정리
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
