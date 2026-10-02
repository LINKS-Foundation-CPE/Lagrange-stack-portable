#!/usr/bin/env bash
# One-click installer for the portable quantum-stack development environment.
#
#   ./install.sh --ip <host-ip> --machine-url <url> --token <iqm-server-token>
#
# Prerequisites: Linux, Docker Engine with the compose v2 plugin, git,
# openssl, curl, python3. Everything else runs in containers.
#
# What it does (idempotent — re-running keeps existing secrets/env files):
#   1. checks prerequisites and that the published ports are free
#   2. initialises git submodules
#   3. generates the shared self-signed certificate + all secrets
#   4. starts Keycloak and bootstraps the realm/client/test users
#   5. starts the QC Gateway stack (gateway, reporter, RustFS, Redis,
#      Postgres, jobs portal, TLS proxy, dashboard)
#   6. starts quantum-api (native TLS) and seeds org/project/test users
#   7. smoke-tests every endpoint
#
# Options:
#   --ip <addr>           host address clients will use (required)
#   --machine-url <url>   IQM machine / mock device URL (required unless kept)
#   --token <token>       IQM_SERVER_TOKEN for the machine (required unless kept)
#   --no-start            generate configs/certs only, start nothing
#
# Variants extend the installer with files in install.d/ rather than by editing
# this script — options of their own included (see install.d/README.md).
set -euo pipefail
cd "$(dirname "$0")"

HOST_IP="" MACHINE_URL="" IQM_TOKEN_VAL="" NO_START=0
EXTRA_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ip) HOST_IP=$2; shift 2;;
    --machine-url) MACHINE_URL=$2; shift 2;;
    --token) IQM_TOKEN_VAL=$2; shift 2;;
    --no-start) NO_START=1; shift;;
    *) EXTRA_ARGS+=("$1"); shift;;  # an install.d hook may claim it
  esac
done
[ -n "${HOST_IP}" ] || { echo "ERROR: --ip <host-ip> is required (the address clients will use; autodetection is unreliable behind NAT)"; exit 2; }

case "$HOST_IP" in
  127.*|localhost|::1)
    echo "NOTE: --ip ${HOST_IP} is a loopback address: the stack will only be usable"
    echo "      from a browser or SDK on this machine. Containers reach each other"
    echo "      through host.docker.internal and the compose network regardless.";;
esac
PORTS="8000 8080 8500 8843 8901 8940 9000"

# Extension points. A file install.d/<stage>-<name>.sh is sourced at <stage>, in
# this script's own shell: it sees and may change its variables, and use its
# helpers (step, set_env, checkout_component; CERT, HOST_IP, ...). Stages, in
# order: options, components, config, seed, post, summary — see
# install.d/README.md. Nothing ships in install.d by default.
run_hooks() { # $1=stage
  local hook
  for hook in install.d/"$1"-*.sh; do
    [ -e "$hook" ] || continue
    # shellcheck disable=SC1090
    . "$hook"
  done
}
run_hooks options
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  echo "unknown option: ${EXTRA_ARGS[0]}"; exit 2
fi
step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
set_env() { # $1=file $2=key $3=value — idempotent upsert, safe to re-run
  if grep -q "^$2=" "$1"; then
    sed -i "s|^$2=.*|$2=$3|" "$1"
  else
    printf '%s=%s\n' "$2" "$3" >> "$1"
  fi
}

step "Checking prerequisites"
[ "$(uname -s)" = "Linux" ] || { echo "ERROR: Linux required"; exit 1; }
for c in docker git openssl curl python3; do
  command -v "$c" >/dev/null || { echo "ERROR: missing prerequisite: $c"; exit 1; }
done
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose v2 plugin missing"; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: cannot talk to the Docker daemon (permissions?)"; exit 1; }
if [ "$NO_START" = 0 ]; then
  for p in $PORTS; do
    if curl -s -m 1 -o /dev/null "http://127.0.0.1:$p" 2>/dev/null || \
       { command -v ss >/dev/null && ss -tln 2>/dev/null | grep -q ":$p "; }; then
      echo "ERROR: port $p is in use. Another stack running? See teardown.sh"; exit 1
    fi
  done
fi
echo "OK"

