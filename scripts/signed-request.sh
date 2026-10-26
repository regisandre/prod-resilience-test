#!/usr/bin/env bash
# Send an HMAC-SHA256 signed request to an internal endpoint, signing the exact bytes sent.
#
# Signature (adapt to the server): hex(HMAC_SHA256(secret, "<timestamp>.<method>.<path>.<sha256(body)>"))
# Headers: x-timestamp, x-signature. Check the server source for the timestamp unit before use.
#
# The secret is read from an environment variable whose NAME you pass, never from the command line,
# and is never printed. Run it on the machine that holds the secret, then unset the variable.
#
# Usage:
#   signed-request.sh --method <GET|POST|PUT|DELETE> --url <url> --secret-env <VAR_NAME>
#                     [--body-file <file.json>] [--ts-unit s|ms] [--dry-run]
#
# For a PUT that replaces an object, GET it first and send it back whole with only your change:
# a missing field may reset to its default on the server.
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

method="" url="" secret_env="" body_file="" ts_unit="s" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --method) method="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --secret-env) secret_env="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    --ts-unit) ts_unit="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$method" ] || [ -z "$url" ] || [ -z "$secret_env" ]; then usage; exit 2; fi

[ -n "${!secret_env:-}" ] || { echo "env variable $secret_env is empty or missing" >&2; exit 2; }

path="/${url#*://*/}"; path="${path%%\?*}"
case "$ts_unit" in
  s) ts=$(date +%s) ;;
  ms) ts=$(( $(date +%s) * 1000 )) ;;
  *) echo "--ts-unit must be s or ms" >&2; exit 2 ;;
esac

if [ -n "$body_file" ]; then
  body_hash=$(sha256sum "$body_file" | cut -d' ' -f1)
else
  body_hash=$(printf '' | sha256sum | cut -d' ' -f1)
fi

# python3 reads the secret from the environment: `openssl -hmac <secret>` would put it in the process
# arguments, readable by any local user through ps.
sig=$(printf '%s.%s.%s.%s' "$ts" "$method" "$path" "$body_hash" \
  | python3 -c 'import hmac, hashlib, os, sys; print(hmac.new(os.environ[sys.argv[1]].encode(), sys.stdin.buffer.read(), hashlib.sha256).hexdigest())' "$secret_env")

args=(-sS -X "$method" "$url" -H "x-timestamp: $ts" -H "x-signature: $sig" -w '\n%{http_code}\n')
[ -n "$body_file" ] && args+=(-H 'content-type: application/json' --data-binary "@$body_file")

if [ "$dry_run" = 1 ]; then
  echo "[dry-run] curl -X $method $url (timestamp $ts $ts_unit, body sha256 $body_hash, signature <redacted>)"
  exit 0
fi
curl "${args[@]}"
