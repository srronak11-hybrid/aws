provider "aws" {
       region = "ap-south-1"
   }

resource "aws_vpc" "vpc_tera" {
  cidr_block       = "192.168.0.0/25"

  tags = {
    Name = "vpc_tera"
  }
}

resource "aws_subnet" "sub_tera" {
  vpc_id     = "${aws_vpc.vpc_tera.id}"
  availability_zone = "ap-south-1a"
  cidr_block = "192.168.0.0/25"
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_internet_gateway" "gw_tf" {
  vpc_id = "${aws_vpc.vpc_tera.id}"

  tags = {
    Name = "tera"
  }
}

resource "aws_route_table" "rt_tera" {
  vpc_id = "${aws_vpc.vpc_tera.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw_tf.id}"
  }
}
resource "aws_route_table_association" "public_rt" {
  subnet_id      = aws_subnet.sub_tera.id
  route_table_id = aws_route_table.rt_tera.id
}

resource "aws_security_group" "SG_tera" {
  name        = "test_SG"
  description = "Allow TLS inbound traffic"
  vpc_id      = "${aws_vpc.vpc_tera.id}"

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "TLS from VPC"
    from_port   = 81
    to_port     = 81
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_tls"
  }
}


resource "aws_instance" "web2" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "${aws_subnet.sub_tera.availability_zone}"
  subnet_id = "${aws_subnet.sub_tera.id}"
  vpc_security_group_ids = [ "${aws_security_group.SG_tera.id}" ]	
  key_name = "keyaccess"
}

resource "aws_eip" "ip" {
  instance = "${aws_instance.web2.id}"
  vpc      = true
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = "${aws_instance.web2.id}"
  allocation_id = "${aws_eip.ip.id}"	
}

resource "aws_ebs_volume" "ebs_c" {
  availability_zone = "${aws_instance.web2.availability_zone}"
  size              = 5

  tags = {
    Name = "HelloWorld"
  }
}

resource "aws_volume_attachment" "ebs_tera" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebs_c.id}"
  instance_id = "${aws_instance.web2.id}"
  force_detach = true
}


resource "null_resource"  "null_local" {
depends_on = [ 
   aws_volume_attachment.ebs_tera,
 ]    
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/SR/Downloads/keyaccess.pem")
    host     = "${aws_instance.web2.public_ip}"
  }
  
  provisioner "rem ote-exec" {
    inline = [
      "sudo yum install -y httpd php docker",
      "sudo systemctl start httpd --now",
      "sudo systemctl start docker --now",
      "sudo mkfs.xfs /dev/sdh",
      "sudo mount /dev/sdh /var/www/html/",
      "sudo docker pull vimal13/apache-webserver-php",
      "sudo docker container run -dit --name os1 -p 81:80 vimal13/apache-webserver-php",
    ]
   }
 }

output "aws_instance" {
   value = aws_instance.web2.public_ip
}

resource "null_resource" "null_test" {
depends_on = [
      null_resource.null_local
 ]

   provisioner "local-exec" {
    command = "echo ${aws_instance.web2.public_ip} >> private_ips.txt"
  }
}
