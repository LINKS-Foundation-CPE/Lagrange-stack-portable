# The SLURM variant (`--with-slurm`)

`install.sh --with-slurm` adds a containerised SLURM cluster to the environment
and configures the stack for **Sqed**, the *Slurm-based Quantum Execution
Director*: jobs submit circuits with a per-job token that a SLURM prolog mints,
SLURM decides who may use the machine, and the portal becomes a job viewer. It
is a test bed for that integration. To deploy Sqed on a real cluster, follow
[Deploying Sqed](https://links-foundation-cpe.github.io/Lagrange-stack-docs/hpc/deployment/)
instead.

```bash
./install.sh --ip <host-ip> --machine-url https://<mock-or-qc> --token <IQM_SERVER_TOKEN> --with-slurm
```

On top of the default prerequisites: port **2222** free (the headnode's SSH,
on `127.0.0.1`), and time and disk for the SLURM images. The base image compiles
Slurm from source, which takes tens of minutes on a cold cache.

## What it adds

| | |
|---|---|
| **The cluster** | [LINKS-Foundation-CPE/vhpc](https://github.com/LINKS-Foundation-CPE/vhpc): a headnode, two workers and an accounting database, Slurm 23.11.10. Compose project `portable-slurm`, images built locally. |
| **The prolog/epilog** | [Lagrange-prolog-epilog](https://github.com/LINKS-Foundation-CPE/Lagrange-prolog-epilog), mounted at `/opt/sqed` on every node and wired into `slurm.conf`. They write token records to the gateway's Redis. |
| **A license** | `qpu@qc_gateway`, a remote license with 4 seats, registered in slurmdbd. Jobs request it with `--licenses=qpu@qc_gateway:N`; the bare name `qpu` is refused. |
| **A cluster user** | `user` (or `--cluster-user <name>`), in Keycloak with no e-mail, and in the backend. Its SLURM account is `dev-project`. Password: `CLUSTERUSER_PASSWORD` in `keycloak-deployment/dev-credentials.env`. |
| **Gateway settings** | `SITE_PLUGIN=sqed`, `AUTH_PLUGINS=keycloak,sqed`, `SQED_DEFAULT_ROLES=cortex_user,pulla_user`. |
| **Backend settings** | `USERNAME_FORMAT=any`, set before the first start, and `JOB_PORTAL_ONLY=true`, set after the seeding (the seed uses the endpoints the flag removes). |
| **On the cluster** | `iqm-client[qiskit]` in the shared venv `/opt/venv`, and `/shared/user` holding the development CA as `keycloak.crt`. |

`teardown.sh` brings the cluster down with the rest of the stack.

## Running a circuit through SLURM

Copy the test job onto the shared filesystem and submit it as the cluster user:

```bash
cd slurm-docker-compose
docker compose -p portable-slurm cp ../test/slurm_iqm_job.py     slurm-headnode:/shared/user/
docker compose -p portable-slurm cp ../test/slurm_iqm_job.sbatch slurm-headnode:/shared/user/
docker compose -p portable-slurm exec slurm-headnode chown user /shared/user/slurm_iqm_job.py /shared/user/slurm_iqm_job.sbatch
docker compose -p portable-slurm exec -u user slurm-headnode sbatch -A dev-project /shared/user/slurm_iqm_job.sbatch
```

The job runs a three-qubit GHZ circuit through the gateway. Its output, in
`/shared/user/iqm-ghz-<job-id>.out`, looks like:

```text
token_injected=yes
gateway=https://host.docker.internal:8000
slurm_job_id=1
job_id=<the machine's job id>
counts={'000': 512, '111': 512}
```

In the portal, logged in as the cluster user, the job appears under the
project `dev-project`. Submit with another SLURM account (`sbatch -A <account>`,
after `sacctmgr add account` and `add user`) and the job is filed under a project
of that name, created on first sight.

## Checking the pieces

```bash
docker compose -p portable-slurm exec slurm-headnode scontrol show lic     # qpu@qc_gateway, Remote=yes
docker compose -p portable-slurm exec slurm-headnode sinfo -N             # workers idle or allocated
docker exec jobs-redis-dev redis-cli --scan --pattern 'qpu:*'             # while a job runs: qpu:token:<sha256>, qpu:job:<id>
docker logs fastapi-middleware-dev 2>&1 | grep 'via sqed'                 # the gateway authenticated a job token
```

| Symptom | Look at |
|---|---|
| `Invalid license specification` | Request `qpu@qc_gateway:N`, the remote name. |
| `token_injected=no`, or the task fails at launch | The prolog could not publish the record: is `jobs-redis-dev` attached to the cluster network (`docker network inspect portable-slurm_slurm-net`)? |
| The job runs but never shows in the portal | The cluster user must exist in the backend under the same name: rerun the installer, or log in to the portal once as that user. |
| `No module named qiskit` | `iqm-client[qiskit]` goes into `/opt/venv` on the headnode, which the workers share. |
| TLS errors from Python | `REQUESTS_CA_BUNDLE` must point at `/shared/user/keycloak.crt`. |

## Turning it back into a full portal

`JOB_PORTAL_ONLY` is not frozen: remove it from `quantum-api/.env` and recreate
the backend container to get the management surface back. `USERNAME_FORMAT`
*is* frozen at first boot; changing it needs the procedure in the backend's
documentation.
