// Fetch available AZs to spread subnets.
data "aws_availability_zones" "available" {}

// Use the first two AZs for a simple multi-AZ layout.
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

// Base VPC for the whole environment.
resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

// Internet gateway for public internet access.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

// Public subnets for the ALB and NAT gateway.
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index) // /24 per public subnet
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                = "${var.name}-public-${count.index}"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

// Private subnets for EKS nodes and internal services.
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, 10 + count.index) // /24 per private subnet
  availability_zone = local.azs[count.index]

  tags = {
    Name                                = "${var.name}-private-${count.index}"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

// Elastic IP for the NAT gateway.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-eip" }
}

// NAT gateway to let private subnets reach the internet.
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.name}-nat" }

  depends_on = [aws_internet_gateway.igw]
}

// Public route table with a default route to the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public-rt" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

// Associate public subnets with the public route table.
resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

// Private route table with a default route to the NAT gateway.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private-rt" }
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

// Associate private subnets with the private route table.
resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
