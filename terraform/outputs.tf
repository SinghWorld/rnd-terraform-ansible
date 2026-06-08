###############################################################
# outputs.tf
###############################################################

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.windows.id
}

output "public_ip" {
  description = "Public IP — use this for WinRM / RDP"
  value       = aws_instance.windows.public_ip
}

output "public_dns" {
  description = "Public DNS"
  value       = aws_instance.windows.public_dns
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
  value       = "curl -s http://${aws_instance.windows.public_ip}:5985/wsman"
}

output "rdp_connection" {
  description = "RDP target"
  value       = "${aws_instance.windows.public_ip}:3389"
}

output "ansible_inventory_command" {
  description = "Quick test command for Ansible WinRM ping"
  value       = "ansible windows -i '${aws_instance.windows.public_ip},' -m win_ping -e 'ansible_user=ansible_admin ansible_password=<YOUR_PASSWORD> ansible_connection=winrm ansible_winrm_transport=basic ansible_winrm_port=5985 ansible_winrm_scheme=http ansible_winrm_server_cert_validation=ignore'"
}
