provider "aws" {
       region = "ap-south-1"
   }

resource "tls_private_key" "tls_tera" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vkey" {
  key_name   = "tera_key"
  public_key = tls_private_key.tls_tera.public_key_openssh
}

resource "aws_vpc" "vpc_tera" {
  cidr_block       = "192.168.0.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc_tera"
  }
}

# Subnet: public instance

resource "aws_subnet" "public" {
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

resource "aws_route_table" "rt_public" {
  vpc_id = "${aws_vpc.vpc_tera.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw_tf.id}"
  }
}

resource "aws_route_table_association" "rt_pub" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt_public.id
}

resource "aws_security_group" "allow_tls_ssh" {
  name        = "SG-test"
  description = "Allow TLS inbound traffic"
  vpc_id      = "${aws_vpc.vpc_tera.id}"

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
    from_port   = 2049
    to_port     = 2049
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


resource "aws_instance" "baston" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "${aws_subnet.public.availability_zone}"
  subnet_id = "${aws_subnet.public.id}"
  vpc_security_group_ids = [ "${aws_security_group.allow_tls_ssh.id}" ]	
  key_name = aws_key_pair.vkey.key_name
 

  tags = {
    Name = "web1"
  }
}

resource "null_resource"  "local_1" {
   depends_on = [
            aws_instance.baston
    ]

 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tls_tera.private_key_pem
    host     = aws_instance.baston.public_ip
  }
 
 
  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y amazon-efs-utils  nfs-common  nfs-utils  httpd  git",
      "sudo systemctl enable httpd --now",
    ]
  }  
}

resource "aws_efs_file_system" "efs" {	
   depends_on = [
            null_resource.local_1
    ]
  creation_token = "my-product"

  tags = {
    Name = "MyProduct"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  depends_on = [
    aws_efs_file_system.efs
  ]
  file_system_id = aws_efs_file_system.efs.id
  subnet_id = aws_subnet.public.id
  security_groups = [ aws_security_group.allow_tls_ssh.id ]
}

data "aws_efs_mount_target" "mount_id" {
  mount_target_id = aws_efs_mount_target.efs_mount.id
}

resource "null_resource" "null_mount" {
   depends_on = [
              data.aws_efs_mount_target.mount_id
     ]
    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tls_tera.private_key_pem
    host     = aws_instance.baston.public_ip
  }
   provisioner "remote-exec" {
    inline = [
        "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${data.aws_efs_mount_target.mount_id.ip_address}:/  /var/www/html",
        "sudo su -c \"echo '${data.aws_efs_mount_target.mount_id.ip_address}:/ /var/www/html nfs4 defaults nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 00' >> /etc/fstab\"",
        "sudo rm -rf /var/www/html/*",
      ]
   }
}


resource "aws_s3_bucket" "end-point"	 {
  bucket = "my-tf-end-point"
  acl    = "private"
  region = "ap-south-1"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_vpc_endpoint" "s3-end" {
 depends_on = [
              null_resource.null_mount
     ]  
  
  vpc_id       = "${aws_vpc.vpc_tera.id}"
  service_name = "com.amazonaws.ap-south-1.s3"
 }


resource "aws_vpc_endpoint_route_table_association" "rt_add" {
   depends_on = [
              aws_vpc_endpoint.s3-end
     ]
  route_table_id  = "${aws_route_table.rt_public.id}"
  vpc_endpoint_id = "${aws_vpc_endpoint.s3-end.id}"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
 depends_on = [
              aws_s3_bucket.end-point
     ]
  origin {
    domain_name = "${aws_s3_bucket.end-point.bucket_regional_domain_name}"
    origin_id   = "my-tf-end-point"
 }
  enabled             = "true"
  is_ipv6_enabled     = "true"    
 

 default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "my-tf-end-point"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

    restrictions {
      geo_restriction {
        restriction_type = "none"
      }
   }
   
   viewer_certificate { 
    cloudfront_default_certificate = "true"
  }
}