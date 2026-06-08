###############################################################
# variables.tf
###############################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "win-demo"
}

variable "key_name" {
  description = "Name for the EC2 Key Pair (created by Terraform)"
  type        = string
  default     = "win-demo-key"
}

variable "instance_type" {
  description = "EC2 instance type — t3.medium minimum for Windows"
  type        = string
  default     = "t3.medium"
}

variable "winrm_username" {
  description = "Local Windows admin user Ansible will connect as"
  type        = string
  default     = "ansible_admin"
}

variable "winrm_password" {
  description = "Password for the WinRM/Ansible local admin account"
  type        = string
  sensitive   = true
  # Set via: export TF_VAR_winrm_password="YourStr0ngP@ss!"
}
