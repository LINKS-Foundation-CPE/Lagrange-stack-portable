# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses **CalVer** in the form `YYYY.MM.PATCH`:

- `YYYY.MM` is bumped when a release is cut in that year and month. There is
  no obligation to release every month; the date simply records when the
  release happened.
- `.PATCH` is bumped for fix-only follow-up releases within the same month,
  starting at `.0`.

Because this repository is an orchestration umbrella, most changes are either
**component pin bumps** (a `*_REF` moved in `components.env`) or installer /
documentation changes. Entries marked **Breaking:** require operator action on
re-install (a teardown, a new prerequisite, or a changed flag).

## [Unreleased]

## [2026.10.0] — 2026-10-02

### Added
- Component repositories can be fetched over HTTPS with `GITLAB_TOKEN`
  (`read_repository` access), without embedding credentials in repository URLs
  or persisting them in clone configuration.
- `CONTRIBUTING.md`: contribution workflow, the orchestration-only rule, and
  the guarantees the installer must preserve.

### Changed
- **Breaking: the Keycloak is part of this repository.** `keycloak-deployment/`
  holds the environment's own development Keycloak — compose file,
  certificate generator, realm bootstrap — instead of a clone of a separate
  repository, and uses Keycloak's own login theme. `components.env` no longer
  lists it. **Re-install:** `./teardown.sh --purge`, then remove the old
  `keycloak-deployment/` clone (`rm -rf keycloak-deployment`) before pulling,
  or git refuses to overwrite it.
- **The installer has extension points.** `install.sh` sources
  `install.d/<stage>-*.sh` at six stages (options, components, config, seed,
  post, summary) and `teardown.sh` sources `teardown.d/*.sh`, so a variant of
  the environment is a set of added files instead of edits to the scripts.
  Unknown options are offered to the `options` hooks before being rejected.
  Contract in `install.d/README.md`.
- The gateway's S3-client endpoint is set as `S3_ENDPOINT_URL` (the name since
  nginx-reverse-proxy !55), and still as `MINIO_INTERNAL_URL` for the default
  gateway pin until it moves past !55. The old name collided with a line early
  deployments keep in `.env`.
- **Fresh-machine fixes from a colleague's test report.**
  - `GITLAB_TOKEN` is optional: without it Git uses the access the host already
    has.
  - `--ip 127.0.0.1` / `localhost` works: the gateway fetches Keycloak's keys
    through `host.docker.internal` and its S3 client uses
    `S3_ENDPOINT_URL=http://rustfs:9000`, set on every install.
  - A database volume left over from a previous install, whose secrets file is
    gone, stops the installer with the fix instead of failing later with
    "password authentication failed".
- **Breaking: the object store is RustFS, and a fresh install works again.**
  MinIO withdrew its images: `minio/minio` and `minio/mc` at the pinned
  releases no longer pull from any registry, so a fresh `install.sh` failed
  at the gateway stack. `NGINX_REVERSE_PROXY_REF` moves to the gateway's
  first commit with RustFS alone (MinIO retired, CORS set for the job
  portal) — on its `staging` for now, since its `main` still runs MinIO to
  migrate existing deployments. Same ports (8901 console, 9000 S3), same
  `MINIO_*` variables; no migration here, the environment is for fresh
  installs. Re-install over an old one with `./teardown.sh --purge` first.
- `QUANTUM_API_REF`, `QUANTUM_DASHBOARD_REF` and `KEYCLOAK_DEPLOYMENT_REF`
  move to their upstream `main`. The old quantum-api pin had no
  `host.docker.internal` mapping, so on Linux it could not fetch Keycloak's
  keys and rejected every token: a fresh install stopped at seeding with a
  JSON traceback (fixed upstream in `be3f888`). The dashboard and Keycloak
  pins move with it so a fresh install gets one coherent set.
- `NGINX_REVERSE_PROXY_REF` moves on to `64b9079`, which gives the dev
  `calibration-poller` the self-signed cert and the `host.docker.internal`
  mapping: without them it could not reach the object store.
- `NGINX_REVERSE_PROXY_REF` moves on to `d5ecf72` (gateway !53): the gateway's
  S3 client honours `S3_ENDPOINT_URL`, which a loopback `--ip` needs.
- `teardown.sh --purge` removes the object store's data from a container: it
  belongs to RustFS's uid, and a plain `rm -rf` fails on it.

### Fixed
- `--machine-url` is rejected unless it carries an `http://` or `https://`
  scheme. A bare host name produced a gateway that answered `/health` — so the
  installer's smoke tests passed — but 502'd every proxied request with
  "Request URL is missing an 'http://' or 'https://' protocol". Found by
  running a real job through a deployment installed that way.
- `checkout_component` now hard-resets each component checkout to exactly the
  fetched repo+ref on every run (`git checkout -B __deploy` onto the fetched
  commit). Previously an existing clone on a stale local branch (e.g. `main`)
  kept the old commit and silently ignored the fetched ref and any `*_REPO`
  override; fresh, up-to-date and stale clones now all converge on the
  requested branch/tag/SHA.
- Generated `quantum-api/.env` now sets
  `KEYCLOAK_BASE_URL=https://host.docker.internal:8843/auth` instead of the
  `${HOST_IP}`-based URL, which is often unroutable from inside the container
  (e.g. `127.0.0.1`). Browser-facing URLs (CORS, `VITE_*`) stay `${HOST_IP}`-based.

## [2026.07.0] — 2026-07-20

First versioned baseline, capturing the portable development environment at
the point open-sourcing preparation was completed.

### Added
- One-command installer (`install.sh`) and teardown tooling (`teardown.sh`)
  for the full LINKS quantum stack (QC Gateway, quantum-api,
  quantum-dashboard, Keycloak, MinIO, Redis, Postgres) on a bare IP with a
  shared self-signed certificate — no FQDN, DNS, or CA required.
- Component manifest (`components.env`): each component pinned by repo + ref,
  overridable at install time via `GIT_BASE` / per-component variables
  (replaces the earlier git-submodule approach).
- Hello-world end-to-end test notebook (`test/01_hello_world_dev.ipynb`).
- `LICENSE`: European Union Public Licence v. 1.2 (EUPL-1.2), consistent with
  the other components of the stack; README Licensing section and `CLAUDE.md`
  conventions.

[Unreleased]: https://github.com/LINKS-Foundation-CPE/Lagrange-stack-portable/compare/2026.10.0...HEAD
[2026.10.0]: https://github.com/LINKS-Foundation-CPE/Lagrange-stack-portable/releases/tag/2026.10.0
[2026.07.0]: https://github.com/LINKS-Foundation-CPE/Lagrange-stack-portable/releases/tag/2026.07.0
