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
