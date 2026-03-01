# =============================================================================
# puppet/modules/baseline/manifests/init.pp
# Main class for the baseline module.
# Apply with: bolt apply modules/baseline/manifests/init.pp --targets localhost
# =============================================================================

# @summary Baseline OS configuration: packages, SSH hardening, user management.
#
# @param packages         List of packages to ensure are installed.
# @param ssh_harden       Whether to harden SSH daemon configuration.
# @param ssh_port         Port number for the SSH daemon to listen on.
# @param admin_user       Admin username to create. Empty string skips creation.
# @param admin_ssh_pubkey SSH public key to authorise for the admin user.
class baseline (
  Array[String[1]] $packages         = ['curl', 'wget', 'git', 'vim', 'htop', 'unzip'],
  Boolean          $ssh_harden       = true,
  Integer[1,65535] $ssh_port         = 22,
  String           $admin_user       = '',
  String           $admin_ssh_pubkey = '',
) {

  # ---------------------------------------------------------------------------
  # Package installation
  # The `package` resource is cross-platform — Puppet selects the correct
  # provider (apt, yum, dnf, pacman, brew) based on the OS facts.
  # ---------------------------------------------------------------------------
  $packages.each |String $pkg| {
    package { $pkg:
      ensure => installed,
    }
  }

  # ---------------------------------------------------------------------------
  # SSH hardening
  # ---------------------------------------------------------------------------
  if $ssh_harden {

    # Manage the sshd_config file.
    # `augeas` or `file_line` could be used for surgical edits;
    # managing the full file gives reproducible, reviewable state.
    file { '/etc/ssh/sshd_config':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content => epp('baseline/sshd_config.epp', {
        port                    => $ssh_port,
        permit_root_login       => 'no',
        password_authentication => 'no',
      }),
      notify  => Service['sshd'],
    }

    # The SSH service name differs between Debian ('ssh') and RHEL ('sshd').
    # `$facts['os']['family']` is populated by the Facter fact-gathering step.
    $ssh_service = $facts['os']['family'] ? {
      'Debian' => 'ssh',
      default  => 'sshd',
    }

    service { 'sshd':
      ensure => running,
      name   => $ssh_service,
      enable => true,
    }
  }

  # ---------------------------------------------------------------------------
  # Admin user creation
  # ---------------------------------------------------------------------------
  if $admin_user != '' {
    user { $admin_user:
      ensure     => present,
      shell      => '/bin/bash',
      managehome => true,
      comment    => 'Admin user managed by Puppet',
    }

    # Add user to the appropriate sudo group.
    $sudo_group = $facts['os']['family'] ? {
      'RedHat' => 'wheel',
      default  => 'sudo',
    }

    # `stdlib::ensure_packages` from puppetlabs-stdlib installs a package
    # if not already present — used here to ensure sudo is installed.
    package { 'sudo':
      ensure => installed,
    }

    exec { "add-${admin_user}-to-${sudo_group}":
      command => "/usr/sbin/usermod -aG ${sudo_group} ${admin_user}",
      unless  => "/usr/bin/id -nG ${admin_user} | grep -qw ${sudo_group}",
      require => User[$admin_user],
    }

    if $admin_ssh_pubkey != '' {
      ssh_authorized_key { "${admin_user}_key":
        ensure => present,
        user   => $admin_user,
        type   => 'ssh-ed25519',
        key    => $admin_ssh_pubkey,
      }
    }
  }

}
