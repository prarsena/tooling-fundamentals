# =============================================================================
# chef/cookbooks/base/test/integration/default/default_test.rb
# InSpec integration tests for the base cookbook.
# Run with: kitchen verify  (after `kitchen converge`)
# Reference: https://docs.chef.io/inspec/
# =============================================================================

# ---------------------------------------------------------------------------
# Verify baseline packages are installed
# ---------------------------------------------------------------------------
%w[curl wget git vim htop unzip].each do |pkg|
  describe package(pkg) do
    it { should be_installed }
  end
end

# ---------------------------------------------------------------------------
# Verify SSH daemon configuration
# ---------------------------------------------------------------------------
describe file("/etc/ssh/sshd_config") do
  it     { should exist }
  it     { should be_file }
  its("owner") { should eq "root" }
  its("mode")  { should cmp "0600" }
  # Ensure password authentication is disabled for SSH hardening.
  its("content") { should match /PasswordAuthentication no/ }
  # Ensure root login is disabled.
  its("content") { should match /PermitRootLogin no/ }
end

# ---------------------------------------------------------------------------
# Verify SSH service is running
# ---------------------------------------------------------------------------
describe service("ssh") do
  it { should be_installed }
  it { should be_enabled }
  it { should be_running }
end
