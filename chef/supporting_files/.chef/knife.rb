# =============================================================================
# chef/supporting_files/.chef/knife.rb
# knife configuration for this project.
# knife reads this file from <repo>/.chef/knife.rb automatically when you run
# knife from within the repository directory — no ~/.chef/knife.rb needed.
# Reference: https://docs.chef.io/workstation/knife_setup/
# =============================================================================

# ---------------------------------------------------------------------------
# LOCAL-MODE SETTINGS
# When using chef-client --local-mode (ChefZero), no real Infra Server is
# needed. The settings below are for the optional remote server workflow.
# ---------------------------------------------------------------------------

# Path to the cookbook repository root (one level above .chef/).
cookbook_path   [File.expand_path("../../cookbooks", __FILE__)]

# Node name used to identify this workstation to the Chef Infra Server.
# For local-mode only, this can be any string.
node_name       ENV.fetch("CHEF_NODE_NAME", "local-workstation")

# ---------------------------------------------------------------------------
# REMOTE CHEF INFRA SERVER (comment out for local-mode only usage)
# ---------------------------------------------------------------------------
# chef_server_url  "https://chef.example.com/organizations/myorg"
# client_key       File.expand_path("~/.chef/#{node_name}.pem")

# ---------------------------------------------------------------------------
# macOS-SPECIFIC SETTINGS
# ---------------------------------------------------------------------------

# Cache Knife's SSL certificates in ~/Library/Caches/ (macOS standard)
# rather than the default ~/.chef/trusted_certs/ to keep the home directory
# clean and align with macOS conventions for cache data.
trusted_certs_dir File.expand_path("~/Library/Caches/chef/trusted_certs")

# knife[:editor] uses $EDITOR if set; this fallback opens VS Code on macOS.
knife[:editor] = ENV.fetch("EDITOR", "code --wait")

# Turn off SSL verification for local Lab/Lima VMs with self-signed certs.
# NEVER set to :verify_none in production.
# ssl_verify_mode :verify_none
