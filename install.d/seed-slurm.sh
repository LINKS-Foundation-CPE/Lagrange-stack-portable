# shellcheck shell=bash
# Sourced by install.sh at the 'seed' stage (install.d/README.md).

if [ "$WITH_SLURM" = 1 ]; then
  step "Seeding the cluster user '${CLUSTER_USER}'"
  # A SLURM job is reported under the *cluster* account that ran it, not an
  # e-mail address, and quantum-api rejects a report whose user it does not
  # know. So the same name has to exist as a Keycloak user — that is also how
  # the person logs into the portal to find their jobs — and as a row in the
  # backend, which is created the first time that user authenticates.
  #
  # The Keycloak user is deliberately given NO e-mail: Keycloak validates the
  # format of that field, and the identity here is a bare account name.
  # quantum-api falls back to `preferred_username` for exactly this case.
  KC_URL="https://${HOST_IP}:8843/auth"
  API="https://${HOST_IP}:8500"
  # shellcheck disable=SC1091
  source keycloak-deployment/secret_conf.dev.env
  json() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

  KC_ADMIN_TOKEN=$(curl -skf "${KC_URL}/realms/master/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=admin-cli -d username=admin \
    --data-urlencode password="${KC_BOOTSTRAP_ADMIN_PASSWORD}" | json "['access_token']") \
    || { echo "ERROR: could not get a Keycloak admin token"; exit 1; }
  kc_admin() { # $1=method $2=path $3=body(optional)
    if [ -n "${3:-}" ]; then
      curl -sk -X "$1" "${KC_URL}/admin/realms/cortex$2" \
        -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
        -H "Content-Type: application/json" -d "$3"
    else
      curl -sk -X "$1" "${KC_URL}/admin/realms/cortex$2" \
        -H "Authorization: Bearer ${KC_ADMIN_TOKEN}"
    fi
  }

  # Make the realm accept an account with nothing but a username. Keycloak's
  # declarative user profile requires e-mail, first and last name of anyone
  # logging in as themselves, and an account missing them is "not fully set up":
  # the password grant is refused outright. A cluster account has none of the
  # three, so the requirement has to go before the user can authenticate at all.
  kc_admin GET /users/profile > "${TMP_PROFILE:=$(mktemp)}"
  python3 - "$TMP_PROFILE" <<'PROFILE'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    profile = json.load(fh)
relaxed = [
    a["name"]
    for a in profile.get("attributes", [])
    if a["name"] in ("email", "firstName", "lastName") and a.pop("required", None)
]
with open(path, "w") as fh:
    json.dump(profile, fh)
print("  optional now:", ", ".join(relaxed) if relaxed else "(already relaxed)")
PROFILE
  kc_admin PUT /users/profile "$(cat "$TMP_PROFILE")" >/dev/null
  rm -f "$TMP_PROFILE"

  # Keep the password across re-runs, like every other generated secret here.
  if ! grep -q '^CLUSTERUSER_PASSWORD=' keycloak-deployment/dev-credentials.env; then
    printf 'CLUSTERUSER_PASSWORD=%s\n' "$(openssl rand -hex 12)" \
      >> keycloak-deployment/dev-credentials.env
  fi
  # shellcheck disable=SC1091
  source keycloak-deployment/dev-credentials.env

  KC_UID=$(kc_admin GET "/users?username=${CLUSTER_USER}&exact=true" \
    | python3 -c "import json,sys;u=json.load(sys.stdin);print(u[0]['id'] if u else '')")
  if [ -z "${KC_UID}" ]; then
    kc_admin POST /users \
      "{\"username\":\"${CLUSTER_USER}\",\"enabled\":true,\"emailVerified\":false}" >/dev/null
    KC_UID=$(kc_admin GET "/users?username=${CLUSTER_USER}&exact=true" \
      | python3 -c "import json,sys;u=json.load(sys.stdin);print(u[0]['id'] if u else '')")
    [ -n "${KC_UID}" ] || { echo "ERROR: could not create Keycloak user '${CLUSTER_USER}'"; exit 1; }
    echo "  created Keycloak user '${CLUSTER_USER}' (no e-mail, by design)"
  else
    echo "  Keycloak user '${CLUSTER_USER}' exists"
  fi
  kc_admin PUT "/users/${KC_UID}/reset-password" \
    "{\"type\":\"password\",\"value\":\"${CLUSTERUSER_PASSWORD}\",\"temporary\":false}" >/dev/null
  # Same realm roles as the regular test user, so this account can also drive
  # the machine directly if a deployment ever wants it to.
  for role in cortex_user pulla_user; do
    rep=$(kc_admin GET "/roles/${role}")
    case "$rep" in
      *'"name"'*) kc_admin POST "/users/${KC_UID}/role-mappings/realm" "[${rep}]" >/dev/null;;
      *) echo "  WARNING: realm role ${role} not found — skipping";;
    esac
  done

  # First authentication creates the backend row keyed on the username.
  CLUSTER_KC_TOKEN=$(curl -skf "${KC_URL}/realms/cortex/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=test-frontend -d username="${CLUSTER_USER}" \
    --data-urlencode password="${CLUSTERUSER_PASSWORD}" | json "['access_token']") \
    || { echo "ERROR: cluster user '${CLUSTER_USER}' cannot authenticate against Keycloak"; exit 1; }
  curl -skf -X POST "${API}/auth/token" -H "Authorization: Bearer ${CLUSTER_KC_TOKEN}" >/dev/null \
    || { echo "ERROR: quantum-api rejected the cluster user's token"; exit 1; }

  # Give it an organization: projects named by a job report are created there,
  # and this is the last moment an API exists to set it.
  BE_ADMIN=$(curl -skf "${KC_URL}/realms/cortex/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=test-frontend -d username=testadmin@example.com \
    --data-urlencode password="${TESTADMIN_PASSWORD}" | json "['access_token']")
  BE_ADMIN=$(curl -skf -X POST "${API}/auth/token" -H "Authorization: Bearer ${BE_ADMIN}" | json "['token']")
  CLUSTER_DB_ID=$(curl -sk "${API}/api/users" -H "Authorization: Bearer ${BE_ADMIN}" \
    | python3 -c "import json,sys;u=[x for x in json.load(sys.stdin) if x['email']=='${CLUSTER_USER}'];print(u[0]['id'] if u else '')")
  ORG_ID=$(curl -sk "${API}/api/organizations" -H "Authorization: Bearer ${BE_ADMIN}" \
    | python3 -c "import json,sys;o=json.load(sys.stdin);print(o[0]['id'] if o else '')")
  if [ -n "${CLUSTER_DB_ID}" ] && [ -n "${ORG_ID}" ]; then
    curl -sk -X PUT "${API}/api/users/${CLUSTER_DB_ID}" \
      -H "Authorization: Bearer ${BE_ADMIN}" -H "Content-Type: application/json" \
      -d "{\"organization_id\":${ORG_ID}}" >/dev/null
    echo "  backend user '${CLUSTER_USER}' (id ${CLUSTER_DB_ID}) in organization ${ORG_ID}"
  else
    echo "  WARNING: could not place '${CLUSTER_USER}' in an organization (user=${CLUSTER_DB_ID:-?} org=${ORG_ID:-?})"
    echo "           job reports naming a new project will be rejected until it has one"
  fi

  # A job is billed to its SLURM account, which the cluster step below creates
  # as '${CLUSTER_PROJECT}' — the project the seed made. Member of it, and with it
  # as default project for a job that reaches the gateway without an account:
  # without either, quantum-api refuses the job's first report and every later
  # one fails with "jobid ... not found".
  PROJ_ID=$(curl -sk "${API}/api/projects" -H "Authorization: Bearer ${BE_ADMIN}" \
    | python3 -c "import json,sys;p=[x['id'] for x in json.load(sys.stdin) if x['name']=='${CLUSTER_PROJECT}'];print(p[0] if p else '')")
  if [ -n "${PROJ_ID}" ]; then
    curl -sk -X POST "${API}/api/projects/${PROJ_ID}/users" \
      -H "Authorization: Bearer ${BE_ADMIN}" -H "Content-Type: application/json" \
      -d "{\"email\":\"${CLUSTER_USER}\",\"admin\":false}" >/dev/null
    BE_CLUSTER=$(curl -skf -X POST "${API}/auth/token" -H "Authorization: Bearer ${CLUSTER_KC_TOKEN}" | json "['token']")
    curl -sk -X PUT "${API}/api/own/default_project" \
      -H "Authorization: Bearer ${BE_CLUSTER}" -H "Content-Type: application/json" \
      -d "{\"default_project_id\":${PROJ_ID}}" >/dev/null
    echo "  '${CLUSTER_USER}' is a member of '${CLUSTER_PROJECT}' (id ${PROJ_ID}), its default project"
  else
    echo "  WARNING: project '${CLUSTER_PROJECT}' not found — '${CLUSTER_USER}' has no default project"
  fi
fi
