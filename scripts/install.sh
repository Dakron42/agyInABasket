#!/usr/bin/env bash
#
# install.sh: Build the agyInABasket container image and install host wrappers
# Supports both Docker and Podman container engines.
#

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
TARGET_RUNTIME="${CONTAINER_RUNTIME:-}"

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build the agyInABasket container image and set up host wrappers.

Options:
  --docker            Build image and configure volumes for Docker only
  --podman            Build image and configure volumes for Podman only
  --both, --all       Build image and configure volumes for both Docker and Podman
  -h, --help          Show this help message

Default behavior:
  If both Docker and Podman are installed and accessible, images and volumes
  are automatically generated for both engines. Otherwise, the available
  engine is used.
EOF
}

# Parse command line options
for arg in "$@"; do
    case "$arg" in
        --docker|docker)
            TARGET_RUNTIME="docker"
            ;;
        --podman|podman)
            TARGET_RUNTIME="podman"
            ;;
        --both|--all|both|all)
            TARGET_RUNTIME="both"
            ;;
        -h|--help|help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Error: Unknown argument '$arg'" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 1
            ;;
    esac
done

echo "=========================================================="
echo "        agyInABasket - Setup & Installation               "
echo "=========================================================="

# 1. Detect and check container runtime(s) (Podman and/or Docker)
RUNTIMES=()

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        return 2
    fi
    return 0
}

check_podman() {
    if ! command -v podman >/dev/null 2>&1; then
        return 1
    fi
    if ! podman info >/dev/null 2>&1; then
        return 2
    fi
    return 0
}

if [ "$TARGET_RUNTIME" = "docker" ]; then
    check_docker_res=0
    check_docker || check_docker_res=$?
    if [ "$check_docker_res" -eq 1 ]; then
        echo "❌ Error: Docker is not installed or not found in PATH." >&2
        echo "Please install Docker (e.g. sudo apt install docker.io)." >&2
        exit 1
    elif [ "$check_docker_res" -eq 2 ]; then
        echo "❌ Error: Cannot connect to the Docker daemon." >&2
        echo "Make sure the Docker service is running ('sudo systemctl start docker') and that your user '${USER:-$(id -un)}' belongs to the 'docker' group." >&2
        echo "To add your user to the docker group: sudo usermod -aG docker \${USER:-\$(id -un)} && newgrp docker" >&2
        exit 1
    fi
    RUNTIMES+=("docker")
elif [ "$TARGET_RUNTIME" = "podman" ]; then
    check_podman_res=0
    check_podman || check_podman_res=$?
    if [ "$check_podman_res" -eq 1 ]; then
        echo "❌ Error: Podman is not installed or not found in PATH." >&2
        echo "Please install Podman (e.g. sudo apt install podman)." >&2
        exit 1
    elif [ "$check_podman_res" -eq 2 ]; then
        echo "❌ Error: Podman is installed but 'podman info' failed." >&2
        exit 1
    fi
    RUNTIMES+=("podman")
elif [ "$TARGET_RUNTIME" = "both" ]; then
    has_error=false
    check_docker_res=0
    check_docker || check_docker_res=$?
    if [ "$check_docker_res" -ne 0 ]; then
        echo "❌ Error: Docker was requested but is not available/running." >&2
        has_error=true
    else
        RUNTIMES+=("docker")
    fi
    check_podman_res=0
    check_podman || check_podman_res=$?
    if [ "$check_podman_res" -ne 0 ]; then
        echo "❌ Error: Podman was requested but is not available/functional." >&2
        has_error=true
    else
        RUNTIMES+=("podman")
    fi
    if [ "$has_error" = true ]; then
        exit 1
    fi
else
    # Auto-detection: build for all operational container engines
    if check_podman; then
        RUNTIMES+=("podman")
    fi
    if check_docker; then
        RUNTIMES+=("docker")
    fi

    if [ "${#RUNTIMES[@]}" -eq 0 ]; then
        echo "❌ Error: Neither Podman nor Docker is running or accessible." >&2
        if command -v docker >/dev/null 2>&1; then
            echo "ℹ️ Docker is installed, but the daemon is not running or accessible." >&2
            echo "   Try: sudo systemctl start docker" >&2
        fi
        if command -v podman >/dev/null 2>&1; then
            echo "ℹ️ Podman is installed, but 'podman info' failed." >&2
        fi
        echo "Please install and start Docker or Podman." >&2
        exit 1
    fi
