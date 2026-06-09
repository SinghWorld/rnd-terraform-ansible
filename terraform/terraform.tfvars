# terraform.tfvars
# Non-sensitive defaults — committed to repo

aws_region                   = "us-east-1"
spot_project_name            = "win-demo"
spot_key_name                = "win-demo-key"
spot_instance_type           = "t3.medium"
spot_price                   = "0.05"
spot_interruption_behavior   = "stop"
winrm_username               = "ansible_admin"