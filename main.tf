terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = var.aws_region
  # access_key = var.aws_access_key
  # secret_key = var.aws_access_key
}
resource "aws_vpc" "default" {
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      cidr_block,
    ]
  }
  cidr_block = "172.31.0.0/16"
}
resource "aws_internet_gateway" "default" {
  lifecycle {
    prevent_destroy = true
  }
  vpc_id = aws_vpc.default.id
}
resource "aws_route" "internet_access" {
  lifecycle {
    prevent_destroy = true
  }
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}
resource "aws_subnet" "default" {
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      vpc_id,
      cidr_block,
    ]
  }
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "172.31.198.0/24"
  map_public_ip_on_launch = true
}
resource "aws_security_group" "default" {
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      name,
      vpc_id,
    ]

  }
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["172.31.198.0/24","52.49.159.236/32","109.92.31.155/32"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.31.198.0/24","52.49.159.236/32", "109.92.31.155/32"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "auth" {
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      key_name,
      public_key,
    ]
  }
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_instance" "web" {
  connection {
    type = "ssh"
    user = "ubuntu"
    host = self.public_ip
    private_key = file(var.key_name)
    timeout     = "1m"
    agent       = false
  }
  count = var.instance_count
  instance_type = "t2.medium"
  ami = var.aws_amis[var.aws_region]
  key_name = aws_key_pair.auth.id
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id = aws_subnet.default.id
  tags = {
    "type" = "tdex-box",
  }
  provisioner "file" {
  source      = "./scripts/provisioner.sh"
  destination = "/home/ubuntu/provisioner.sh"
  }

  provisioner "file" {
  source      = "./scripts/cronscript.sh"
  destination = "/home/ubuntu/cronscript.sh"
  }
  provisioner "file" {
  source      = "./scripts/backup.sh"
  destination = "/home/ubuntu/backup.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt install -y awscli",
      "git clone https://github.com/TDex-network/tdex-box.git",
      "chmod +x /home/ubuntu/provisioner.sh",
      "sudo /home/ubuntu/provisioner.sh",
      "chmod +x /home/ubuntu/cronscript.sh",
      "sudo /home/ubuntu/cronscript.sh",
      "chmod +x /home/ubuntu/backup.sh",
      "sudo mkdir /root/.aws/",
      "sudo printf '[default]\naws_access_key_id=${var.aws_access_key}\naws_secret_access_key=${var.aws_secret_key}' | sudo tee -a /root/.aws/credentials",
      "sudo /usr/bin/aws s3 cp /home/ubuntu/tdex-box/tdexd/db/ s3://tdexdb-terraform-test/db/ --recursive"
    ]
  }
}
