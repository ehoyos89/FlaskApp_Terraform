# Generate a random password for the database
resource "random_password" "db_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials"
  description = "Database credentials for ${var.project_name}"
  
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "dbadmin" # Cambiar a un nombre de usuario más seguro
    password = random_password.db_password.result
  })

}
# Generate a random password for the flask application
resource "random_password" "flask_app_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
}

resource "aws_secretsmanager_secret" "flask_secret_key" {
  name        = "${var.project_name}-flask-secret-key"
  description = "Secret key for Flask application ${var.project_name}"
  
}
resource "aws_secretsmanager_secret_version" "flask_secret_key_version" {
  secret_id     = aws_secretsmanager_secret.flask_secret_key.id
  secret_string = jsonencode({
    secret_key = random_password.flask_app_password.result
  })

}

# IAM role for the EC2 instance to access Secrets Manager and S3
resource "aws_iam_role" "ec2_app_role" {
  name = "${var.project_name}-ec2-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read_write" {
  role       = aws_iam_role.ec2_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" # Consider using a more restrictive policy for production environments
}

resource "aws_iam_role_policy_attachment" "ec2_secretsmanager_read" {
  role       = aws_iam_role.ec2_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" # Consider using a more restrictive policy for production environments
  
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_app_role.name
}