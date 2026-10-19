#!/usr/bin/env bash
# Start Dreeve as a single Podman container using the public image.
set -euo pipefail

# --- Config -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTAINER_NAME="${DREEVE_CONTAINER:-dreeve}"
IMAGE="${DREEVE_IMAGE:-docker.io/robiningelbrecht/dreeve:latest}"
HOST_PORT="${DREEVE_PORT:-8081}"
ENV_FILE="${DREEVE_ENV_FILE:-${SCRIPT_DIR}/dreeve.env}"

# Host directories that hold persistent data. Bind-mounted into the container.
DATA_ROOT="${DREEVE_DATA_ROOT:-${SCRIPT_DIR}}"

# --- Preconditions ----------------------------------------------------------
if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman is not installed or not on PATH." >&2
  exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: env file not found: ${ENV_FILE}" >&2
  echo "Copy the template and edit it:" >&2
  echo "  cp \"${SCRIPT_DIR}/dreeve.env.example\" \"${ENV_FILE}\"" >&2
  exit 1
fi

# --- Prepare host data directories -----------------------------------------
mkdir -p \
  "${DATA_ROOT}/storage/database" \
  "${DATA_ROOT}/storage/files" \
  "${DATA_ROOT}/storage/gear-maintenance" \
  "${DATA_ROOT}/build" \
  "${DATA_ROOT}/watch"

# --- Pull the public image --------------------------------------------------
echo "Pulling ${IMAGE}..."
podman pull "${IMAGE}"

# --- Replace any previous container ----------------------------------------
if podman container exists "${CONTAINER_NAME}"; then
  echo "Removing existing container ${CONTAINER_NAME}..."
  podman rm -f "${CONTAINER_NAME}" >/dev/null
fi

# --- Start the single container --------------------------------------------
# :Z relabels the bind mounts for SELinux hosts; harmless elsewhere.
echo "Starting ${CONTAINER_NAME}..."
podman run -d \
  --name "${CONTAINER_NAME}" \
  --env-file "${ENV_FILE}" \
  --restart unless-stopped \
  --health-cmd "curl -f http://localhost:2019/metrics" \
  --health-start-period 60s \
  -p "127.0.0.1:${HOST_PORT}:8080" \
  -v "${DATA_ROOT}/storage/database:/var/www/storage/database:Z" \
  -v "${DATA_ROOT}/storage/files:/var/www/storage/files:Z" \
  -v "${DATA_ROOT}/storage/gear-maintenance:/var/www/storage/gear-maintenance:Z" \
  -v "${DATA_ROOT}/build:/var/www/build:Z" \
  -v "${DATA_ROOT}/watch:/var/www/watch:Z" \
  "${IMAGE}"

echo
echo "Dreeve is starting. It runs DB migrations on boot; give it a moment."
echo "  Web UI:   http://localhost:${HOST_PORT}"
echo "  Logs:     ./ctl.sh logs"
echo "  Import:   ./import.sh"
