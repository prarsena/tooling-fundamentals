# =============================================================================
# terraform/supporting_files/outputs.tf
# Output values exposed after `tofu apply`.
# These can be read with: tofu output -json | jq .
# =============================================================================

output "environment" {
  description = "The active deployment environment."
  value       = var.environment
}

output "random_suffix" {
  description = "A random 8-char hex suffix for uniquely named resources."
  value       = random_id.suffix.hex
}

output "hello_file_path" {
  description = "Absolute path to the generated hello.txt file."
  value       = local_file.hello.filename
}
