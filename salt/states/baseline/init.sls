# =============================================================================
# salt/states/baseline/init.sls
# Baseline state: packages, SSH hardening, user management.
# Run with: salt-call --local --config-dir ../../supporting_files state.apply baseline
# =============================================================================

# ---------------------------------------------------------------------------
# Jinja2 variables
# Salt state files use Jinja2 templating. `grains` contains collected facts
# (OS, arch, memory, etc.). `pillar` contains encrypted per-node secrets.
# ---------------------------------------------------------------------------
{% set is_debian = grains['os_family'] == 'Debian' %}
{% set is_redhat = grains['os_family'] == 'RedHat' %}
{% set ssh_service = 'ssh' if is_debian else 'sshd' %}

# ---------------------------------------------------------------------------
# Package cache refresh
# ---------------------------------------------------------------------------

# Refresh the package database before installing anything.
# On Debian/Ubuntu this is equivalent to `apt-get update`.
{% if is_debian %}
pkg_refresh:
  pkg.uptodate:
    - refresh: true
{% endif %}

# ---------------------------------------------------------------------------
# Baseline packages
# ---------------------------------------------------------------------------

# `pkg.installed` installs a list of packages if they are not already present.
# Salt automatically selects the correct package manager (apt, dnf, pacman).
baseline_packages:
  pkg.installed:
    - pkgs:
      - curl
      - wget
      - git
      - vim
      - htop
      - unzip
      - ca-certificates
    # `require` ensures the package cache is refreshed first on Debian.
    {% if is_debian %}
    - require:
      - pkg: pkg_refresh
    {% endif %}

# ---------------------------------------------------------------------------
# SSH daemon hardening
# ---------------------------------------------------------------------------

# Manage the sshd_config file. Salt compares the managed content with the
# current file; it only writes if there is a difference (idempotent).
/etc/ssh/sshd_config:
  file.managed:
    - source: salt://baseline/files/sshd_config
    - user:   root
    - group:  root
    - mode:   '0600'
    # `watch_in` means the SSH service will restart if this file changes.
    - watch_in:
      - service: {{ ssh_service }}_service

# Ensure the SSH service is running and enabled at boot.
{{ ssh_service }}_service:
  service.running:
    - name:   {{ ssh_service }}
    - enable: true
    - require:
      - pkg: baseline_packages

# ---------------------------------------------------------------------------
# Managed SSH config file (minimal hardened template)
# This file is referenced by `source: salt://baseline/files/sshd_config` above.
# It lives at salt/states/baseline/files/sshd_config.
# ---------------------------------------------------------------------------
