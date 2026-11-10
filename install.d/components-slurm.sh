# shellcheck shell=bash
# Sourced by install.sh at the 'components' stage (install.d/README.md).

if [ "$WITH_SLURM" = 1 ]; then
  # The variant's two extra components. The gateway, quantum-api and the
  # dashboard are the ones components.env names: Sqed is their configuration
  # (config-slurm.sh, post-slurm.sh), not other code.
  # shellcheck disable=SC1091
  source ./components-sqed.env
  checkout_component slurm-docker-compose "${SLURM_REPO}" "${SLURM_REF}"
  checkout_component prolog-epilog "${PROLOG_EPILOG_REPO}" "${PROLOG_EPILOG_REF}"
fi
