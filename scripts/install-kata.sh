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
    x86_64)  KATA_ARCH="x86_64" ;;
    aarch64) KATA_ARCH="aarch64" ;;
    *)
        echo "❌ Error: Unsupported architecture '$ARCH'. Kata static binaries support x86_64 and aarch64." >&2
        exit 1
        ;;
esac

# 2. Hardware virtualization check
echo "🔍 Checking hardware virtualization (VT-x / AMD-V)..."
if [ ! -e "/dev/kvm" ]; then
    echo "⚠️ Warning: /dev/kvm device node was not found."
    if grep -E -q '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
        echo "   CPU supports virtualization! You may need to load the kvm module:"
        echo "     sudo modprobe kvm"
        echo "     sudo modprobe kvm_intel  # or kvm_amd"
    else
        echo "   ❌ Your CPU does not appear to support hardware virtualization or it is disabled in BIOS/UEFI." >&2
        echo "   Please enable Intel VT-x or AMD-V in your BIOS/UEFI settings." >&2
    fi
else
    echo "✓ Hardware virtualization (/dev/kvm) detected."
fi

# Ensure user is in kvm group
if ! groups 2>/dev/null | grep -qw "kvm"; then
    echo "👤 Adding current user '$USER' to the 'kvm' group..."
    sudo usermod -aG kvm "$USER" 2>/dev/null || true
    echo "✓ User added to 'kvm' group (changes apply on your next shell or run: newgrp kvm)"
fi

# 3. Determine version to install
FALLBACK_VERSION="3.12.0"
VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "🌐 Checking latest Kata Containers release from GitHub..."
    LATEST_TAG="$(curl -fsSL https://api.github.com/repos/kata-containers/kata-containers/releases/latest 2>/dev/null | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [ -n "$LATEST_TAG" ]; then
        VERSION="${LATEST_TAG#v}"
        echo "✓ Found release version: ${VERSION}"
    else
        VERSION="$FALLBACK_VERSION"
        echo "ℹ️ Using stable release version: ${VERSION}"
    fi
fi

TAR_NAME="kata-static-${VERSION}-${KATA_ARCH}.tar.xz"
DOWNLOAD_URL="https://github.com/kata-containers/kata-containers/releases/download/${VERSION}/${TAR_NAME}"
TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 4. Download static bundle
echo "⬇️ Downloading ${TAR_NAME}..."
echo "   URL: ${DOWNLOAD_URL}"
if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o "${TMP_DIR}/${TAR_NAME}"; then
    echo "❌ Error: Failed to download Kata Containers from ${DOWNLOAD_URL}." >&2
    exit 1
fi

# 5. Extract to /opt/kata
echo "📦 Extracting Kata Containers static bundle to /opt/kata..."
sudo mkdir -p /opt/kata
sudo tar -xJf "${TMP_DIR}/${TAR_NAME}" -C /

# 6. Create symlinks in /usr/local/bin
echo "🔗 Symlinking binaries to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo ln -sf /opt/kata/bin/kata-runtime /usr/local/bin/kata-runtime
sudo ln -sf /opt/kata/bin/kata-ctl /usr/local/bin/kata-ctl
sudo ln -sf /opt/kata/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata-v2

# 7. Container engine registration
if command -v docker >/dev/null 2>&1; then
    echo "🐳 Configuring Docker daemon for Kata Containers..."
    DAEMON_JSON="/etc/docker/daemon.json"
    sudo mkdir -p /etc/docker
    if [ -f "$DAEMON_JSON" ]; then
        # Merge or inform
        if command -v jq >/dev/null 2>&1; then
            sudo jq '.runtimes["kata-runtime"] = {"path": "/usr/local/bin/kata-runtime"}' "$DAEMON_JSON" > "${TMP_DIR}/daemon.json"
            sudo cp "${TMP_DIR}/daemon.json" "$DAEMON_JSON"
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

# 8. Run verification check
echo ""
echo "🩺 Running Kata verification check..."
if /usr/local/bin/kata-runtime kata-check 2>&1; then
    echo "✓ Kata check completed successfully!"
else
    echo "ℹ️ kata-check finished (review any warnings above)."
fi

echo ""
echo "=========================================================="
echo "🎉 Kata Containers installed successfully!"
echo "aiab will now automatically launch inside hardware microVMs:"
echo "  aiab"
echo "  aiab check-kata"
echo "=========================================================="
