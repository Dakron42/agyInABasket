#!/usr/bin/env bash
#
# Bash function definition for aiab (Antigravity In A Basket)
# Source this file in ~/.bashrc or ~/.bash_aliases:
#   source /path/to/agyInABasket/shell/aiab.bash
#
# Delegates directly to the aiab binary (in PATH or ~/.local/bin/aiab)
# to ensure full support for Kata microVMs, persistent configs, and all subcommands.
#

aiab() {
    # Check if an aiab executable exists in PATH (excluding this shell function)
    local bin_path
    bin_path="$(type -P aiab 2>/dev/null || true)"
    if [ -n "$bin_path" ] && [ -x "$bin_path" ]; then
        "$bin_path" "$@"
        return $?
    # Check ~/.local/bin/aiab directly
    elif [ -x "${HOME}/.local/bin/aiab" ]; then
        "${HOME}/.local/bin/aiab" "$@"
        return $?
    else
        echo "❌ Error: 'aiab' executable not found in PATH or ~/.local/bin/aiab." >&2
        echo "   Please run ./scripts/install.sh to build and install aiab." >&2
        return 1
    fi
}
