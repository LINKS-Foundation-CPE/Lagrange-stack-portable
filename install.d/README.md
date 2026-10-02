# Installer hooks

`install.sh` sources every `install.d/<stage>-<name>.sh` at `<stage>`, in name
order, in its own shell: a hook sees the installer's variables and may change
them, and may use its helpers. `teardown.sh` sources every `teardown.d/*.sh`
before bringing the stacks down. Nothing ships here by default; a variant adds
files instead of editing the scripts.

| Stage | When | Typical use |
|---|---|---|
| `options` | after the built-in options are parsed and `PORTS` is set | claim extra options from `EXTRA_ARGS` (remove what you consume — whatever is left is an unknown-option error); reserve extra ports; override `*_REPO` / `*_REF` before `components.env` is read |
| `components` | after the component checkouts (gateway, backend, dashboard) | `checkout_component <dir> <repo> <ref>` for extra ones |
| `config` | after the env files are generated, before anything starts (also under `--no-start`) | `set_env <file> <key> <value>` on the generated env files |
| `seed` | after the backend is seeded with the test organization, project and users | extra users, projects or data |
| `post` | after the smoke tests pass | bring up extra stacks; switch settings that seeding needed off |
| `summary` | after the closing summary | print what the variant added |

Available to hooks: `step "<title>"`, `set_env`, `checkout_component`,
`HOST_IP`, `MACHINE_URL`, `CERT` (the shared dev CA, from the `config` stage
on), `PORTS`, `EXTRA_ARGS`, `NO_START`, and everything `components.env`
defines. `set -euo pipefail` is in force: a failing command in a hook stops the
installer, so guard what is best-effort with `|| true`.

`teardown.d/*.sh` append `"<directory>:<compose flags>"` to `SPECS`; teardown
skips a directory that is not there.

Hooks must keep the installer's guarantees: idempotent on re-run, nothing beyond
Linux, Docker, git, openssl, curl and python3.
