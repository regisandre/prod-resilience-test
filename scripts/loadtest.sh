#!/usr/bin/env bash
# Stepped load test around oha (https://github.com/hatoo/oha). Local or staging only, never prod.
#
# Optionally starts the server itself on a random free port, so an orphan from a previous run
# cannot answer in its place. Kills only the server it started. Waits only on the load generator.
#
# Usage:
#   loadtest.sh --url <url> [--steps 1,4,16,64] [--duration 30] [--runs 2] [--out <file.csv>]
#               [--server-cmd '<command using $PORT>'] [--server-log <file>] [--dry-run]
#
# With --server-cmd, the URL may contain the literal PORT, replaced by the chosen port:
#   loadtest.sh --server-cmd 'node dist/server.js --port $PORT' --url http://127.0.0.1:PORT/items
#
# Output CSV: label,run,concurrency,rps,p50_ms,p99_ms,error_rate
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

url="" steps="1,4,16,64,128" duration=30 runs=2 out="loadtest-$(date +%Y%m%d%H%M%S).csv"
server_cmd="" server_log="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --steps) steps="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --server-cmd) server_cmd="$2"; shift 2 ;;
    --server-log) server_log="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$url" ] || { usage; exit 2; }

case "$url" in
  *"<prod-domain>"*|*"<api-host>"*) echo "refusing: looks like prod" >&2; exit 2 ;;
esac

server_pid=""
stop_server() { if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi; }
trap stop_server EXIT INT TERM

if [ -n "$server_cmd" ]; then
  PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null \
    || shuf -i 20000-60000 -n 1)
  export PORT
  url="${url//PORT/$PORT}"
  server_log="${server_log:-server-$PORT.log}"
  if [ "$dry_run" = 1 ]; then
    echo "[dry-run] PORT=$PORT $server_cmd > $server_log"
  else
    bash -c "$server_cmd" > "$server_log" 2>&1 &
    server_pid=$!
    for _ in $(seq 1 60); do curl -fsS -o /dev/null "$url" && break; sleep 1; done
    if grep -qiE 'EADDRINUSE|address already in use|bind' "$server_log"; then
      echo "server failed to bind, see $server_log" >&2; exit 1
    fi
    kill -0 "$server_pid" 2>/dev/null || { echo "server exited, see $server_log" >&2; exit 1; }
  fi
fi

[ "$dry_run" = 1 ] || echo "label,run,concurrency,rps,p50_ms,p99_ms,error_rate" > "$out"
label=$(basename "$out" .csv)

IFS=',' read -r -a conc <<< "$steps"
for run in $(seq 1 "$runs"); do
  for c in "${conc[@]}"; do
    if [ "$dry_run" = 1 ]; then
      echo "[dry-run] oha -z ${duration}s -c $c --no-tui --output-format json $url"; continue
    fi
    oha -z "${duration}s" -c "$c" --no-tui --output-format json "$url" > "$out.tmp.json" &
    loadgen_pid=$!
    wait "$loadgen_pid"
    jq -r --arg l "$label" --arg r "$run" --arg c "$c" '
      [ $l, $r, $c,
        (.summary.requestsPerSec | . * 10 | round / 10),
        (.latencyPercentiles.p50 * 1000 | round),
        (.latencyPercentiles.p99 * 1000 | round),
        (1 - .summary.successRate | . * 1000 | round / 1000)
      ] | @csv' "$out.tmp.json" >> "$out"
    tail -n 1 "$out"
  done
done
rm -f "$out.tmp.json"
[ "$dry_run" = 1 ] || echo "results in $out"
