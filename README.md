# Redes II - transport protocol laboratory

This repository currently contains only the fundamental infrastructure requested for the practical assessment. The experiment scenarios and their analysis have intentionally not been implemented.

## Requirements

- Docker Engine with the Docker Compose plugin running.
- A Linux Docker backend capable of granting `NET_ADMIN` and `NET_RAW` to containers.

## Run the smoke test

```bash
bash scripts/smoke_test.sh
```

The script builds the images, starts the Compose project, exercises HTTP/1.1, HTTP/2, real HTTP/3 with `--http3-only`, iperf3 TCP/UDP, netem, and a tshark capture. It always removes the netem qdisc and brings the project down on exit. Packet captures are retained in `artifacts/`.

## Manual inspection

```bash
docker compose up --build --detach --wait
docker compose exec client curl -k --http3-only -w 'HTTP/%{http_version}\n' https://server:8443/
docker compose exec client curl --version
docker compose exec server nginx -V
docker compose down
```
