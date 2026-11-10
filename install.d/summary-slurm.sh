# shellcheck shell=bash
# Sourced by install.sh at the 'summary' stage (install.d/README.md).

if [ "$WITH_SLURM" = 1 ] && [ -d slurm-docker-compose ]; then
  cat <<EOF

SLURM (sqed)   headnode SSH on ${HOST_IP}:2222 (opt-in HPC variant)
               quantum-api JOB_PORTAL_ONLY=true — the portal lists and shows
                 jobs only; no projects/users/admin, and nothing is billed.
                 Unset it in quantum-api/.env and recreate the container to
                 get the full portal back.
               cluster user '${CLUSTER_USER}' seeded in Keycloak and the
                 backend (password: CLUSTERUSER_PASSWORD in
                 keycloak-deployment/dev-credentials.env). Jobs are reported
                 under it, and the project is the SLURM --account they were
                 submitted with — created on first sight.
               gateway SITE_PLUGIN=sqed, AUTH_PLUGINS=keycloak,sqed
               token provisioning: prolog/epilog scripts at /opt/sqed
               verify: sbatch -A <project> -L qpu@qc_gateway:1 \\
                         --wrap "env | grep IQM_TOKEN"
EOF
fi