step "Fetching components (components.env)"
# shellcheck disable=SC1091
source ./components.env
# GITLAB_TOKEN is optional: with it, git gets an HTTP Basic header for HTTPS
# clones (never written into a URL or a checkout's config); without it, git uses
# whatever access the host already has (credential helper, public mirror, ...).
GITLAB_AUTH_HEADER=""
if [ -n "${GITLAB_TOKEN:-}" ]; then
  GITLAB_AUTH_HEADER="Authorization: Basic $(printf 'oauth2:%s' "$GITLAB_TOKEN" | \
    python3 -c 'import base64,sys; print(base64.b64encode(sys.stdin.buffer.read()).decode())')"
fi
gitlab_git() { # $1=HTTPS repository URL; remaining arguments are passed to git
  local repo_url=$1 git_config_url
  shift
  if [ -z "$GITLAB_AUTH_HEADER" ]; then
    git "$@"
    return
  fi
  git_config_url=$(python3 - "$repo_url" <<'PY'
from urllib.parse import urlsplit
import sys

url = urlsplit(sys.argv[1])
if url.scheme != "https" or not url.hostname or url.username or url.password:
    raise SystemExit(1)
host = f"[{url.hostname}]" if ":" in url.hostname else url.hostname
if url.port:
    host += f":{url.port}"
print(f"https://{host}/")
PY
  ) || {
    echo "ERROR: component repository URL must be HTTPS without embedded credentials: $repo_url"
    exit 1
  }
  GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="http.${git_config_url}.extraheader" \
    GIT_CONFIG_VALUE_0="$GITLAB_AUTH_HEADER" \
    git "$@"
}
checkout_component() { # $1=dir $2=repo $3=ref
  if [ ! -e "$1/.git" ]; then
    if [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
      echo "ERROR: $1 exists but is not a git checkout — remove it and re-run"; exit 1
    fi
    echo "  cloning $1"
    gitlab_git "$2" clone -q "$2" "$1"
  fi
  # Hard-reset the working tree to exactly the requested repo+ref on every run.
  # A plain "git checkout <ref>" on an existing clone keeps a stale local branch
  # (e.g. an old "main") and ignores both the freshly fetched ref and any
  # *_REPO override; forcing __deploy onto the fetched commit makes fresh,
  # up-to-date and stale clones all end up on the requested branch/tag/SHA.
  if gitlab_git "$2" -C "$1" fetch -q "$2" "$3" 2>/dev/null; then
    # ref was directly fetchable (branch, tag, or a SHA the server serves)
    git -C "$1" checkout -q -B __deploy FETCH_HEAD
  else
    # ref not directly fetchable (typically a bare SHA on a server that
    # refuses fetch-by-sha): mirror the branches, then reset onto the ref
    gitlab_git "$2" -C "$1" fetch -q "$2" '+refs/heads/*:refs/remotes/__deploy/*' 2>/dev/null \
      || gitlab_git "$2" -C "$1" fetch -q "$2"
    git -C "$1" checkout -q -B __deploy "$3"
  fi
  echo "  $1 @ $(git -C "$1" rev-parse --short HEAD) ($3)"
}
checkout_component nginx-reverse-proxy "${NGINX_REVERSE_PROXY_REPO}" "${NGINX_REVERSE_PROXY_REF}"
checkout_component quantum-api "${QUANTUM_API_REPO}" "${QUANTUM_API_REF}"
checkout_component quantum-dashboard "${QUANTUM_DASHBOARD_REPO}" "${QUANTUM_DASHBOARD_REF}"
run_hooks components
unset GITLAB_TOKEN GITLAB_AUTH_HEADER
echo "OK"

step "Certificates and secrets"
# A database volume outlives its checkout: delete a component directory (or its
# generated env file) and re-run, and the new random password no longer matches
# the one the volume was initialised with — Keycloak or a backend then fails
# with "password authentication failed". Catch it before generating anything.
leftover_volume() { # $1=secrets file about to be generated $2=volume name
  if [ ! -f "$1" ] && [ -n "$(docker volume ls -q --filter "name=^$2\$")" ]; then
    echo "ERROR: data volume '$2' is left over from a previous install, but $1"
    echo "       (the password it was created with) is gone. If that data can go:"
    echo "         ./teardown.sh --volumes     (or: docker volume rm $2)"
    echo "       then re-run the installer."
    exit 1
  fi
}
leftover_volume keycloak-deployment/secret_conf.dev.env keycloak-deployment_postgres_data_dev
leftover_volume nginx-reverse-proxy/.env.dev nginx-reverse-proxy_postgres_data_dev
leftover_volume quantum-api/.env quantum-api_postgres_data
if [ ! -f keycloak-deployment/certs/keycloak.crt ]; then
  (cd keycloak-deployment && ./gen-dev-certs.sh "$HOST_IP")
else
  echo "certs/keycloak.crt exists — keeping it"
fi
CERT="$(pwd)/keycloak-deployment/certs/keycloak.crt"

if [ ! -f keycloak-deployment/secret_conf.dev.env ]; then
  PG=$(openssl rand -hex 16)
  umask 077
  cat > keycloak-deployment/secret_conf.dev.env <<EOF
KC_BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -hex 16)
KC_DB_PASSWORD=${PG}
POSTGRES_PASSWORD=${PG}
EOF
  echo "generated keycloak-deployment/secret_conf.dev.env"
