###############################################################
# spot-variables.tf
# Variables for Windows EC2 Spot Instance
###############################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "spot_project_name" {
  description = "Prefix for all spot instance resource names"
  type        = string
}

variable "spot_key_name" {
  description = "Name for the EC2 Key Pair (created by Terraform)"
  type        = string
}

variable "spot_instance_type" {
  description = "EC2 instance type — t3.medium minimum for Windows"
  type        = string
}

variable "spot_price" {
  description = "Maximum hourly price ($) you're willing to pay for the spot instance"
  type        = string
}

variable "spot_interruption_behavior" {
  description = "Behavior when spot instance is interrupted: stop | hibernate | terminate"
  type        = string
}

variable "winrm_username" {
  description = "Local Windows admin user Ansible will connect as"
  type        = string
}

variable "winrm_password" {
  description = "Password for the WinRM/Ansible local admin account"
  type        = string
  sensitive   = true
}