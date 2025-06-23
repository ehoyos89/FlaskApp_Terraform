output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.flask_app.public_ip
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.mysql_db.address
}

output "s3_bucket_name" {
  description = "value of the S3 bucket name"
  value = aws_s3_bucket.photos_bucket.bucket
}

output "application_url" {
  description = "URL of the Flask application"
  value       = "http://${aws_instance.flask_app.public_ip}:8000"
}