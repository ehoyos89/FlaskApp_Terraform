# VPC 
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.subnet_cidr_block) 
  vpc_id = aws_vpc.main.id
  cidr_block = var.subnet_cidr_block[count.index]
  availability_zone = "${var.aws_region}${element(["a", "b"], count.index)}"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_route_table_association" {
  count = length(aws_subnet.public_subnets)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
  
}

# Security Group for EC2
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id
  name = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instance"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access"
  }
  ingress {
    from_port = 8000
    to_port = 8000
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow Flask app access"
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access"
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS access"
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name = "${var.project_name}-ec2-sg"
  } 
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id
  name = "${var.project_name}-rds-sg"
  description = "Security group for RDS instance"

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description = "Allow MySQL access from EC2"
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# RDS subnet group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name = "${var.project_name}-rds-subnet-group"
  subnet_ids = [for s in aws_subnet.public_subnets : s.id] 
  description = "use public subnets for RDS"

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
  
}

# RDS Instance
resource "aws_db_instance" "mysql_db" {
  allocated_storage =  var.db_allocated_storage
  engine = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  db_name = var.db_name
  username = jsondecode(aws_secretsmanager_secret_version.db_credentials_version.secret_string)["username"]
  password = jsondecode(aws_secretsmanager_secret_version.db_credentials_version.secret_string)["password"]
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  skip_final_snapshot = true
  publicly_accessible = true
  identifier = "${var.project_name}-mysql-db"

  tags = {
    Name = "${var.project_name}-mysql-db"
  }
}

# s3 Bucket for Flask Application
resource "aws_s3_bucket" "photos_bucket" {
  bucket = "${var.s3_bucket_name_prefix}-${var.project_name}-photos"

  tags = {
    Name        = "${var.project_name}-photos-bucket"
  }
  
}

# Block Public Access for S3 Bucket
resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.photos_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true

}

# Random ID for S3 Bucket
resource "random_id" "bucket_suffix" {
  byte_length = 6
}


# EC2 Instance
resource "aws_instance" "flask_app" {
  ami = var.ami_id
  instance_type = var.instance_type
  key_name = var.key_name
  subnet_id = aws_subnet.public_subnets[0].id
  security_groups = [aws_security_group.ec2_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = templatefile("${path.module}/user_data.sh", {
    aws_region = var.aws_region
    project_name = var.project_name
    db_endpoint = aws_db_instance.mysql_db.endpoint
    db_host_only = split(":", aws_db_instance.mysql_db.endpoint)[0]
    db_name = var.db_name
    photos_bucket = aws_s3_bucket.photos_bucket.bucket
    db_username_secret_arn    = aws_secretsmanager_secret.db_credentials.arn
    db_password_secret_arn    = aws_secretsmanager_secret.db_credentials.arn
    flask_secret_key_secret_arn = aws_secretsmanager_secret.flask_secret_key.arn
  })
  tags = {
    Name = "${var.project_name}-flask-app"
  }
}