else
  echo "keycloak secrets exist — keeping them"
fi

if [ ! -f nginx-reverse-proxy/.env.dev ]; then
  [ -n "${MACHINE_URL}" ] || { echo "ERROR: --machine-url required on first install"; exit 2; }
  # httpx cannot build a request from a bare host name, so a scheme-less value
  # yields a gateway that answers /health but 502s every proxied call with
  # "Request URL is missing an 'http://' or 'https://' protocol" — and the smoke
  # tests below only probe /health, so the install looks clean. Caught this way
  # on 2026-08-20.
  case "${MACHINE_URL}" in
    http://*|https://*) ;;
    *) echo "ERROR: --machine-url must include a scheme, e.g. https://${MACHINE_URL}"; exit 2;;
  esac
  [ -n "${IQM_TOKEN_VAL}" ] || { echo "ERROR: --token required on first install"; exit 2; }
  sed -e "s/192\\.0\\.2\\.10/${HOST_IP}/g" \
      -e "s|^MACHINE_URL=.*|MACHINE_URL=${MACHINE_URL}|" \
      -e "s|^IQM_SERVER_TOKEN=.*|IQM_SERVER_TOKEN=${IQM_TOKEN_VAL}|" \
      -e "s|^MIDDLEWARE_MODE=.*|MIDDLEWARE_MODE=production|" \
      -e "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=$(openssl rand -hex 12)|" \
      -e "s|^APP_PASSWORD=.*|APP_PASSWORD=$(openssl rand -hex 12)|" \
      -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 12)|" \
      -e "s|^#VITE_|VITE_|" \
      nginx-reverse-proxy/env.dev.example > nginx-reverse-proxy/.env.dev
  echo "generated nginx-reverse-proxy/.env.dev"
else
  echo "gateway .env.dev exists — keeping it"
fi

# The containers dial Keycloak and the object store themselves. --ip is the
# address *clients* use, which from inside a container may be unroutable (a
# loopback address is the container itself). Keycloak's keys are fetched through
# host.docker.internal (a SAN on the dev cert); the issuer stays --ip-based,
# since it is only compared with the tokens browsers obtain. The S3 client talks
# to RustFS on the compose network; the links it hands out keep MINIO_SERVER_URL.
set_env nginx-reverse-proxy/.env.dev KEYCLOAK_JWKS_URL \
  https://host.docker.internal:8843/auth/realms/cortex/protocol/openid-connect/certs
set_env nginx-reverse-proxy/.env.dev S3_ENDPOINT_URL http://rustfs:9000
# The same, under the name gateways before nginx-reverse-proxy !55 read. Drop it
# once NGINX_REVERSE_PROXY_REF is at or past !55.
set_env nginx-reverse-proxy/.env.dev MINIO_INTERNAL_URL http://rustfs:9000


if [ ! -f quantum-api/.env ]; then
  umask 077
  cat > quantum-api/.env <<EOF
API_PORT=8500
# Reached from inside the quantum-api container, where \${HOST_IP} may be
# unroutable (e.g. 127.0.0.1 is the container itself). host.docker.internal is
# mapped to the host gateway by the quantum-api dev overlay's extra_hosts and
# is a SAN on the shared self-signed dev cert. Browser-facing URLs below stay
# \${HOST_IP}-based.
KEYCLOAK_BASE_URL=https://host.docker.internal:8843/auth
KEYCLOAK_REALM=cortex
BACKEND_SECRET=$(openssl rand -hex 32)
CORS_ORIGIN=https://${HOST_IP}:8080
DB_HOST=quantum-api-db
DB_PORT=5432
POSTGRES_PASSWORD=$(openssl rand -hex 16)
SSL_CERT=/certs/keycloak.crt
SSL_KEY=/certs/keycloak.key
EOF
  echo "generated quantum-api/.env"
