#!/usr/bin/env bash
#
# Bash function definition for aiab (Antigravity In A Basket)
# Add to ~/.bashrc or ~/.bash_aliases by sourcing this file or appending its contents.
# Supports both Docker and Podman container engines.
#

aiab() {
    # If installed host binary exists, prefer delegating to it
    if [ -x "${HOME}/.local/bin/aiab" ]; then
        "${HOME}/.local/bin/aiab" "$@"
        return $?
    fi

    # Fallback to direct execution if running without installed binary
    local first_arg="${1:-}"
    case "$first_arg" in
        update|rebuild|status|clean|backup-auth|reset-auth|uninstall)
            echo "❌ Maintenance commands require the installed aiab binary in ~/.local/bin." >&2
            echo "Run ./scripts/install.sh first." >&2
            return 1
            ;;
    esac

    # Runtime detection
    local runtime=""
    local podman_flags=()
    local vol_suffix=""
    if command -v podman >/dev/null 2>&1; then
        runtime="podman"
        podman_flags=("--userns=keep-id")
        vol_suffix=":Z"
    elif command -v docker >/dev/null 2>&1; then
        runtime="docker"
    else
        echo "❌ Error: Neither Podman nor Docker is installed or in PATH." >&2
        return 1
    fi

    local target_dir="."
    local agy_args=()

    if [ -n "${1:-}" ]; then
        if [ -d "$1" ]; then
            target_dir="$1"
            shift
            agy_args=("$@")
        elif [[ "$1" == -* || "$1" == "bash" || "$1" == "sh" ]]; then
            agy_args=("$@")
        else
            target_dir="$1"
            shift
            agy_args=("$@")
        fi
    fi

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Directory does not exist: $target_dir" >&2
        echo "Usage: aiab [/path/to/project] [extra options...]" >&2
        return 1
    fi

    local resolved_dir
    resolved_dir=$(realpath "$target_dir")

    "$runtime" run -it --rm "${podman_flags[@]}" \
        --name "agy-$(basename "$resolved_dir" | tr -c 'a-zA-Z0-9_' '_')-$$" \
        -e TERM="${TERM:-xterm-256color}" \
        -v "agy-data:/home/minty/.gemini" \
        -v "agy-config:/home/minty/.config" \
        -v "$resolved_dir:/home/minty/workspace${vol_suffix}" \
        agy-yolo "${agy_args[@]}"
}
