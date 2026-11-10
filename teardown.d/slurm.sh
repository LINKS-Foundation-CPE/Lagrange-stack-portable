# shellcheck shell=bash
# Sourced by teardown.sh: the SLURM test bed, when an install --with-slurm
# cloned it (teardown.sh skips a directory that is not there).
SPECS+=("slurm-docker-compose:-p portable-slurm -f docker-compose.yml")