fi

echo "🐳 Target container runtime(s): ${RUNTIMES[*]}"

# 2. Build container image and set up persistent volumes for each runtime
for rt in "${RUNTIMES[@]}"; do
    echo ""
    echo "=========================================================="
    echo "  Configuring engine: ${rt}"
    echo "=========================================================="

    echo "🔨 Building container image matching host UID: ${HOST_UID}, GID: ${HOST_GID} via ${rt}..."
    "$rt" build \
        --build-arg USER_UID="${HOST_UID}" \
        --build-arg USER_GID="${HOST_GID}" \
        --build-arg USER_NAME="${AIAB_CONTAINER_USER:-minty}" \
        -t agy-in-a-basket:latest \
        "${REPO_DIR}"

    echo "✓ Container image built successfully with tag: agy-in-a-basket:latest in ${rt}"

    echo "📦 Setting up persistent volumes in ${rt}..."
    if "$rt" volume inspect agy-data >/dev/null 2>&1; then
        echo "✓ Persistent volume 'agy-data' already exists in ${rt} (preserved)"
    else
        "$rt" volume create agy-data >/dev/null 2>&1 || true
        echo "✓ Created persistent volume 'agy-data' in ${rt}"
    fi

    if "$rt" volume inspect agy-config >/dev/null 2>&1; then
        echo "✓ Persistent volume 'agy-config' already exists in ${rt} (preserved)"
    else
        "$rt" volume create agy-config >/dev/null 2>&1 || true
        echo "✓ Created persistent volume 'agy-config' in ${rt}"
    fi

    # Check if legacy agy-auth-data exists and migrate
    if "$rt" volume inspect agy-auth-data >/dev/null 2>&1; then
        echo "ℹ️ Found existing 'agy-auth-data' volume in ${rt}. Copying any stored credentials to 'agy-data'..."
        "$rt" run --rm \
            -v "agy-auth-data:/from:ro" \
            -v "agy-data:/to" \
            agy-in-a-basket:latest sh -c "cp -an /from/. /to/ 2>/dev/null || true" || true
    fi
done

# 3. Install host CLI wrapper into ~/.local/bin
echo ""
echo "=========================================================="
echo "  Installing Host CLI Wrapper"
echo "=========================================================="
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

# 4. Hypervisor Isolation check (Kata Containers)
echo ""
echo "🛡️ Hypervisor Isolation Check (Kata Containers):"
if [ -e "/dev/kvm" ]; then
    echo "✓ Hardware virtualization (/dev/kvm) detected on host."
    if command -v kata-runtime >/dev/null 2>&1 || [ -x "/opt/kata/bin/kata-runtime" ] || [ -x "/usr/local/bin/kata-runtime" ] || [ -x "/usr/bin/kata-runtime" ] || command -v containerd-shim-kata-v2 >/dev/null 2>&1; then
        echo "✓ Kata Containers runtime detected! aiab will automatically default to microVM isolation."
        if [[ " ${RUNTIMES[*]} " == *" docker "* ]]; then
            echo "✓ Docker image and volumes are ready for Kata microVM execution."
        else
            echo "⚠️ Notice: Kata Containers requires Docker (containerd shimv2). Docker was not targeted during this install."
            echo "  To build for Docker: ./scripts/install.sh --docker"
        fi
    else
        echo "ℹ️ Kata Containers is not installed. Standard container isolation will be used."
        echo "  To install Kata Containers on Linux Mint / Ubuntu, run:"
        echo "    ./scripts/install-kata.sh"
    fi
else
    echo "ℹ️ /dev/kvm device not found. Standard container isolation will be used."
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
echo "  aiab --kata                     # (With Kata microVM)"
echo "=========================================================="
