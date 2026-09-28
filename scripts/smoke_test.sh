#!/usr/bin/env bash
# Run this script from the repository root on a host with Docker Compose available.
set -uo pipefail

compose=(docker compose)
failed=0
capture_name="smoke_$(date +%Y%m%d_%H%M%S).pcapng"
capture_path="/artifacts/${capture_name}"

report() {
    local status="$1"
    local name="$2"
    local detail="$3"
    printf '[%s] %s - %s\n' "$status" "$name" "$detail"
}

run() {
    local name="$1"
    shift
    if "$@"; then
        report OK "$name" "validated"
    else
        report FALHOU "$name" "command failed"
        failed=1
    fi
}

client() {
    "${compose[@]}" exec -T client bash -lc "$1"
}

server() {
    "${compose[@]}" exec -T server bash -lc "$1"
}

cleanup_netem() {
    client 'tc qdisc del dev eth0 root 2>/dev/null || true'
}

if ! docker compose version >/dev/null 2>&1; then
    report FALHOU 'docker compose' 'Docker Compose is unavailable'
    exit 1
fi
report OK 'docker compose' 'Compose plugin is available'

if ! "${compose[@]}" config -q; then
    report FALHOU 'docker compose configuration' 'compose file is invalid'
    exit 1
fi
report OK 'docker compose configuration' 'configuration is valid'

if ! "${compose[@]}" up --build --detach --wait; then
    report FALHOU 'containers' 'could not build or become healthy'
    exit 1
fi
trap 'cleanup_netem; "${compose[@]}" down --remove-orphans >/dev/null 2>&1 || true' EXIT
report OK 'containers' 'server and client are running'

run 'container communication' client 'getent hosts server >/dev/null && timeout 3 bash -c "</dev/tcp/server/8443"'
run 'self-signed TLS certificate' server "test -s /etc/nginx/tls/cert.pem && test -s /etc/nginx/tls/key.pem && openssl x509 -in /etc/nginx/tls/cert.pem -noout -subject | grep -Eq 'CN *= *server'"
run 'TLS 1.3' client 'curl --verbose --insecure --http1.1 --output /dev/null https://server:8443/ 2>&1 | grep -q "SSL connection using TLSv1.3"'
run 'HTTP/1.1' client 'test "$(curl --silent --show-error --insecure --http1.1 --output /dev/null --write-out "%{http_version}" https://server:8443/)" = "1.1"'
run 'HTTP/2' client 'test "$(curl --silent --show-error --insecure --http2 --output /dev/null --write-out "%{http_version}" https://server:8443/)" = "2"'
run 'curl HTTP/3 capability' client 'curl --version | grep -q HTTP3'
run 'HTTP/3 without fallback' client 'test "$(curl --silent --show-error --insecure --http3-only --output /dev/null --write-out "%{http_version}" https://server:8443/)" = "3"'
run 'iperf3 TCP' client 'iperf3 --client server --port 5201 --time 1 --json | python3 -c "import json,sys; assert json.load(sys.stdin)[\"end\"][\"sum_received\"][\"bytes\"] > 0"'
run 'iperf3 UDP' client 'iperf3 --client server --port 5201 --udp --bitrate 10M --time 1 --json | python3 -c "import json,sys; assert json.load(sys.stdin)[\"end\"][\"sum\"][\"bytes\"] > 0"'

run 'netem delay application' client 'tc qdisc replace dev eth0 root netem delay 50ms && ping -c 3 -W 2 server | python3 -c "import re,sys; m=re.search(r\"= [^/]+/([^/]+)\",sys.stdin.read()); assert m and float(m.group(1)) >= 35"'
run 'netem packet loss application' client 'tc qdisc replace dev eth0 root netem loss 100% && ! ping -c 1 -W 1 server >/dev/null 2>&1'
run 'netem removal' client 'tc qdisc del dev eth0 root && ! tc qdisc show dev eth0 | grep -q netem && ping -c 1 -W 2 server >/dev/null'

if client "rm -f '${capture_path}'; tshark -i eth0 -f 'tcp port 8443' -a duration:4 -w '${capture_path}' >/tmp/tshark-smoke.log 2>&1" & then
    capture_pid=$!
    sleep 1
    if client 'curl --silent --show-error --insecure --http1.1 --output /dev/null https://server:8443/' \
        && wait "${capture_pid}" \
        && client "test -s '${capture_path}' && tshark -r '${capture_path}' -c 1 >/dev/null"; then
        report OK 'tshark capture' "capture saved as artifacts/${capture_name}"
    else
        report FALHOU 'tshark capture' 'no readable packet capture was produced'
        failed=1
    fi
else
    report FALHOU 'tshark capture' 'could not start tshark'
    failed=1
fi

if (( failed )); then
    exit 1
fi
