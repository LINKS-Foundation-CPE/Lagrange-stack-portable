# CLAUDE.md

Orientation for AI assistants (and new human contributors) working on
**portable-deployment**.

## What this project is

The umbrella repository for the portable development environment of the LINKS
quantum stack: a component manifest (`components.env`, cloned by the
installer), a one-click installer (`install.sh`), teardown tooling
(`teardown.sh`), documentation (`README.md`) and a test notebook (`test/`).
See the README for usage.

Rules of thumb:

- This repo contains **orchestration only** — no application code. Fixes to
  the gateway, backend or dashboard belong in their own repositories; here you
  only bump the pins in `components.env`.
- The environment's **Keycloak lives here**, in `keycloak-deployment/`
  (compose file, certificate generator, realm bootstrap), with Keycloak's own
  login theme. It has nothing to do with any production Keycloak deployment:
  change it here.
- Pins are commit SHAs on `main` of each component. Bump them in
  `components.env` via merge request, with a message saying what moved and
  why. Component checkouts live in gitignored directories cloned by
  `install.sh`.
- Variants extend the installer with hook files in `install.d/` and
  `teardown.d/` (contract in `install.d/README.md`), never by editing
  `install.sh`. A variant that is not part of this environment lives on its own
  branch, as added files only, so merging `main` into it cannot conflict.
- `install.sh` must stay idempotent (re-runs keep existing secrets, env files
  and certificates) and must never require more than Linux + Docker
  (compose v2) + git/openssl/curl/python3. Component clones use HTTPS, with
  an optional `GITLAB_TOKEN` (`read_repository`) as an HTTP header.
- Never commit secrets: generated files (`*.env.dev`, `secret_conf.dev.env`,
  `dev-credentials.env`, `certs/`) live inside the component checkouts and are
  gitignored there.

## Repository layout — private + public

Development happens on a **private GitLab repo**; a public open-source
mirror on **GitHub**, `Lagrange-stack-portable`, is planned (repository not yet created):

| Remote | URL | Purpose |
|--------|-----|---------|
| `origin` | `gitlab.linksfoundation.com:links-iqm-spark/machine-management/portable-deployment.git` | Private development (default push target) |
| `github` | `github.com:LINKS-Foundation-CPE/Lagrange-stack-portable.git` (to be created) | Public open-source mirror |

### Branch mapping

| Branch | Lives on | Pushed to |
|--------|----------|-----------|
| `main` | GitLab `origin` | `origin main` only |
| `public` | Both remotes | `origin public` + `github main` (once created) |

`public` is an **orphan branch** — its history starts from a clean
"Initial public release" squash commit and never includes the private
history. It is fast-forwarded from `main` one commit at a time via
`git cherry-pick`.

### Publishing a commit to GitHub

After merging or committing to `main` on GitLab:

```bash
git checkout public
git cherry-pick <commit-sha>          # repeat for each commit to publish
git push origin public                # update GitLab mirror of public
git push github public:main           # update GitHub main (once the repo exists)
git checkout main
```

Review each cherry-pick before pushing — the `public` branch is the gate
that prevents internal details from leaking to GitHub. Never
`git push github main:main` or rebase `public` onto `main` directly.

### Component-access caveat for the public mirror

`components.env` defaults to the **private GitLab** repositories. A public
clone of this repo works, but `install.sh` can only fetch the components
with GitLab access (or with `GIT_BASE`/per-component overrides pointing at
public mirrors — today only the gateway has one:
`github.com/LINKS-Foundation-CPE/QC-Gateway`).

### Adding the `github` remote (first-time setup on a new clone)

```bash
git remote add github git@github.com:LINKS-Foundation-CPE/Lagrange-stack-portable.git
```

## Working on this repository on its own

Clone it anywhere and it is workable: everything needed to build, test and change
it is in here. Nothing in this file depends on another repository being at hand,
or on any private document.

What it talks to, and where each contract is written down:

| Counterpart | Interface | Where the contract is |
|---|---|---|
| The components it installs | Compose files, `.env` rendering, and the variables each component documents | each component's `.env.example` / `env.example` |

The installer's job is to be the one place a deployment is described, so a
variable that exists here but nowhere else is a bug: it belongs in the component
that reads it, documented there, and referenced here.

Every repository in the stack carries a `CLAUDE.md` in this same shape, so the
same is true read from the other side. If you find yourself needing a fact that
is not in one of them, that is a gap worth fixing in the repository that owns the
fact — not a reason to go looking for a central document.
