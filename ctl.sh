#!/usr/bin/env bash
# Small control helper for the single Dreeve Podman container.
#
# Usage:
#   ./ctl.sh logs [-f]        Show (and optionally follow) container logs
#   ./ctl.sh shell            Open a shell inside the container
#   ./ctl.sh console <args>   Run `bin/console <args>` in the container
#   ./ctl.sh status           Show container status
#   ./ctl.sh stop             Stop the container
#   ./ctl.sh start            Start a stopped container
#   ./ctl.sh restart          Restart the container (does NOT reload dreeve.env)
#   ./ctl.sh rm               Stop and remove the container (data is kept)
#
# NOTE: start/restart reuse the EXISTING container, whose environment was
# frozen at creation time. They do NOT re-read dreeve.env. After editing
# dreeve.env, run ./run.sh (it recreates the container) to apply the changes.
set -euo pipefail

CONTAINER_NAME="${DREEVE_CONTAINER:-dreeve}"

cmd="${1:-}"
shift || true

case "${cmd}" in
  logs)    exec podman logs "$@" "${CONTAINER_NAME}" ;;
  shell)   exec podman exec -it "${CONTAINER_NAME}" bash ;;
  console) exec podman exec -it "${CONTAINER_NAME}" bin/console "$@" ;;
  status)  exec podman ps -a --filter "name=^${CONTAINER_NAME}$" ;;
  stop)    exec podman stop "${CONTAINER_NAME}" ;;
  start)   exec podman start "${CONTAINER_NAME}" ;;
  restart) exec podman restart "${CONTAINER_NAME}" ;;
  rm)      exec podman rm -f "${CONTAINER_NAME}" ;;
  *)
    echo "Usage: $0 {logs|shell|console <args>|status|stop|start|restart|rm}" >&2
    exit 1
    ;;
esac
