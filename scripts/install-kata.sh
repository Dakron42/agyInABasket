#!/usr/bin/env bash
#
# scripts/install-kata.sh: Automated installer for Kata Containers static release
# Designed for Linux Mint, Ubuntu, Debian, and systems without direct apt packages.
#

set -euo pipefail

echo "=========================================================="
echo "       Kata Containers Automated Installer (aiab)         "
echo "=========================================================="

# 1. Architecture check
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)
        PRIMARY_ARCH="amd64"
        ALT_ARCH="x86_64"
        ;;
    aarch64|arm64)
        PRIMARY_ARCH="arm64"
        ALT_ARCH="aarch64"
        ;;
    *)
        echo "❌ Error: Unsupported architecture '$ARCH'. Kata static binaries support amd64 (x86_64) and arm64 (aarch64)." >&2
        exit 1
        ;;
esac

# 2. Hardware virtualization and kernel modules check
echo "🔍 Checking hardware virtualization (VT-x / AMD-V)..."
if [ ! -e "/dev/kvm" ]; then
    echo "⚠️ Warning: /dev/kvm device node was not found."
    if grep -E -q '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
        echo "   CPU supports virtualization! Attempting to load KVM kernel modules..."
        sudo modprobe kvm 2>/dev/null || true
        sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true
    else
        echo "   ❌ Your CPU does not appear to support hardware virtualization or it is disabled in BIOS/UEFI." >&2
        echo "   Please enable Intel VT-x or AMD-V in your BIOS/UEFI settings." >&2
    fi
else
    echo "✓ Hardware virtualization (/dev/kvm) detected."
fi

# Load required kernel modules for Kata Containers (vhost, vhost_net, vhost_vsock)
echo "🔌 Loading required host kernel modules (vhost, vhost_net, vhost_vsock)..."
for mod in vhost vhost_net vhost_vsock; do
    if sudo modprobe "$mod" 2>/dev/null; then
        echo "   ✓ Loaded module: $mod"
    else
        echo "   ⚠️ Notice: Unable to load module '$mod' (it may be built-in or require kernel headers)"
    fi
done

# Persist kernel modules on boot via /etc/modules-load.d/kata.conf
if [ -d "/etc/modules-load.d" ]; then
    cat << 'EOF' | sudo tee /etc/modules-load.d/kata.conf >/dev/null
# Kernel modules required for Kata Containers hypervisor isolation
vhost
vhost_net
vhost_vsock
EOF
    echo "✓ Configured /etc/modules-load.d/kata.conf for persistent module loading across reboots."
fi

# Ensure user is in kvm group if group exists
CURRENT_USER="${USER:-$(id -un)}"
if getent group kvm >/dev/null 2>&1; then
    if ! id -nG "$CURRENT_USER" 2>/dev/null | grep -qw "kvm"; then
        echo "👤 Adding current user '$CURRENT_USER' to the 'kvm' group..."
        sudo usermod -aG kvm "$CURRENT_USER" 2>/dev/null || true
        echo "✓ User added to 'kvm' group (changes apply on your next shell or run: newgrp kvm)"
    fi
fi

# 3. Determine version and download URL
# Default to 3.12.0: Stable release bundling the complete kata-runtime OCI engine
DEFAULT_VERSION="3.12.0"
VERSION="${1:-$DEFAULT_VERSION}"

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

DOWNLOAD_URL=""

echo "🌐 Resolving Kata Containers release (${VERSION})..."
candidates=(
    "https://github.com/kata-containers/kata-containers/releases/download/${VERSION}/kata-static-${VERSION}-${PRIMARY_ARCH}.tar.xz"
    "https://github.com/kata-containers/kata-containers/releases/download/${VERSION}/kata-static-${VERSION}-${PRIMARY_ARCH}.tar.zst"
    "https://github.com/kata-containers/kata-containers/releases/download/${VERSION}/kata-static-${VERSION}-${ALT_ARCH}.tar.xz"
    "https://github.com/kata-containers/kata-containers/releases/download/${VERSION}/kata-static-${VERSION}-${ALT_ARCH}.tar.zst"
    "https://github.com/kata-containers/kata-containers/releases/download/v${VERSION}/kata-static-${VERSION}-${PRIMARY_ARCH}.tar.xz"
    "https://github.com/kata-containers/kata-containers/releases/download/v${VERSION}/kata-static-${VERSION}-${PRIMARY_ARCH}.tar.zst"
    "https://github.com/kata-containers/kata-containers/releases/download/v${VERSION}/kata-static-${VERSION}-${ALT_ARCH}.tar.xz"
    "https://github.com/kata-containers/kata-containers/releases/download/v${VERSION}/kata-static-${VERSION}-${ALT_ARCH}.tar.zst"
)
for cand in "${candidates[@]}"; do
    status="$(curl -sIL -o /dev/null -w "%{http_code}" "$cand" || true)"
    if [ "$status" = "200" ]; then
        DOWNLOAD_URL="$cand"
        break
    fi
