# Contributing to portable-deployment

Thanks for your interest! This repository is the umbrella orchestration for
the portable development environment of the LINKS quantum stack. If you are an
AI assistant working here, also read [CLAUDE.md](CLAUDE.md) — it covers
conventions that are not repeated below.

## Orchestration only

This repo contains **no application code**. It is a component manifest
(`components.env`), a one-click installer (`install.sh`), teardown tooling
(`teardown.sh`), documentation, and a test notebook (`test/`).

Fixes to the gateway, backend, dashboard, or Keycloak setup belong in their
**own repositories** — here you only bump the pins in `components.env`. If a
change requires editing a component's code, open a PR there first, then bump
the pin here once it merges.

## Ways to contribute

- **Component pin bumps** — move a `*_REF` in `components.env` to a newer
  commit on that component's `main`, in a dedicated commit that says what
  moved and why.
- **Installer / teardown improvements** — as long as they keep the guarantees
  below.
- **Documentation** — the README is the operator's entry point; keep it
  accurate against what `install.sh` actually does.
- **Test notebook** — extend `test/` with additional end-to-end checks.

## Guarantees to preserve

- **`install.sh` stays idempotent** — re-running keeps existing secrets, env
  files, and certificates.
- **No new prerequisites** — the only requirements are Linux + Docker (compose
  v2) + `git`, `openssl`, `curl`, `python3`. Don't add others.
- **Never commit secrets** — generated files (`*.env.dev`,
  `secret_conf.dev.env`, `dev-credentials.env`, `certs/`) live inside the
  gitignored component checkouts. Keep them out of version control.
- **Never expose this stack to untrusted networks** — it ships dev
  credentials, permissive CORS/redirect settings, and an object store
  anyone can read by key, by design. Don't add anything that invites production use.

## Testing a change

On a clean Linux box with Docker:

```bash
./install.sh --ip <host-ip> --machine-url https://<mock-or-qc> --token <IQM_SERVER_TOKEN>
```

Then run the hello-world check in `test/01_hello_world_dev.ipynb` (fetches the
self-signed cert, gets a dev Keycloak token, submits a GHZ circuit through the
gateway, and confirms it is billed to `dev-project`). Tear down with
`./teardown.sh --purge` between full runs. A pin bump should be validated by a
clean install + the notebook passing end to end.

## Pull request workflow

1. **Branch** with a descriptive name (`feat/...`, `fix/...`, `chore/pin-...`).
2. **Keep the change focused.** A pin bump is its own commit; don't mix it with
   installer changes.
3. **Explain the `why`** in the commit/PR — for a pin bump, name the component,
   the old/new ref, and what landed.
4. **Open the PR against `main`** with what changed, how you validated it
   (clean install + notebook), and any operator-visible impact.

## License

By contributing, you agree that your contributions will be licensed under the
[European Union Public Licence v. 1.2 (EUPL-1.2)](LICENSE) that covers this
repository. See the Licensing section of [README.md](README.md). Each component
cloned by the installer carries its own licence.
