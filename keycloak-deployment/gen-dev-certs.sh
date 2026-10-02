#!/usr/bin/env bash
# Generate a self-signed TLS certificate for the dev Keycloak.
# Usage: ./gen-dev-certs.sh <host-ip> [extra-dns-name]
set -euo pipefail

HOST_IP=${1:?usage: gen-dev-certs.sh <host-ip> [extra-dns-name]}
EXTRA_DNS=${2:-localhost}

# The address may be a host name (e.g. localhost or a VM's DNS name): it goes in
# the certificate as DNS:, since openssl refuses a name given as IP:.
if [[ "$HOST_IP" =~ ^[0-9]+(\.[0-9]+){3}$ || "$HOST_IP" == *:* ]]; then
  HOST_SAN="IP:${HOST_IP}"
else
  HOST_SAN="DNS:${HOST_IP}"
fi

mkdir -p certs
# SANs cover every name the dev stack dials: the external address (browsers/SDKs),
# loopback (host-side scripts), and host.docker.internal (container->host hops).
SANS="${HOST_SAN},IP:127.0.0.1,DNS:localhost,DNS:host.docker.internal,DNS:${EXTRA_DNS}"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout certs/keycloak.key -out certs/keycloak.crt \
  -subj "/CN=${HOST_IP}" \
  -addext "subjectAltName=${SANS}"
chmod 644 certs/keycloak.key certs/keycloak.crt
echo "Self-signed cert written to certs/keycloak.{crt,key} (SAN: ${SANS})"
