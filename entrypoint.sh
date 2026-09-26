#!/usr/bin/env bash
set -euo pipefail

# If .gemini is mounted and owned by root, fix ownership so container user can write tokens and configs
if [ -n "${HOME:-}" ] && [ -d "${HOME}/.gemini" ] && [ ! -w "${HOME}/.gemini" ]; then
    sudo chown -R "$(id -u):$(id -g)" "${HOME}/.gemini" 2>/dev/null || true
fi

if [ -n "${HOME:-}" ] && [ -d "${HOME}/.config" ] && [ ! -w "${HOME}/.config" ]; then
    sudo chown -R "$(id -u):$(id -g)" "${HOME}/.config" 2>/dev/null || true
fi

# Case 1: No arguments provided -> run agy in default YOLO mode
if [ $# -eq 0 ]; then
    exec agy --dangerously-skip-permissions
fi

# Case 2: First argument is a flag (starts with '-') -> forward to agy in YOLO mode
if [[ "${1:-}" == -* ]]; then
    has_yolo=false
    for arg in "$@"; do
        if [ "$arg" = "--dangerously-skip-permissions" ]; then
            has_yolo=true
            break
        fi
    done
    if [ "$has_yolo" = false ]; then
        exec agy --dangerously-skip-permissions "$@"
    else
        exec agy "$@"
    fi
fi

# Case 3: Explicitly calling 'agy'
if [ "${1:-}" = "agy" ]; then
    shift
    has_yolo=false
    for arg in "$@"; do
        if [ "$arg" = "--dangerously-skip-permissions" ]; then
            has_yolo=true
            break
        fi
    done
    if [ "$has_yolo" = false ]; then
        exec agy --dangerously-skip-permissions "$@"
    else
        exec agy "$@"
    fi
fi

# Case 4: Running custom shell or arbitrary command (e.g. bash, sh, python3)
exec "$@"
