# =============================================================================
# terraform/modules/example-vm/main.tf
# Reusable module: provision a minimal EC2 instance (or swap the resource
# block for another provider's VM resource as needed).
# =============================================================================

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = {
    Name = "${var.name_prefix}-vm"
  }
}
