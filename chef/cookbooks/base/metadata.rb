# =============================================================================
# chef/cookbooks/base/metadata.rb
# Cookbook metadata. Required by Chef Infra and Test Kitchen.
# =============================================================================

name             "base"
maintainer       "DevOps Stack"
maintainer_email "ops@example.com"
license          "Apache-2.0"
description      "Baseline OS configuration: packages, users, SSH hardening."
version          "0.1.0"

# The `chef_version` constraint ensures this cookbook is only run with
# a compatible version of the Chef Infra Client.
chef_version ">= 17.0"

# Supported platforms. Test Kitchen uses these to select the VM image.
supports "ubuntu", ">= 22.04"
supports "debian", ">= 12.0"
supports "redhat", ">= 9.0"
supports "centos", ">= 9.0"
supports "fedora"

# Cookbook dependencies (installed automatically by `berks install` or
# `chef-client --local-mode` when listed here).
# depends "apt",  "~> 7.0"
