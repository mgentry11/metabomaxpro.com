# Secrets Manager for MetaboMax Pro HIPAA Infrastructure

# Secrets Manager Secret
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "metabomax-app-secrets-${var.environment}"
  description             = "Application secrets for MetaboMax Pro"
  kms_key_id              = aws_kms_key.secrets_manager.id
  recovery_window_in_days = 30

  tags = {
    Name = "metabomax-app-secrets-${var.environment}"
  }
}

# Secret Version with actual values
resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  secret_string = jsonencode({
    DATABASE_URL           = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.metabomax_primary.address}:${aws_db_instance.metabomax_primary.port}/${var.db_name}?sslmode=require"
    DATABASE_HOST          = aws_db_instance.metabomax_primary.address
    DATABASE_PORT          = tostring(aws_db_instance.metabomax_primary.port)
    DATABASE_NAME          = var.db_name
    DATABASE_USER          = var.db_username
    DATABASE_PASSWORD      = var.db_password
    FLASK_SECRET_KEY       = var.flask_secret_key
    STRIPE_SECRET_KEY      = var.stripe_secret_key
    STRIPE_PUBLISHABLE_KEY = var.stripe_publishable_key
    STRIPE_WEBHOOK_SECRET  = var.stripe_webhook_secret
  })
}

# Additional variables for secrets
variable "flask_secret_key" {
  description = "Flask secret key for session encryption"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_secret_key" {
  description = "Stripe secret key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_publishable_key" {
  description = "Stripe publishable key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_webhook_secret" {
  description = "Stripe webhook secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alert_email" {
  description = "Email address for security alerts"
  type        = string
  default     = ""
}
