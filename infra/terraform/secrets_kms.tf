resource "aws_kms_key" "this" {
  description = "KMS for secrets"
}

resource "aws_secretsmanager_secret" "symanto" { name = "${var.project}/symanto/api_key" kms_key_id = aws_kms_key.this.arn }
resource "aws_secretsmanager_secret" "openai"  { name = "${var.project}/openai/api_key"  kms_key_id = aws_kms_key.this.arn }
resource "aws_secretsmanager_secret" "db"      { name = "${var.project}/db/password"     kms_key_id = aws_kms_key.this.arn }

