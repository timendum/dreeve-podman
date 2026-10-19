#!/usr/bin/env bash
set -euo pipefail
# Run the file import manually inside the running Dreeve container.
#
# Requires IMPORT_MODE=files. Any extra args are forwarded to the command.

CONTAINER_NAME="${DREEVE_CONTAINER:-dreeve}"

if ! podman container exists "${CONTAINER_NAME}"; then
  echo "ERROR: container '${CONTAINER_NAME}' is not running. Start it with ./run.sh" >&2
  exit 1
fi

exec podman exec -it "${CONTAINER_NAME}" bin/console app:import:files "$@"
