// Random admin password for MongoDB.
resource "random_password" "mongo_admin" {
  length  = 16
  special = true

  lifecycle {
    prevent_destroy = true
  }
}

// Random app user password for MongoDB.
resource "random_password" "mongo_app" {
  length  = 16
  special = true

  lifecycle {
    prevent_destroy = true
  }
}

// SSH key for VM access.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    prevent_destroy = true
  }
}

// Register the SSH public key with EC2.
resource "aws_key_pair" "mongo" {
  key_name   = "${var.name}-mongo-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

// Public S3 bucket used for lab backups.
resource "aws_s3_bucket" "public_backups" {
  bucket_prefix = "${var.name}-public-backups-"
  force_destroy = true
}

// Disable public access blocks for the lab bucket.
resource "aws_s3_bucket_public_access_block" "public_backups" {
  bucket                  = aws_s3_bucket.public_backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

// Bucket policy that allows public list and read.
resource "aws_s3_bucket_policy" "public_backups" {
  bucket = aws_s3_bucket.public_backups.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicList",
        Effect    = "Allow",
        Principal = "*",
        Action    = ["s3:ListBucket"],
        Resource  = aws_s3_bucket.public_backups.arn
      },
      {
        Sid       = "PublicRead",
        Effect    = "Allow",
        Principal = "*",
        Action    = ["s3:GetObject"],
        Resource  = "${aws_s3_bucket.public_backups.arn}/*"
      }
    ]
  })
}

// Overly permissive instance role for the lab.
resource "aws_iam_role" "mongo_vm" {
  name = "${var.name}-mongo-vm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

// EC2 full access for the lab instance role.
resource "aws_iam_role_policy_attachment" "mongo_vm_ec2_full" {
  role       = aws_iam_role.mongo_vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

// S3 full access for the lab instance role.
resource "aws_iam_role_policy_attachment" "mongo_vm_s3_full" {
  role       = aws_iam_role.mongo_vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

// Instance profile used by the Mongo VM.
resource "aws_iam_instance_profile" "mongo_vm" {
  name = "${var.name}-mongo-vm-profile"
  role = aws_iam_role.mongo_vm.name
}

// Security group for the Mongo VM.
resource "aws_security_group" "mongo" {
  name   = "${var.name}-mongo-sg"
  vpc_id = aws_vpc.this.id

  // Allow SSH from anywhere for the lab.
  ingress {
    description = "SSH open to internet (intentional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Allow Mongo only from the private subnets.
  ingress {
    description = "Mongo from Kubernetes private subnets only"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  // Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Ubuntu 20.04 AMI for the lab.
data "aws_ami" "ubuntu_2004" {
  most_recent = true
  owners      = ["099720109477"] // Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

// MongoDB VM instance with user-data bootstrap.
resource "aws_instance" "mongo" {
  ami                         = data.aws_ami.ubuntu_2004.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.mongo.id]
  key_name                    = aws_key_pair.mongo.key_name
  iam_instance_profile        = aws_iam_instance_profile.mongo_vm.name
  associate_public_ip_address = true

  // Recreate the instance when user data changes.
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/mongo_user_data.sh.tftpl", {
    mongo_admin_password = random_password.mongo_admin.result
    mongo_app_password   = random_password.mongo_app.result
    public_backup_bucket = aws_s3_bucket.public_backups.bucket
  })

  tags = { Name = "${var.name}-mongo-vm" }
}