done

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Error: Could not locate a static release asset for Kata Containers ${VERSION} (${PRIMARY_ARCH})." >&2
    echo "Please check available releases at: https://github.com/kata-containers/kata-containers/releases" >&2
    exit 1
fi

TAR_NAME="$(basename "$DOWNLOAD_URL")"
echo "✓ Selected release package: ${TAR_NAME}"

# 4. Decompression dependencies check
if [[ "$TAR_NAME" == *.zst ]] && ! command -v zstd >/dev/null 2>&1; then
    echo "📦 Package 'zstd' is required to extract .tar.zst archives."
    if command -v apt-get >/dev/null 2>&1; then
        echo "   Installing 'zstd' via apt-get..."
        sudo apt-get update -qq
        sudo apt-get install -y zstd
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y zstd
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm zstd
    else
        echo "❌ Error: 'zstd' command not found. Please install zstd to unpack Kata Containers." >&2
        exit 1
    fi
elif [[ "$TAR_NAME" == *.xz ]] && ! command -v xz >/dev/null 2>&1; then
    echo "📦 Package 'xz-utils' is required to extract .tar.xz archives."
    if command -v apt-get >/dev/null 2>&1; then
        echo "   Installing 'xz-utils' via apt-get..."
        sudo apt-get update -qq
        sudo apt-get install -y xz-utils
    fi
fi

# 5. Download static bundle
echo "⬇️ Downloading ${TAR_NAME}..."
echo "   URL: ${DOWNLOAD_URL}"
if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o "${TMP_DIR}/${TAR_NAME}"; then
    echo "❌ Error: Failed to download Kata Containers from ${DOWNLOAD_URL}." >&2
    exit 1
fi

# 6. Clean up prior installation to prevent version conflicts
echo "🧹 Checking for existing Kata Containers installation..."
OLD_VERSION=""
if [ -f "/opt/kata/VERSION" ]; then
    OLD_VERSION="$(cat /opt/kata/VERSION 2>/dev/null | tr -d '[:space:]' || true)"
elif command -v kata-runtime >/dev/null 2>&1; then
    OLD_VERSION="$(kata-runtime --version 2>/dev/null | head -n 1 | awk '{print $3}' || true)"
fi

if [ -d "/opt/kata" ] || [ -L "/usr/local/bin/kata-runtime" ] || [ -e "/usr/local/bin/kata-runtime" ] || [ -L "/usr/local/bin/kata-ctl" ] || [ -e "/usr/local/bin/kata-ctl" ]; then
    if [ -n "$OLD_VERSION" ]; then
        echo "   Found existing installation (version: ${OLD_VERSION}). Removing to prevent version conflicts..."
    else
        echo "   Found existing /opt/kata or symlinks. Removing to ensure clean installation..."
    fi
    sudo rm -rf /opt/kata
    sudo rm -f /usr/local/bin/kata-runtime /usr/local/bin/kata-ctl /usr/local/bin/containerd-shim-kata-v2
    echo "✓ Prior installation cleaned up."
else
    echo "✓ No existing installation found."
fi

if command -v dpkg >/dev/null 2>&1 && dpkg -s kata-containers >/dev/null 2>&1; then
    echo "ℹ️ Note: An older 'kata-containers' package was found in dpkg/apt."
    echo "   The new static release in /opt/kata and /usr/local/bin will take precedence."
    echo "   (You may optionally remove the distro package: sudo apt-get remove --purge -y kata-containers)"
fi

