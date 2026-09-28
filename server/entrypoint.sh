#!/usr/bin/env bash
set -euo pipefail

cert_dir=/etc/nginx/tls
cert_path="${cert_dir}/cert.pem"
key_path="${cert_dir}/key.pem"

mkdir -p "${cert_dir}" /run

if [[ ! -s "${cert_path}" || ! -s "${key_path}" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${key_path}" \
        -out "${cert_path}" \
        -days 30 \
        -subj "/CN=${TLS_COMMON_NAME:-server}" \
        -addext "subjectAltName=DNS:${TLS_COMMON_NAME:-server},DNS:localhost"
    chmod 0600 "${key_path}"
fi

iperf3 --server --port 5201 >/dev/stdout 2>/dev/stderr &
exec nginx -g 'daemon off;'

