# =============================================================================
# salt/states/top.sls
# The Salt Top File: maps minions (by ID or glob/regex) to state files.
# This is the entry point when running `state.highstate`.
# Reference: https://docs.saltproject.io/en/latest/ref/states/top.html
# =============================================================================

# 'base' is the default environment (matches the file_roots 'base' key
# in the minion config). Add 'staging' or 'prod' environments as needed.
base:
  # '*' matches ALL minions. States listed here are applied to every target.
  '*':
    - baseline          # Applies states/baseline/init.sls

  # Match by minion ID prefix (glob):
  # 'web*':
  #   - baseline
  #   - webserver

  # Match by OS grain using the 'grain' matcher:
  # 'os:Ubuntu':
  #   - match: grain
  #   - baseline
