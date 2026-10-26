#!/usr/bin/env bash
# Restore skeleton for an age-encrypted tar backup of files, volumes and SQLite or Postgres dumps.
#
# Modes:
#   check  Decrypt to a temp dir, list contents, integrity-check every database, print timings.
#          Changes nothing. The plaintext is shredded on exit, even on error.
#   apply  Restore into --root and into docker volumes named <volume-prefix><name>. Refuses to
#          overwrite anything that exists. Chowns each volume to the uid:gid in --owners.
#
# Usage:
#   restore.sh check --source <file-or-s3-url> --key <age-key-file> [--dry-run]
#   restore.sh apply --source <file-or-s3-url> --key <age-key-file> --root <dir> \
#                    [--volume-prefix <prefix>] [--owners <owners-file>] [--dry-run]
#
# Expected archive layout (adapt to the real backup):
#   files/...                 restored under --root
#   volumes/<name>/...        restored into docker volume <volume-prefix><name>
#   db/*.sqlite               checked with PRAGMA integrity_check
#   db/*.dump                 checked with pg_restore --list
#
# Owners file: one line per volume, "<name> <uid>:<gid>", for example "app-data 1000:1000".
#
# Never pass a real key on the command line of a shared shell history; point --key at a file.
set -euo pipefail

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }

mode="${1:-}"; if [ $# -gt 0 ]; then shift; fi
case "$mode" in check|apply) ;; -h|--help|"") usage; exit 0 ;; *) echo "unknown mode: $mode" >&2; usage; exit 2 ;; esac

source_uri="" key="" root="" prefix="restore_" owners="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --source) source_uri="$2"; shift 2 ;;
    --key) key="$2"; shift 2 ;;
    --root) root="$2"; shift 2 ;;
    --volume-prefix) prefix="$2"; shift 2 ;;
    --owners) owners="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$source_uri" ] || { echo "--source is required" >&2; exit 2; }
[ -n "$key" ] || { echo "--key is required" >&2; exit 2; }
[ "$mode" = apply ] && [ -z "$root" ] && { echo "--root is required in apply mode" >&2; exit 2; }

run() { if [ "$dry_run" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
step_start=0
step() { step_start=$(date +%s); echo "== $1"; }
step_done() { echo "   done in $(( $(date +%s) - step_start )) s"; }

work=$(mktemp -d)
cleanup() {
  # Shred every plaintext file, then remove the dir. Runs on success, error and Ctrl-C.
  if [ -d "$work" ]; then
    find "$work" -type f -exec shred -u {} + 2>/dev/null || true
    rm -rf "$work"
  fi
}
trap cleanup EXIT INT TERM

total_start=$(date +%s)

step "fetch"
case "$source_uri" in
  s3://*) run aws s3 cp --only-show-errors "$source_uri" "$work/backup.age" ;;
  *) run cp "$source_uri" "$work/backup.age" ;;
esac
step_done

if [ "$dry_run" = 0 ]; then
  head -c 64 "$work/backup.age" | head -n 1 | grep -q '^age-encryption.org/v1' \
    || { echo "not an age file (bad header)" >&2; exit 1; }
fi

step "decrypt"
run sh -c "age -d -i '$key' '$work/backup.age' | tar -x -C '$work'"
run shred -u "$work/backup.age"
step_done

step "list"
[ "$dry_run" = 0 ] && (cd "$work" && find . -maxdepth 3 -type d | sort && du -sh . )
step_done

step "integrity"
status=0
if [ "$dry_run" = 0 ]; then
  for f in "$work"/db/*.sqlite; do
    [ -e "$f" ] || continue
    r=$(sqlite3 "$f" 'PRAGMA integrity_check;')
    echo "   $(basename "$f"): $r"; [ "$r" = ok ] || status=1
  done
  for f in "$work"/db/*.dump; do
    [ -e "$f" ] || continue
    if pg_restore --list "$f" > /dev/null; then echo "   $(basename "$f"): ok"; else echo "   $(basename "$f"): FAIL"; status=1; fi
  done
else
  echo "[dry-run] sqlite3 <db> 'PRAGMA integrity_check;' and pg_restore --list <dump>"
fi
step_done
[ "$status" = 0 ] || { echo "integrity check failed" >&2; exit 1; }

if [ "$mode" = check ]; then
  echo "check ok in $(( $(date +%s) - total_start )) s, nothing changed"
  exit 0
fi

step "apply: refuse overwrite"
if [ -e "$root" ] && [ -n "$(ls -A "$root" 2>/dev/null)" ]; then
  echo "refusing: $root exists and is not empty" >&2; exit 1
fi
for d in "$work"/volumes/*/; do
  [ -d "$d" ] || continue
  v="$prefix$(basename "$d")"
  if docker volume inspect "$v" > /dev/null 2>&1; then echo "refusing: volume $v exists" >&2; exit 1; fi
done
step_done

step "apply: files"
run mkdir -p "$root"
[ -d "$work/files" ] && run cp -a "$work/files/." "$root/"
step_done

step "apply: volumes"
for d in "$work"/volumes/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d"); v="$prefix$name"
  owner=""
  [ -n "$owners" ] && owner=$(awk -v n="$name" '$1 == n { print $2 }' "$owners")
  [ -n "$owner" ] || { echo "no owner for volume $name in --owners; refusing to restore as root" >&2; exit 1; }
  run docker volume create "$v" > /dev/null
  run docker run --rm -v "$v:/dst" -v "$d:/src:ro" alpine sh -c "cp -a /src/. /dst/ && chown -R $owner /dst"
  echo "   $v owned by $owner"
done
step_done

echo "apply ok in $(( $(date +%s) - total_start )) s into $root and volumes $prefix*"
echo "remove a drill with: docker volume ls -q | grep '^$prefix' | xargs -r docker volume rm; rm -rf '$root'"
