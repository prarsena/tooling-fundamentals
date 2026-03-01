#!/usr/bin/env bash
# =============================================================================
# puppet/modules/baseline/tasks/check.sh
# Bolt task: ad-hoc health check on a target node.
# Run with: bolt task run baseline::check --targets <host>
# =============================================================================
# Bolt tasks receive parameters as environment variables prefixed with PT_
# (Puppet Task). No PT_ parameters are defined for this task — it is purely
# diagnostic and requires no arguments.
# =============================================================================

set -euo pipefail

echo "=== Baseline Health Check ==="
echo ""

# OS information
echo "--- OS ---"
# `uname -a` is POSIX-standard and available on all Unix-like systems.
# On macOS, `uname -m` prints 'arm64' (Apple Silicon) or 'x86_64'.
uname -a

# Uptime
echo ""
echo "--- Uptime ---"
uptime

# Disk usage (root filesystem)
echo ""
echo "--- Disk (/) ---"
# BSD `df` (macOS) and GNU `df` (Linux) both support -h (human-readable).
# `-P` (POSIX output) prevents line-wrapping on long mount point names.
df -hP /

# Memory
echo ""
echo "--- Memory ---"
if command -v free &>/dev/null; then
  # `free` is available on Linux. BSD/macOS use `vm_stat` instead.
  free -h
elif command -v vm_stat &>/dev/null; then
  # macOS-native memory stats.
  vm_stat
fi

# Key services
echo ""
echo "--- SSH daemon ---"
# `pgrep` (available on both macOS and Linux) searches for a process by name.
if pgrep -x sshd &>/dev/null || pgrep -x ssh &>/dev/null; then
  echo "SSH daemon: RUNNING"
else
  echo "SSH daemon: NOT RUNNING"
fi

echo ""
echo "=== Check complete ==="
