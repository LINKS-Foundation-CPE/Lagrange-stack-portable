# shellcheck shell=bash
# Sourced by install.sh at the 'config' stage (install.d/README.md).

if [ "$WITH_SLURM" = 1 ]; then
  # Configure the gateway for the sqed (HPC/SLURM) variant. Idempotent upsert
  # so re-runs don't duplicate lines. The default (Lagrange) path never sets
  # these, so the gateway keeps its shipped SITE_PLUGIN=spark behaviour.
  set_env nginx-reverse-proxy/.env.dev SITE_PLUGIN sqed
  set_env nginx-reverse-proxy/.env.dev AUTH_PLUGINS keycloak,sqed
  # Both roles granted statically: an HPC-only deployment has
  # no surface for setting the per-user pulla_user flag, so a backend lookup would
  # always return the defaults anyway. Set SQED_ROLES_LOOKUP_URL instead for a
  # deployment that does want the per-user grant.
  set_env nginx-reverse-proxy/.env.dev SQED_DEFAULT_ROLES cortex_user,pulla_user
  echo "configured gateway .env.dev for the sqed variant (SITE_PLUGIN=sqed)"
fi

if [ "$WITH_SLURM" = 1 ] && ! grep -q '^USERNAME_FORMAT=' quantum-api/.env; then
  # Sqed/HPC deployments bill jobs to SLURM cluster account names, which are not
  # e-mail addresses (the token record carries SLURM_JOB_USER, and the job
  # reporter posts it as the username). quantum-api FREEZES this choice in its
  # system_configs table on first boot and refuses to start on a conflicting
  # value, so it is set before quantum-api is ever started — and only then.
  if [ -z "$(docker volume ls -q --filter 'name=^quantum-api_postgres_data$')" ]; then
    set_env quantum-api/.env USERNAME_FORMAT any
    echo "  set USERNAME_FORMAT=any for the sqed variant (database not created yet)"
  else
    cat <<'USERNAMENOTE'
  WARNING: the sqed variant needs USERNAME_FORMAT=any in quantum-api/.env, but
           this deployment already has a quantum-api database where the format
           was frozen at first boot — setting it now would make quantum-api
           refuse to start. To convert this deployment:
             docker exec quantum-api-db psql -U quantumapi -d quantum \
               -c "delete from system_configs where key='username_format';"
             echo USERNAME_FORMAT=any >> quantum-api/.env
           then restart quantum-api. Until then, jobs reported with a cluster
           account name (non-email) are rejected by the backend.
USERNAMENOTE
  fi
fi

# Seed with the management surface still mounted, then switch it off in the
# post stage. Matters on a RE-RUN, where .env already carries
# JOB_PORTAL_ONLY=true from the previous install: the seeding step drives the
# very endpoints that flag removes, and would 404 its way out of the installer.
[ "$WITH_SLURM" = 1 ] && set_env quantum-api/.env JOB_PORTAL_ONLY false
