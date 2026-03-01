variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the VM image."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}