# 7. Extract to /opt/kata
echo "📦 Extracting Kata Containers static bundle to /opt/kata..."
sudo mkdir -p /opt/kata
if [[ "$TAR_NAME" == *.zst ]]; then
    sudo tar --zstd -xf "${TMP_DIR}/${TAR_NAME}" -C /
elif [[ "$TAR_NAME" == *.xz ]]; then
    sudo tar -xJf "${TMP_DIR}/${TAR_NAME}" -C /
elif [[ "$TAR_NAME" == *.gz ]]; then
    sudo tar -xzf "${TMP_DIR}/${TAR_NAME}" -C /
else
    sudo tar -xf "${TMP_DIR}/${TAR_NAME}" -C /
fi

# 8. Create symlinks in /usr/local/bin
echo "🔗 Symlinking binaries to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
if [ -e "/opt/kata/bin/kata-runtime" ]; then
    sudo ln -sf /opt/kata/bin/kata-runtime /usr/local/bin/kata-runtime
fi
if [ -e "/opt/kata/bin/kata-ctl" ]; then
    sudo ln -sf /opt/kata/bin/kata-ctl /usr/local/bin/kata-ctl
fi
if [ -e "/opt/kata/bin/containerd-shim-kata-v2" ]; then
    sudo ln -sf /opt/kata/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata-v2
elif [ -e "/opt/kata/runtime-rs/bin/containerd-shim-kata-v2" ]; then
    sudo ln -sf /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata-v2
fi

# 9. Container engine registration
if command -v docker >/dev/null 2>&1; then
    echo "🐳 Configuring Docker daemon for Kata Containers..."
    DAEMON_JSON="/etc/docker/daemon.json"
    sudo mkdir -p /etc/docker
    if [ -f "$DAEMON_JSON" ]; then
        if command -v jq >/dev/null 2>&1; then
            sudo jq '.runtimes["kata-runtime"] = {"path": "/usr/local/bin/kata-runtime"}' "$DAEMON_JSON" > "${TMP_DIR}/daemon.json"
            sudo cp "${TMP_DIR}/daemon.json" "$DAEMON_JSON"
            echo "✓ Added 'kata-runtime' to ${DAEMON_JSON}"
        elif command -v python3 >/dev/null 2>&1; then
            sudo python3 -c "import json; p='$DAEMON_JSON'; data = json.load(open(p)) if open(p).read().strip() else {}; data.setdefault('runtimes', {})['kata-runtime'] = {'path': '/usr/local/bin/kata-runtime'}; open(p, 'w').write(json.dumps(data, indent=2))"
            echo "✓ Added 'kata-runtime' to ${DAEMON_JSON}"
        else
            echo "ℹ️ Please verify /etc/docker/daemon.json contains the kata-runtime definition."
        fi
    else
        cat << 'EOF' | sudo tee "$DAEMON_JSON" >/dev/null
{
  "runtimes": {
    "kata-runtime": {
      "path": "/usr/local/bin/kata-runtime"
    }
  }
}
EOF
        echo "✓ Created ${DAEMON_JSON} with kata-runtime registered."
    fi

    if systemctl is-active --quiet docker 2>/dev/null; then
        echo "🔄 Reloading Docker daemon..."
        sudo systemctl restart docker 2>/dev/null || true
    fi
fi

if command -v podman >/dev/null 2>&1; then
    echo "🦭 Podman detected. aiab will automatically invoke Kata via:"
    echo "   /usr/local/bin/kata-runtime"
fi

# 10. Run verification check
echo ""
echo "🩺 Running Kata verification check..."
if [ -x "/usr/local/bin/kata-runtime" ]; then
    if /usr/local/bin/kata-runtime kata-check 2>&1; then
        echo "✓ Kata check completed successfully!"
    else
        echo "ℹ️ kata-check finished (review any warnings above)."
    fi
elif [ -x "/usr/local/bin/kata-ctl" ]; then
    if /usr/local/bin/kata-ctl check 2>&1; then
        echo "✓ Kata check completed successfully!"
    else
        echo "ℹ️ kata-ctl check finished (review any warnings above)."
    fi
fi

echo ""
echo "=========================================================="
echo "🎉 Kata Containers installed successfully!"
echo "aiab will now automatically launch inside hardware microVMs:"
echo "  aiab"
echo "  aiab check-kata"
echo "=========================================================="
