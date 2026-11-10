#!/bin/bash
#SBATCH --job-name=iqm-ghz
#SBATCH --output=/shared/user/%x-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --licenses=qpu@qc_gateway:1

set -euo pipefail

: "${IQM_SERVER_URL:=https://host.docker.internal:8000}"
: "${REQUESTS_CA_BUNDLE:=/shared/user/keycloak.crt}"
export IQM_SERVER_URL REQUESTS_CA_BUNDLE

echo "host=$(hostname -s)"
echo "slurm_job_id=${SLURM_JOB_ID}"
echo "iqm_server_url=${IQM_SERVER_URL}"
echo "license=${SLURM_JOB_LICENSES:-<unset>}"
echo "token_injected=$([ -n "${IQM_TOKEN:-}" ] && echo yes || echo no)"

/opt/venv/bin/python /shared/user/slurm_iqm_job.py
