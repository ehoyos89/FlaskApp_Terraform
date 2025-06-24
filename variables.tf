variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
  
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "flask-crud-app"
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "The CIDR block for the subnet"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "ami_id" {
  description = "The AMI ID to use for the EC2 instance"
  type        = string
  default     = "ami-0b28354031edf7b09" # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  
}

variable "instance_type" {
  description = "The type of EC2 instance to launch"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "The name of the SSH key pair to use for the EC2 instance"
  type        = string
  default     = "ec2_key" 
}

variable "db_instance_class" {
  description = "The instance class for the RDS database"
  type        = string
  default     = "db.t2.micro"
}

variable "db_allocated_storage" {
  description = "The allocated storage for the RDS database in GB"
  type        = number
  default     = 10
}

variable "db_engine_version" {
  description = "The version of the RDS database engine"
  type = string
  default = "mysql-8.0" # Puedes cambiar a la versión que necesites
}

variable "db_name" {
  description = "The name of the RDS database"
  type        = string
  default     = "flaskdb"
  
}

variable "s3_bucket_name_prefix" {
  description = "The prefix for the S3 bucket name"
  type        = string
  default     = "flask-crud-app-bucket" # revisar el nombre del bucket para evitar conflictos con otros buckets existentes
  
}



