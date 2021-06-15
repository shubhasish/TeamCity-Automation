### Providers
provider "aws" {
  region = "us-east-1"
}
provider "ansible" {}
terraform {
  required_providers {
    ansible = {
      source = "nbering/ansible"
      version = "1.0.4"
    }
  }
}



### VPC
resource "aws_vpc" "teamcity_vpc" {
  cidr_block = "10.8.0.0/16"
  tags = {
    Name        = "teamcity-vpc"
    Environment = "dev"
  }
}

resource "aws_subnet" "public_subnet" {
  cidr_block = "10.8.1.0/24"
  vpc_id     = aws_vpc.teamcity_vpc.id
  tags = {
    Name        = "teamcity-subnet"
    Environment = "dev"
  }
}

resource "aws_internet_gateway" "IG" {
  vpc_id = aws_vpc.teamcity_vpc.id
  tags = {
    Name        = "teamcity-IG"
    Environment = "dev"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.teamcity_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IG.id
  }
}

resource "aws_route_table_association" "RT_association" {
  route_table_id = aws_route_table.route_table.id
  subnet_id      = aws_subnet.public_subnet.id
}


### Security group

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

resource "aws_security_group" "teamcity_sg" {
  name   = "teamcity-SG"
  vpc_id = aws_vpc.teamcity_vpc.id
  ingress {
    from_port = 80
    protocol  = "tcp"
    to_port   = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#### TeamCity server
module "teamcity_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  name           = "TeamCity-serevr"
  instance_count = 1

  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = "t2.medium"
  key_name                    = "teamcity"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.teamcity_sg.id]
  subnet_id                   = aws_subnet.public_subnet.id

  tags = {
    Terraform   = "true"
    Environment = "dev"
    name        = "TeamCity-serevr"
  }
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

output "public_ip" {
  value = module.teamcity_server.public_ip
}

#########################################################
# Ansible Resources
#########################################################

resource "ansible_host" "mongodb" {
  inventory_hostname     = module.teamcity_server.public_ip[0]
  groups                 = ["mongodb"]
  vars = {
    ansible_user         = "ec2-user"
    become               = "yes"
    interpreter_python   = "/usr/bin/python2"
    ansible_ssh_private_key_file = "~/.ssh/teamcity.pem"
    host_key_checking = "False"
  }
}

//resource "null_resource" "ansible_execution" {
//  depends_on = [ansible_host.mongodb]
//  provisioner "local-exec" {
//    command = "ansible-playbook -i lib/ teamcity.yaml"
//  }
//}


#### TeamCity agents
module "teamcity_agents" {
  count = 0
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  name           = "TeamCity-agent-${count.index}"
  instance_count = 1

  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = "t2.small"
  key_name                    = "teamcity"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.teamcity_sg.id]
  subnet_id                   = aws_subnet.public_subnet.id

  tags = {
    Terraform   = "true"
    Environment = "dev"
    name        = "TeamCity-agent-${count.index}"
  }
}


output "agent_public_ip" {
  value = module.teamcity_agents.*.public_ip
}

#########################################################
# Ansible Resources
#########################################################

resource "ansible_host" "teamcity_agents" {
  count = length(module.teamcity_agents.*.public_ip)
  inventory_hostname     = module.teamcity_agents.*.public_ip[count.index][0]
  groups                 = ["teamcity-agents"]
  vars = {
    ansible_user         = "ec2-user"
    become               = "yes"
    interpreter_python   = "/usr/bin/python2"
    ansible_ssh_private_key_file = "~/.ssh/teamcity.pem"
    host_key_checking = "False"
    teamcity_server_url = module.teamcity_server.private_ip[0]
    teamcity_server_public_url = module.teamcity_server.public_ip[0]
  }
}

//resource "null_resource" "ansible_execution" {
//  depends_on = [ansible_host.mongodb]
//  provisioner "local-exec" {
//    command = "ansible-playbook -i lib/ teamcity.yaml"
//  }
//}