else
  echo "quantum-api .env exists — keeping it"
fi
run_hooks config

if [ "$NO_START" = 1 ]; then
  step "--no-start: configuration generated, nothing started"
  exit 0
fi

step "Starting Keycloak"
(cd keycloak-deployment && KC_DEV_HOSTNAME="$HOST_IP" docker compose -f docker-compose.dev.yaml up -d)
printf "waiting for Keycloak"
for _ in $(seq 1 60); do
  curl -s --cacert "$CERT" -m 3 -o /dev/null "https://${HOST_IP}:8843/auth/realms/master" && break
  printf .; sleep 3
done; echo
curl -sf --cacert "$CERT" -o /dev/null "https://${HOST_IP}:8843/auth/realms/master" \
  || { echo "ERROR: Keycloak did not come up; docker logs keycloak_web_dev"; exit 1; }
(cd keycloak-deployment && ./bootstrap-dev-realm.sh)

step "Starting the QC Gateway stack"
(cd nginx-reverse-proxy && docker compose -f docker-compose.dev.yaml --profile dashboard up -d --build)

step "Starting quantum-api"
# The API first, WITHOUT the migrator: quantum-api's migrations are incremental
# on top of the schema `sequelize.sync()` creates at boot, so on a fresh database
# the very first migration fails with "No description found for jobs table" — and
# because migrate runs to completion regardless, the deployment would silently end
# up unmigrated (missing later columns, and jobReport 500s on them).
(cd quantum-api && docker compose -f docker-compose.yaml -f docker-compose.tls-dev.yaml \
  up -d --build quantum-api-db quantum-api)
printf "waiting for quantum-api"
for _ in $(seq 1 40); do
  curl -s --cacert "$CERT" -m 3 -o /dev/null "https://${HOST_IP}:8500/metrics/jobs" && break
  printf .; sleep 3
done; echo

step "Running quantum-api migrations"
# Now that the schema exists, apply the migrations that alter it. Failures here
# are worth seeing: an unmigrated database looks fine until a later column is
# touched at runtime.
(cd quantum-api && docker compose -f docker-compose.yaml -f docker-compose.tls-dev.yaml \
  run --rm quantum-api-migrate) || echo "WARNING: migrations reported an error — check the output above"

step "Seeding organization, project, and test users"
# shellcheck disable=SC1091
source keycloak-deployment/dev-credentials.env
(cd quantum-api && \
  API_URL="https://${HOST_IP}:8500" \
  KEYCLOAK_URL="https://${HOST_IP}:8843/auth" \
  ADMIN_PASS="${TESTADMIN_PASSWORD}" TEST_PASS="${TESTUSER_PASSWORD}" \
  MANAGER_PASS="${TESTMANAGER_PASSWORD:-}" PI_PASS="${TESTPI_PASSWORD:-}" \
  ./scripts/dev-seed.sh)
run_hooks seed


step "Smoke tests"
ok=1
for u in "8000/health" "8500/metrics/jobs" "8080/" "8940/" "9000/minio/health/live" "8843/auth/realms/cortex"; do
  code=$(curl -s --cacert "$CERT" -m 10 -o /dev/null -w '%{http_code}' "https://${HOST_IP}:${u}" || true)
  printf '  https://%s:%-28s %s\n' "$HOST_IP" "$u" "$code"
  [ "$code" = "200" ] || ok=0
done
[ "$ok" = 1 ] || { echo "ERROR: some endpoints failed — check docker ps / logs"; exit 1; }
run_hooks post

step "Done"
cat <<EOF
Dashboard      https://${HOST_IP}:8080   (accept the self-signed cert on :8843, :8500 and :8080 first)
Gateway (IQM)  https://${HOST_IP}:8000
Keycloak       https://${HOST_IP}:8843/auth   (admin password: keycloak-deployment/secret_conf.dev.env)
RustFS console https://${HOST_IP}:8901        (credentials: nginx-reverse-proxy/.env.dev)

Test users     testadmin@example.com / testuser@example.com
               passwords in keycloak-deployment/dev-credentials.env

Try it:        test/01_hello_world_dev.ipynb
EOF
run_hooks summary
