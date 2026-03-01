# =============================================================================
# chef/cookbooks/base/attributes/default.rb
# Default attribute values for the base cookbook.
# Override in a role, environment, or node JSON using higher-precedence levels.
# Reference: https://docs.chef.io/attributes/
# =============================================================================

# Packages to install on every managed node.
default["base"]["packages"] = %w[
  curl
  wget
  git
  vim
  htop
  unzip
  ca-certificates
]

# Whether to harden SSH daemon configuration.
default["base"]["ssh"]["harden"] = true

# SSH port to listen on (change from 22 to reduce scan noise).
default["base"]["ssh"]["port"] = 22

# Whether to disable root login via SSH.
default["base"]["ssh"]["permit_root_login"] = "no"

# Whether to disable password-based SSH authentication (key-only).
default["base"]["ssh"]["password_authentication"] = "no"

# Admin username to create. Set to nil/empty to skip user creation.
default["base"]["admin_user"] = ""
