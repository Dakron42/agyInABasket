#!/usr/bin/env bash
#
# install.sh: Build the agyInABasket container image and install host wrappers
# Supports both Docker and Podman container engines.
#

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"

echo "=========================================================="
echo "        agyInABasket - Setup & Installation               "
echo "=========================================================="

# 1. Detect and check container runtime (Podman or Docker)
if [ -z "$CONTAINER_RUNTIME" ]; then
    if command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    else
        echo "❌ Error: Neither Podman nor Docker is installed or found in PATH." >&2
        echo "Please install Docker (e.g. sudo apt install docker.io) or Podman (e.g. sudo apt install podman)." >&2
        exit 1
    fi
fi

echo "🐳 Detected container runtime: ${CONTAINER_RUNTIME}"

if [ "$CONTAINER_RUNTIME" = "docker" ]; then
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Error: Cannot connect to the Docker daemon." >&2
        echo "Make sure the Docker service is running ('sudo systemctl start docker') and that your user '$USER' belongs to the 'docker' group." >&2
        echo "To add your user to the docker group: sudo usermod -aG docker \$USER && newgrp docker" >&2
        exit 1
    fi
elif [ "$CONTAINER_RUNTIME" = "podman" ]; then
    if ! podman info >/dev/null 2>&1; then
        echo "❌ Error: Podman is installed but 'podman info' failed." >&2
        exit 1
    fi
fi

# 2. Build container image with exact host UID/GID
echo "🔨 Building container image matching host UID: ${HOST_UID}, GID: ${HOST_GID} via ${CONTAINER_RUNTIME}..."
"$CONTAINER_RUNTIME" build \
    --build-arg USER_UID="${HOST_UID}" \
    --build-arg USER_GID="${HOST_GID}" \
    -t agy-yolo:latest \
    -t agy-basket:latest \
    "${REPO_DIR}"

echo "✓ Container image built successfully with tags: agy-yolo:latest, agy-basket:latest"

# 3. Create persistent container volumes
echo "📦 Setting up persistent volumes..."
"$CONTAINER_RUNTIME" volume create agy-data >/dev/null
"$CONTAINER_RUNTIME" volume create agy-config >/dev/null

# Check if legacy agy-auth-data exists and offers to migrate
if "$CONTAINER_RUNTIME" volume inspect agy-auth-data >/dev/null 2>&1; then
    echo "ℹ️ Found existing 'agy-auth-data' volume. Copying any stored credentials to 'agy-data'..."
    "$CONTAINER_RUNTIME" run --rm \
        -v "agy-auth-data:/from:ro" \
        -v "agy-data:/to" \
        busybox sh -c "cp -an /from/* /to/ 2>/dev/null || true" || true
fi

# 4. Install host CLI wrapper into ~/.local/bin
mkdir -p "${BIN_DIR}"
ln -sf "${REPO_DIR}/bin/aiab" "${BIN_DIR}/aiab"
chmod +x "${REPO_DIR}/bin/aiab"

echo "✓ Linked launcher script to:"
echo "    ${BIN_DIR}/aiab"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "⚠️ Notice: '${BIN_DIR}' is not in your current PATH."
    echo "Add the following to your ~/.bashrc or ~/.profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# 5. Shell integration advice
SHELL_INTEGRATION_LINE="source \"${REPO_DIR}/shell/aiab.bash\""
TARGET_RC="${HOME}/.bashrc"
if [ -f "${HOME}/.bash_aliases" ]; then
    TARGET_RC="${HOME}/.bash_aliases"
fi

echo ""
echo "🐚 Shell Function Integration:"
if grep -Fxq "${SHELL_INTEGRATION_LINE}" "${TARGET_RC}" 2>/dev/null; then
    echo "✓ Shell function already sourced in ${TARGET_RC}"
else
    echo "To update your existing 'aiab' bash function automatically, run:"
    echo "  echo '${SHELL_INTEGRATION_LINE}' >> ${TARGET_RC}"
    echo "  source ${TARGET_RC}"
fi

echo ""
echo "=========================================================="
echo "🎉 Installation complete!"
echo "Run Antigravity anywhere via:"
echo "  aiab"
echo "  aiab /path/to/project"
echo "=========================================================="
