# =============================================================================
# puppet/modules/baseline/plans/deploy.pp
# Bolt plan: orchestrated multi-step deployment.
# Plans are written in Puppet DSL or YAML. This example uses Puppet DSL.
#
# Run with: bolt plan run baseline::deploy targets=<host>
# =============================================================================

# @summary Apply the baseline class to targets, with pre- and post-checks.
#
# @param targets  The Bolt targets to deploy to. Accepts a target name,
#                 group name, or comma-separated list.
# @param noop     When true, apply the manifest in no-operation mode.
plan baseline::deploy (
  TargetSpec $targets,
  Boolean    $noop = false,
) {
  # Step 1: Run the pre-deployment health check task.
  # `run_task` executes a Bolt task on all targets in parallel.
  out::message("Step 1/3: Running pre-deployment health check...")
  $pre_check = run_task('baseline::check', $targets,
    _catch_errors => true
  )

  # Log the results of the pre-check.
  $pre_check.each |$result| {
    if $result.ok {
      out::message("  ${result.target}: pre-check OK")
    } else {
      out::message("  ${result.target}: pre-check FAILED — ${result.error.message}")
    }
  }

  # Step 2: Apply the baseline manifest.
  # `apply` compiles and applies a Puppet catalog to the targets.
  out::message("Step 2/3: Applying baseline manifest...")

  if $noop {
    out::message("  (noop mode — no changes will be made)")
  }

  apply($targets, _noop => $noop, _catch_errors => true) {
    class { 'baseline': }
  }

  # Step 3: Run post-deployment verification.
  out::message("Step 3/3: Running post-deployment verification...")
  $post_check = run_task('baseline::check', $targets,
    _catch_errors => true
  )

  $post_check.each |$result| {
    if $result.ok {
      out::message("  ${result.target}: post-check OK — deployment successful")
    } else {
      out::message("  ${result.target}: post-check FAILED — review logs")
    }
  }

  return $post_check
}
