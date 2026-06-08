###############################################################
# spot-outputs.tf
# Outputs for Windows EC2 Spot Instance
###############################################################

output "spot_instance_id" {
  description = "Spot Instance Request ID (use this to track the request)"
  value       = aws_spot_instance_request.windows_spot.id
}

output "spot_instance_actual_instance_id" {
  description = "Actual EC2 Instance ID (available after fulfillment)"
  value       = aws_spot_instance_request.windows_spot.spot_instance_id
}

output "spot_availability_zone" {
  description = "AZ where the spot instance is running"
  value       = aws_spot_instance_request.windows_spot.availability_zone
}

output "spot_state" {
  description = "Current state of the spot instance request: pending | active | cancelled | closed"
  value       = aws_spot_instance_request.windows_spot.spot_request_state
}

output "public_ip" {
  description = "Public IP — use this for WinRM / RDP"
  value       = aws_spot_instance_request.windows_spot.public_ip
}

output "public_dns" {
  description = "Public DNS"
  value       = aws_spot_instance_request.windows_spot.public_dns
}

output "private_ip" {
  description = "Private IP of the spot instance"
  value       = aws_spot_instance_request.windows_spot.private_ip
}

output "ami_used" {
  description = "Windows AMI ID that was selected"
  value       = data.aws_ami.windows.id
}

output "ami_name" {
  description = "Windows AMI name"
  value       = data.aws_ami.windows.name
}

output "key_name" {
  description = "EC2 Key Pair name"
  value       = aws_key_pair.ec2_key.key_name
}

output "private_key_path" {
  description = "Path to the saved private key PEM file"
  value       = local_sensitive_file.private_key.filename
}

output "winrm_connection_test" {
  description = "Command to test WinRM from your Ubuntu VM (run after 5 min)"
  value       = "curl -s http://${aws_spot_instance_request.windows_spot.public_ip}:5985/wsman"
}

output "rdp_connection" {
  description = "RDP target"
  value       = "${aws_spot_instance_request.windows_spot.public_ip}:3389"
}

output "ansible_inventory_command" {
  description = "Quick test command for Ansible WinRM ping"
  value       = "ansible windows -i '${aws_spot_instance_request.windows_spot.public_ip},' -m win_ping -e 'ansible_user=ansible_admin ansible_password=<YOUR_PASSWORD> ansible_connection=winrm ansible_winrm_transport=basic ansible_winrm_port=5985 ansible_winrm_scheme=http ansible_winrm_server_cert_validation=ignore'"
}

output "spot_cost_estimate" {
  description = "Estimated hourly cost based on spot_price setting"
  value       = "Spot price ceiling: $${var.spot_price}/hour. Actual spot price varies with supply/demand."
}