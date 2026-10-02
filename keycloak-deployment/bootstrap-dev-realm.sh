#!/usr/bin/env bash
# Bootstrap the dev Keycloak with the realm/client/roles/users the quantum
# stack expects. Idempotent: existing objects are left in place.
#
# Usage: ./bootstrap-dev-realm.sh
# Reads KC_BOOTSTRAP_ADMIN_PASSWORD from secret_conf.dev.env.
# Generated test-user passwords are stored in dev-credentials.env (gitignored).
#
# Creates:
#   realm  cortex
#   client test-frontend  (public, standard flow + direct access grants,
#                          redirect/origins "*" — DEV ONLY)
#   realm roles: cortex_user, pulla_user, platform-admin, platform-ro-admin
#   users: testadmin (platform-admin, cortex_user)
#          testuser  (cortex_user, pulla_user)
set -euo pipefail

REALM=${REALM:-cortex}
CLIENT=${CLIENT_ID:-test-frontend}
CONTAINER=${CONTAINER:-keycloak_web_dev}

# shellcheck disable=SC1091
source ./secret_conf.dev.env
: "${KC_BOOTSTRAP_ADMIN_PASSWORD:?not set in secret_conf.dev.env}"

if [ -f dev-credentials.env ]; then
  # shellcheck disable=SC1091
  source ./dev-credentials.env
else
  TESTADMIN_PASSWORD=$(openssl rand -hex 12)
  TESTUSER_PASSWORD=$(openssl rand -hex 12)
  TESTMANAGER_PASSWORD=$(openssl rand -hex 12)
  TESTPI_PASSWORD=$(openssl rand -hex 12)
  umask 077
  cat > dev-credentials.env <<EOF
TESTADMIN_PASSWORD=${TESTADMIN_PASSWORD}
TESTUSER_PASSWORD=${TESTUSER_PASSWORD}
TESTMANAGER_PASSWORD=${TESTMANAGER_PASSWORD}
TESTPI_PASSWORD=${TESTPI_PASSWORD}
EOF
  echo "Generated test-user passwords in dev-credentials.env"
fi

KCADM() { docker exec "${CONTAINER}" /opt/keycloak/bin/kcadm.sh "$@"; }

echo "→ kcadm login (master realm)"
KCADM config credentials --server http://localhost:8080/auth \
  --realm master --user admin --password "${KC_BOOTSTRAP_ADMIN_PASSWORD}"

echo "→ realm ${REALM}"
KCADM create realms -s realm="${REALM}" -s enabled=true 2>/dev/null \
  || echo "  (already exists)"

echo "→ realm roles"
for role in cortex_user pulla_user platform-admin platform-ro-admin; do
  KCADM create roles -r "${REALM}" -s name="${role}" 2>/dev/null \
    || echo "  (${role} already exists)"
done

echo "→ client ${CLIENT}"
KCADM create clients -r "${REALM}" \
  -s clientId="${CLIENT}" \
  -s publicClient=true \
  -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=true \
  -s 'redirectUris=["*"]' \
  -s 'webOrigins=["*"]' 2>/dev/null \
  || echo "  (already exists)"

# Second public client, same realm, used to obtain a token for the QC Gateway
# proxy / IQM client SDK (the dashboard's Profile page fetches a token from it
# via SSO). Configurable id; defaults to iqm_client.
IQM_CLIENT=${IQM_CLIENT_ID:-iqm_client}
echo "→ client ${IQM_CLIENT}"
KCADM create clients -r "${REALM}" \
  -s clientId="${IQM_CLIENT}" \
  -s publicClient=true \
  -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=true \
  -s 'redirectUris=["*"]' \
  -s 'webOrigins=["*"]' 2>/dev/null \
  || echo "  (already exists)"

create_user() { # $1=short-name $2=password $3...=roles
  # Username IS the email: the quantum-api jobReport schema requires the
  # gateway-reported username (Keycloak preferred_username) to be an email,
  # matching how production users log in with institutional addresses.
  local shortname=$1 password=$2; shift 2
  local username="${shortname}@example.com"
  echo "→ user ${username}"
  KCADM create users -r "${REALM}" \
    -s username="${username}" -s enabled=true \
    -s email="${username}" -s emailVerified=true \
    -s firstName=Test -s lastName="${shortname}" 2>/dev/null \
    || echo "  (already exists)"
  KCADM set-password -r "${REALM}" --username "${username}" --new-password "${password}"
  for role in "$@"; do
    KCADM add-roles -r "${REALM}" --uusername "${username}" --rolename "${role}"
  done
}

create_user testadmin   "${TESTADMIN_PASSWORD}"   platform-admin cortex_user
create_user testuser    "${TESTUSER_PASSWORD}"    cortex_user pulla_user
# Extra role fixtures; their platform privileges (organization_manager flag,
# project-admin membership) are granted by quantum-api scripts/dev-seed.sh.
create_user testmanager "${TESTMANAGER_PASSWORD:-$(openssl rand -hex 12)}" cortex_user
create_user testpi      "${TESTPI_PASSWORD:-$(openssl rand -hex 12)}"      cortex_user

echo
echo "✅ Realm '${REALM}' bootstrapped. Test-user passwords: dev-credentials.env"
