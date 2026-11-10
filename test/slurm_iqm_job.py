#!/usr/bin/env python3
"""Submit a small GHZ circuit to the Lagrange gateway from a SLURM job."""

from __future__ import annotations

import os
from pathlib import Path

from qiskit import QuantumCircuit, transpile
from iqm.qiskit_iqm import IQMProvider


def main() -> None:
    iqm_url = os.environ.get("IQM_SERVER_URL", "https://host.docker.internal:8000")
    token = os.environ.get("IQM_TOKEN")
    ca_bundle = os.environ.get("REQUESTS_CA_BUNDLE", "/shared/user/keycloak.crt")

    if not token:
        raise SystemExit(
            "IQM_TOKEN is not set. Submit with --licenses=qpu@qc_gateway:1 "
            "so the SLURM TaskProlog can provision it."
        )
    if not Path(ca_bundle).is_file():
        raise SystemExit(f"CA bundle does not exist: {ca_bundle}")

    circuit = QuantumCircuit(3)
    circuit.h(0)
    circuit.cx(0, 1)
    circuit.cx(0, 2)
    circuit.measure_all()

    provider = IQMProvider(iqm_url, quantum_computer="default")
    backend = provider.get_backend()
    transpiled = transpile(circuit, backend=backend)
    job = backend.run([transpiled], shots=1024)
    result = job.result()

    print(f"gateway={iqm_url}")
    print(f"slurm_job_id={os.environ.get('SLURM_JOB_ID', '<unknown>')}")
    print(f"job_id={job.job_id()}")
    print(f"counts={result.get_counts()}")


if __name__ == "__main__":
    main()
