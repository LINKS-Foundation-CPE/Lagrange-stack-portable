# shellcheck shell=bash
# Sourced by install.sh at the 'options' stage (install.d/README.md).
# Sets variables install.sh reads after this hook returns.
# shellcheck disable=SC2034
#
# --with-slurm: also deploy the SLURM / Sqed (HPC) variant.
# --cluster-user <name>: the SLURM account jobs are reported under, seeded in
#   Keycloak and quantum-api (default `user`, the only unprivileged account in
#   the test bed's SLURM image).
WITH_SLURM=${WITH_SLURM:-0}
CLUSTER_USER=${CLUSTER_USER:-user}
# The SLURM account the cluster user's jobs are billed to: the project the
# quantum-api seed creates.
CLUSTER_PROJECT=${CLUSTER_PROJECT:-dev-project}
_rest=()
while [ ${#EXTRA_ARGS[@]} -gt 0 ]; do
  case "${EXTRA_ARGS[0]}" in
    --with-slurm) WITH_SLURM=1; EXTRA_ARGS=("${EXTRA_ARGS[@]:1}");;
    --cluster-user) CLUSTER_USER=${EXTRA_ARGS[1]:?--cluster-user needs a name}; EXTRA_ARGS=("${EXTRA_ARGS[@]:2}");;
    *) _rest+=("${EXTRA_ARGS[0]}"); EXTRA_ARGS=("${EXTRA_ARGS[@]:1}");;
  esac
done
EXTRA_ARGS=(${_rest[@]+"${_rest[@]}"})
unset _rest

if [ "$WITH_SLURM" = 1 ]; then
  # The SLURM headnode publishes SSH on 2222.
  PORTS="$PORTS 2222"
fi
