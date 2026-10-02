# Portable deployment — quantum stack development environment

One-command deployment of the full LINKS quantum-computer management stack on
any Linux box with Docker: **QC Gateway** (transparent IQM API proxy with
auth, RBAC, fairness and accounting), **quantum-api** (projects, budgets,
billing), **quantum-dashboard**, a dedicated **Keycloak**, RustFS (S3 object store), Redis and
Postgres — everything on a bare IP with a self-signed certificate. No FQDN,
no DNS, no CA. Point an unmodified IQM client (Qiskit/Cirq/Qrisp) at it and
run circuits against a mock device or a real machine. Developed in the context
of the **QTech Piemonte** strategic initiative.

<a href="https://linksfoundation.com"><img src="docs/assets/logo-links.png" alt="LINKS Foundation" height="60"></a>&nbsp;&nbsp;&nbsp;<a href="https://www.polito.it"><img src="docs/assets/logo-polito.png" alt="Politecnico di Torino" height="60"></a>&nbsp;&nbsp;&nbsp;<a href="https://www.inrim.it"><img src="docs/assets/logo-inrim.jpg" alt="INRIM" height="60"></a>

---

Intended for development and integration experiments — the official
dev/staging environment remains the integration-test target. **Never expose
this stack to untrusted networks**: dev credentials, permissive CORS/redirect
settings, an object store anyone can read by key.

## Prerequisites

- Linux (any distro; tested on Ubuntu 24.04)
- Docker Engine with the compose v2 plugin (`docker compose version` works)
- `git`, `openssl`, `curl`, `python3` (standard on most distros)
- Read access to the component repositories. Either export a GitLab token
  with `read_repository` as `GITLAB_TOKEN` (used as an HTTP header, never stored
  in URLs or Git configuration), or rely on the access Git already has (a
  credential helper, a mirror via `GIT_BASE`).
- ~5 GB disk for images/volumes; outbound network for image pulls
- An IQM machine URL + service token (LINKS mock device, or a real QC)
- Ports **8000, 8080, 8500, 8843, 8901, 8940, 9000** free (everything lives
  in 8000–9000, convenient when only that range is reachable)

## Quick start

```bash
git clone <this-repo>
cd portable-deployment
export GITLAB_TOKEN='your-gitlab-token'   # optional, see Prerequisites
./install.sh --ip <host-ip> --machine-url https://<mock-or-qc> --token <IQM_SERVER_TOKEN>
```

`--ip` is the address browsers and SDKs will use. A loopback address
(`127.0.0.1`, `localhost`) works for a stack used only from the same machine:
the containers never dial `--ip` themselves — they fetch Keycloak's keys
through `host.docker.internal` and reach the object store on the compose
network.

`--ip` is the address clients will use (VM floating IP, LAN address, or
`127.0.0.1` for laptop-local use). The installer is idempotent: re-running
keeps existing secrets, env files and certificates.

Then, once per browser, accept the self-signed certificate on
`https://<ip>:8843`, `https://<ip>:8500` and `https://<ip>:8080`, and log in
to the dashboard at **`https://<ip>:8080`**.

## What you get

| Port | Service | Notes |
|---|---|---|
| 8000 | QC Gateway | point `IQM_SERVER_URL` here; API-identical to the machine |
| 8080 | quantum-dashboard | vite dev server (hot reload on the submodule checkout) |
| 8500 | quantum-api | REST backend; native TLS |
| 8843 | Keycloak | realm `cortex`, client `test-frontend`; admin console under `/auth/admin` |
| 8901 | RustFS console | |
| 8940 | Jobs results portal | static viewer linked from job records |
| 9000 | RustFS S3 API | artifact links point here |

Seeded state: organization **DevOrg** (100 h vault), project **dev-project**
(10 h), users **testadmin@example.com** (platform admin) and
**testuser@example.com** (regular; `dev-project` as default project).
Passwords: `keycloak-deployment/dev-credentials.env`. Keycloak admin password:
`keycloak-deployment/secret_conf.dev.env`.

Architecture in one line: a `tls-proxy` nginx terminates HTTPS for the
gateway stack with one shared self-signed cert (SANs: your IP, `127.0.0.1`,
`localhost`, `host.docker.internal`); quantum-api and Keycloak terminate
their own TLS with the same cert; all services speak plain HTTP inside the
compose networks, so no service config diverges from production. Full detail:
`nginx-reverse-proxy/docs/DEV_DEPLOYMENT.md`.

