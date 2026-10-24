output "vpc_id" {
  description = "The VPC ID:"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "The DNS name for the ALB:"
  value       = aws_lb.alb.dns_name
}

output "bastion_public_ip" {
  description = "Public IP for the Bastion Host:"
  value       = aws_instance.bastion.public_ip
}

output "backend_private_ip" {
  description = "Private IP for the Backend Server:"
  value       = aws_instance.backend.private_ip
}