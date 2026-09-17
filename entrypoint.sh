#!/bin/sh
# RustDesk Server OSS - Railway entrypoint.
#
# Resolves the role (hbbs or hbbr), runs the official binary unmodified,
# and — for hbbs — waits for the Ed25519 keypair to appear on the persistent
# volume, then prints and writes a copy-paste client configuration card.
#
# Role resolution (first match wins):
#   1. $ROLE (explicit override)
#   2. $RAILWAY_SERVICE_NAME matching *hbbr*  -> hbbr
#   3. otherwise                              -> hbbs
#
# hbbs receives its relay advertisement from $RELAY_SERVERS, passed both as
# the -r flag and as the RELAY-SERVERS env var (upstream reads the env under
# that exact dashed name). RELAY_SERVERS must be hbbr's PUBLIC address —
# it is what clients are told to relay through.

set -u

BB=/bin/busybox
DATA_DIR="${DATA_DIR:-/root}"

ROLE="${ROLE:-}"
if [ -z "${ROLE}" ]; then
  case "${RAILWAY_SERVICE_NAME:-}" in
    *hbbr*) ROLE=hbbr ;;
    *)      ROLE=hbbs ;;
  esac
fi

cd "${DATA_DIR}" || { echo "[entrypoint] FATAL: cannot cd into ${DATA_DIR}" >&2; exit 1; }

echo "[entrypoint] role=${ROLE} data_dir=${DATA_DIR}"

# Copy-paste client configuration card. Regenerated on every boot so it
# always reflects the currently assigned Railway TCP proxy endpoints; the
# keypair itself persists on the volume.
write_card() {
  PUB_KEY="$($BB cat "${DATA_DIR}/id_ed25519.pub" 2>/dev/null)"
  ID_SERVER="${RAILWAY_TCP_PROXY_DOMAIN:-}"
  if [ -n "${RAILWAY_TCP_PROXY_PORT:-}" ]; then
    ID_SERVER="${ID_SERVER}:${RAILWAY_TCP_PROXY_PORT}"
  fi
  CARD="${DATA_DIR}/client-config.txt"
  {
    echo "============================================================"
    echo " RustDesk client configuration"
    echo " RustDesk client > Settings > Network > ID/Relay Server"
    echo "============================================================"
    echo "ID Server:    ${ID_SERVER:-<proxy not assigned yet>}"
    echo "Relay Server: ${RELAY_SERVERS:-<not set>}"
    echo "Key:          ${PUB_KEY:-<key not generated>}"
    echo "============================================================"
  } | $BB tee "${CARD}"
  echo "[entrypoint] client-config card written to ${CARD}"
}

if [ "${ROLE}" = "hbbs" ]; then
  ARGS=""
  if [ -n "${RELAY_SERVERS:-}" ]; then
    ARGS="-r ${RELAY_SERVERS}"
  fi
  echo "[entrypoint] starting: /usr/bin/hbbs ${ARGS}"
  # shellcheck disable=SC2086  # ARGS is an intentional flag list
  env "RELAY-SERVERS=${RELAY_SERVERS:-}" /usr/bin/hbbs ${ARGS} "$@" &
  CHILD=$!
  trap 'kill -TERM "${CHILD}" 2>/dev/null' TERM INT

  # First boot: hbbs generates the keypair in its working dir ($DATA_DIR).
  # Wait for the public key so the card can be emitted into the deploy log.
  N=0
  while [ ! -s "${DATA_DIR}/id_ed25519.pub" ] && [ "${N}" -lt 60 ]; do
    $BB sleep 1
    N=$((N + 1))
  done
  if [ -s "${DATA_DIR}/id_ed25519.pub" ]; then
    write_card
  else
    echo "[entrypoint] WARNING: ${DATA_DIR}/id_ed25519.pub not found after ${N}s; skipping client-config card" >&2
  fi

  wait "${CHILD}"
  STATUS=$?
  if [ "${STATUS}" -ge 128 ]; then
    # Trap fired during wait: hbbs was signaled to stop, collect its real code.
    wait "${CHILD}" 2>/dev/null
    STATUS=$?
    [ "${STATUS}" -ge 128 ] && STATUS=0
  fi
  echo "[entrypoint] hbbs exited with status ${STATUS}"
  exit "${STATUS}"
fi

echo "[entrypoint] starting: /usr/bin/hbbr"
exec /usr/bin/hbbr "$@"
