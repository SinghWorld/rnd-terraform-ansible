###############################################################
# spot-variables.tf
# Variables for Windows EC2 Spot Instance
###############################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "spot_project_name" {
  description = "Prefix for all spot instance resource names"
  type        = string
  default     = "win-spot-demo"
}

variable "spot_key_name" {
  description = "Name for the EC2 Key Pair (created by Terraform)"
  type        = string
  default     = "win-spot-key"
}

variable "spot_instance_type" {
  description = "EC2 instance type — t3.medium minimum for Windows"
  type        = string
  default     = "t3.medium"
}

variable "spot_price" {
  description = "Maximum hourly price ($) you're willing to pay for the spot instance"
  type        = string
  default     = "0.05" # ~$0.05/hr vs ~$0.05/hr on-demand t3.medium; adjust based on current spot prices
}

variable "spot_interruption_behavior" {
  description = "Behavior when spot instance is interrupted: stop | hibernate | terminate"
  type        = string
  default     = "stop" # 'stop' preserves the instance for restart; 'terminate' removes it
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