## Extending the installer

`install.sh` and `teardown.sh` run any hook files they find in `install.d/` and
`teardown.d/`, at fixed stages, so a variant of this environment — an extra
component, a different plugin set — is a set of added files rather than edits to
the installer. The stages and what a hook may rely on are in
[`install.d/README.md`](install.d/README.md).

## Testing with an IQM client

Open **`test/01_hello_world_dev.ipynb`** — the Lagrange hello-world example
adapted to this environment: it fetches the self-signed certificate, obtains
a token from the dev Keycloak (password grant), and runs a GHZ circuit
through the gateway with plain `qiskit-iqm`. The job then shows up in the
dashboard with artifact links, and its QPU milliseconds are billed to
`dev-project`.

The short version, for scripts:

```bash
scp <user>@<ip>:<path-to>/portable-deployment/keycloak-deployment/certs/keycloak.crt .
export REQUESTS_CA_BUNDLE=$PWD/keycloak.crt
export IQM_SERVER_URL=https://<ip>:8000
export IQM_TOKEN=$(curl -s --cacert keycloak.crt \
  https://<ip>:8843/auth/realms/cortex/protocol/openid-connect/token \
  -d grant_type=password -d client_id=test-frontend \
  -d username=testuser@example.com --data-urlencode password='<see dev-credentials.env>' \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
```

Note: access tokens expire after the realm default (~5 min) — re-fetch as
needed. In notebooks, set `REQUESTS_CA_BUNDLE` via `os.environ` **before**
creating the `IQMProvider`.

## Components

| Directory | What it is | Where it comes from |
|---|---|---|
| `nginx-reverse-proxy` | QC Gateway | cloned by the installer, at the pin in `components.env` |
| `quantum-api` | portal backend | cloned by the installer, at the pin in `components.env` |
| `quantum-dashboard` | portal UI (Vite dev server) | cloned by the installer, at the pin in `components.env` |
| `keycloak-deployment` | this environment's Keycloak: compose file, certificate generator, realm bootstrap | **part of this repository**; Keycloak's own login theme |

The certificate `keycloak-deployment/gen-dev-certs.sh` writes to
`keycloak-deployment/certs/` is the one every component trusts.

## Day-2 operations

```bash
./teardown.sh              # stop everything (data volumes kept)
./teardown.sh --volumes    # also drop DBs / realm / Redis
./teardown.sh --purge      # volumes + secrets + certs + env files
./install.sh --ip <ip>     # re-create (existing secrets/envs are reused)
```

Logs: `docker logs <container>` — main containers are
`fastapi-middleware-dev`, `job-reporter-dev`, `quantum-api`,
`keycloak_web_dev`, `tls-proxy-dev`, `rustfs-job-data`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Browser login hangs silently | Self-signed cert not accepted on `:8843` yet — visit it once |
| Dashboard loads, API calls fail | Cert not accepted on `:8500`; or `CORS_ORIGIN` in `quantum-api/.env` doesn't match the dashboard origin |
| `SSLCertVerificationError` in Python | `REQUESTS_CA_BUNDLE` not set **in that process** (notebook kernels don't inherit later shell exports) |
| Circuit fails `compilation_started → failed` | Two-qubit gates must respect the Spark star topology (centre QB3); let the transpiler map |
| Submission → 403 "user not found / no default project" | Seed didn't run — `./install.sh` again or `quantum-api/scripts/dev-seed.sh` |
| `SignatureDoesNotMatch` from the object store | Something rewrote the `Host` header without the port — see `config-dev/nginx-tls.conf` |
| Port in use at install | A previous stack is running — `./teardown.sh` first |
| Keycloak exits with `password authentication failed` | `KC_DB_PASSWORD` ≠ `POSTGRES_PASSWORD` in `secret_conf.dev.env` — they must match; `--purge` and reinstall |

## Licensing

Portable deployment is licensed under the **European Union Public Licence
v. 1.2 (EUPL-1.2)** — see [LICENSE](LICENSE) — consistently with the other
components of the LINKS quantum stack (e.g. QC Gateway). The licence applies
to the files in this repository (installer, configuration, documentation,
test notebook); each submodule carries its own licence.
