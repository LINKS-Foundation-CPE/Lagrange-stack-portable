#!/usr/bin/env bash
# Tear down the portable dev environment.
#
#   ./teardown.sh            stop and remove containers (data volumes kept)
#   ./teardown.sh --volumes  also delete data volumes (Keycloak realm, DBs, Redis)
#   ./teardown.sh --purge    volumes + generated secrets, env files, certificates
set -euo pipefail
cd "$(dirname "$0")"

VOL="" PURGE=0
case "${1:-}" in
  --volumes) VOL="-v";;
  --purge) VOL="-v"; PURGE=1;;
  "") ;;
  *) echo "usage: teardown.sh [--volumes|--purge]"; exit 2;;
esac

# "<directory>:<compose flags>" for every stack to bring down. A variant adds its
# own from teardown.d/*.sh (see install.d/README.md).
SPECS=(
  "nginx-reverse-proxy:-f docker-compose.dev.yaml --profile dashboard"
  "quantum-api:-f docker-compose.yaml -f docker-compose.tls-dev.yaml"
  "keycloak-deployment:-f docker-compose.dev.yaml"
)
for hook in teardown.d/*.sh; do
  [ -e "$hook" ] || continue
  # shellcheck disable=SC1090
  . "$hook"
done
for spec in "${SPECS[@]}"; do
  dir=${spec%%:*}; flags=${spec#*:}
  if [ -d "$dir" ]; then
    echo "== $dir"
    # shellcheck disable=SC2086
    (cd "$dir" && docker compose $flags down $VOL --remove-orphans) || true
  fi
done

if [ "$PURGE" = 1 ]; then
  echo "== purging generated files"
  rm -f keycloak-deployment/secret_conf.dev.env keycloak-deployment/dev-credentials.env
  rm -rf keycloak-deployment/certs
  rm -f nginx-reverse-proxy/.env.dev quantum-api/.env
  # The object store's data belongs to the RustFS container's user (uid
  # 10001), not to whoever runs this: remove it from a container.
  if [ -d nginx-reverse-proxy/minio-data ]; then
    docker run --rm -v "$PWD/nginx-reverse-proxy:/w" alpine rm -rf /w/minio-data
  fi
fi
echo "done"
