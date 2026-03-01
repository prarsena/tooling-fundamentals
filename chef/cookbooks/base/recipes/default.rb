# =============================================================================
# chef/cookbooks/base/recipes/default.rb
# Default recipe: install baseline packages and harden SSH.
# Run with: chef-client --local-mode --runlist 'recipe[base::default]'
# =============================================================================

# ---------------------------------------------------------------------------
# Package installation
# ---------------------------------------------------------------------------
# `package` is a cross-platform Chef resource. On Debian/Ubuntu it calls apt,
# on RHEL/Fedora it calls dnf, on macOS it calls Homebrew, etc.
node["base"]["packages"].each do |pkg|
  package pkg do
    action :install
  end
end

# ---------------------------------------------------------------------------
# SSH hardening
# ---------------------------------------------------------------------------
if node["base"]["ssh"]["harden"]
  # `template` renders an ERB file from templates/default/sshd_config.erb
  # and writes it to the destination path. The `notifies` statement triggers
  # the SSH service restart handler only when the file changes — idempotent.
  template "/etc/ssh/sshd_config" do
    source   "sshd_config.erb"
    owner    "root"
    group    "root"
    mode     "0600"
    variables(
      port:                    node["base"]["ssh"]["port"],
      permit_root_login:       node["base"]["ssh"]["permit_root_login"],
      password_authentication: node["base"]["ssh"]["password_authentication"]
    )
    # Notify the SSH service resource to restart when this file changes.
    notifies :restart, "service[ssh]", :delayed
  end

  # Manage the SSH service state.
  # `:delayed` means the restart happens at the end of the Chef run, after
  # all resources have been converged — avoids dropping the connection mid-run.
  service "ssh" do
    # Service name differs between Debian ('ssh') and RHEL ('sshd').
    service_name lazy { node["platform_family"] == "rhel" ? "sshd" : "ssh" }
    action       [:enable, :start]
  end
end

# ---------------------------------------------------------------------------
# Admin user creation
# ---------------------------------------------------------------------------
unless node["base"]["admin_user"].to_s.empty?
  user node["base"]["admin_user"] do
    shell   "/bin/bash"
    action  :create
    comment "Admin user managed by Chef"
  end

  # Add user to the sudo/wheel group depending on the OS family.
  group lazy { node["platform_family"] == "rhel" ? "wheel" : "sudo" } do
    action  :modify
    members node["base"]["admin_user"]
    append  true   # Append — do not remove other group members.
  end
end
