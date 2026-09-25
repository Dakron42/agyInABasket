#!/usr/bin/env bash
#
# tests/test_runner.sh: Test suite for agyInABasket (aiab)
#

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIAB_BIN="${REPO_DIR}/bin/aiab"
ENTRYPOINT="${REPO_DIR}/entrypoint.sh"
INSTALL_SH="${REPO_DIR}/scripts/install.sh"
INSTALL_KATA_SH="${REPO_DIR}/scripts/install-kata.sh"
AIAB_BASH="${REPO_DIR}/shell/aiab.bash"

PASSED=0
FAILED=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_case() {
    local name="$1"
    TOTAL=$((TOTAL + 1))
    echo -e "${BLUE}[TEST ${TOTAL}]${NC} ${name}..."
}

assert_success() {
    local status="$1"
    local desc="${2:-Test should exit 0}"
    if [ "$status" -eq 0 ]; then
        echo -e "  ${GREEN}✓ PASS:${NC} ${desc}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAIL:${NC} ${desc} (expected exit code 0, got ${status})"
        FAILED=$((FAILED + 1))
    fi
}

assert_failure() {
    local status="$1"
    local desc="${2:-Test should exit non-zero}"
    if [ "$status" -ne 0 ]; then
        echo -e "  ${GREEN}✓ PASS:${NC} ${desc}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAIL:${NC} ${desc} (expected failure, got 0)"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local output="$1"
    local pattern="$2"
    local desc="${3:-Output should contain pattern}"
    if echo "$output" | grep -F -q -e "$pattern"; then
        echo -e "  ${GREEN}✓ PASS:${NC} ${desc}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAIL:${NC} ${desc} (pattern '$pattern' not found)"
        FAILED=$((FAILED + 1))
    fi
}

echo "=========================================================="
echo "          agyInABasket (aiab) Test Suite                  "
echo "=========================================================="

# ------------------------------------------------------------
# Test 1: Bash syntax verification
# ------------------------------------------------------------
test_case "Syntax checking bash scripts"
bash -n "${AIAB_BIN}" && \
bash -n "${ENTRYPOINT}" && \
bash -n "${INSTALL_SH}" && \
bash -n "${INSTALL_KATA_SH}" && \
bash -n "${AIAB_BASH}"
assert_success $? "All bash scripts pass 'bash -n' syntax verification"

test_case "Permissions check"
[ -x "${AIAB_BIN}" ] && [ -x "${ENTRYPOINT}" ] && [ -x "${INSTALL_SH}" ] && [ -x "${INSTALL_KATA_SH}" ]
assert_success $? "bin/aiab, entrypoint.sh, scripts/install.sh, and scripts/install-kata.sh are executable"

# ------------------------------------------------------------
# Test 2: Help message output and subcommands listing
# ------------------------------------------------------------
test_case "aiab --help displays usage and subcommands"
output=$("${AIAB_BIN}" --help 2>&1)
status=$?
assert_success "$status" "aiab --help exits successfully"
assert_contains "$output" "aiab (Antigravity In A Basket)" "Shows correct program title"
assert_contains "$output" "update" "Lists 'update' subcommand"
assert_contains "$output" "rebuild" "Lists 'rebuild' subcommand"
assert_contains "$output" "status" "Lists 'status' subcommand"
assert_contains "$output" "clean" "Lists 'clean' subcommand"
assert_contains "$output" "check-kata" "Lists 'check-kata' subcommand"
assert_contains "$output" "config" "Lists 'config' subcommand"
assert_contains "$output" "backup-auth" "Lists 'backup-auth' subcommand"
assert_contains "$output" "reset-auth" "Lists 'reset-auth' subcommand"
assert_contains "$output" "uninstall" "Lists 'uninstall' subcommand"
assert_contains "$output" "--kata" "Lists '--kata' argument"
assert_contains "$output" "--no-kata" "Lists '--no-kata' argument"
assert_contains "$output" "KATA_RUNTIME" "Lists 'KATA_RUNTIME' config"
assert_contains "$output" "AIAB_CONFIG_FILE" "Lists 'AIAB_CONFIG_FILE' config"

test_case "aiab -h works as shorthand for --help"
output=$("${AIAB_BIN}" -h 2>&1)
assert_success $? "aiab -h exits successfully"
assert_contains "$output" "Usage:" "Shows usage block"

# Setup temporary sandbox for mock environments
TEST_SANDBOX="$(mktemp -d)"
MOCK_BIN="${TEST_SANDBOX}/bin"
mkdir -p "${MOCK_BIN}"

# Mock standard docker
cat << 'EOF' > "${MOCK_BIN}/docker"
#!/usr/bin/env bash
if [ "${1:-}" = "info" ]; then
    if [ -n "${MOCK_DOCKER_INFO_OUTPUT:-}" ]; then
        echo "${MOCK_DOCKER_INFO_OUTPUT}"
    fi
    exit 0
fi
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
    exit 0
fi
if [ "${1:-}" = "volume" ] && [ "${2:-}" = "create" ]; then
    exit 0
fi
if [ "${1:-}" = "run" ]; then
    echo "MOCK_DOCKER_RUN: $@"
    exit 0
fi
echo "MOCK_DOCKER_OTHER: $@"
exit 0
EOF
chmod +x "${MOCK_BIN}/docker"

# ------------------------------------------------------------
# Test 3: Validation on non-existent directories
# ------------------------------------------------------------
test_case "aiab rejects non-existent directory"
missing_dir_output=$(PATH="${MOCK_BIN}:${PATH}" "${AIAB_BIN}" "/non/existent/path/for/sure/$$" 2>&1 || true)
assert_contains "$missing_dir_output" "Directory does not exist" "Displays error message on missing directory"

# ------------------------------------------------------------
# Test 4: Docker invocation and flags assembly
# ------------------------------------------------------------
test_case "aiab runs docker with correct args and mounts"
TARGET_DIR="${TEST_SANDBOX}/project"
mkdir -p "${TARGET_DIR}"

run_output=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker "${AIAB_BIN}" "${TARGET_DIR}" --continue --model "Gemini 2.5 Pro" 2>&1)
assert_contains "$run_output" "MOCK_DOCKER_RUN:" "Successfully invoked docker run"
assert_contains "$run_output" "-v ${TARGET_DIR}:/home/minty/workspace" "Target directory correctly mounted to /home/minty/workspace"
assert_contains "$run_output" "-v agy-data:/home/minty/.gemini" "Persistent volume agy-data mounted"
assert_contains "$run_output" "-v agy-config:/home/minty/.config" "Persistent volume agy-config mounted"
assert_contains "$run_output" "--continue" "Forwarded --continue flag"
assert_contains "$run_output" "Gemini 2.5 Pro" "Forwarded --model flag"

# ------------------------------------------------------------
# Test 5: Podman auto-detection, flags, and SELinux volume relabeling
# ------------------------------------------------------------
test_case "aiab supports Podman with --userns=keep-id and :Z volume mount"
cat << 'EOF' > "${MOCK_BIN}/podman"
#!/usr/bin/env bash
if [ "${1:-}" = "info" ]; then
    exit 0
fi
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
    exit 0
fi
if [ "${1:-}" = "volume" ] && [ "${2:-}" = "create" ]; then
    exit 0
fi
if [ "${1:-}" = "run" ]; then
    echo "MOCK_PODMAN_RUN: $@"
    exit 0
fi
echo "MOCK_PODMAN_OTHER: $@"
exit 0
EOF
chmod +x "${MOCK_BIN}/podman"

podman_output=$(PATH="${MOCK_BIN}:${PATH}" "${AIAB_BIN}" "${TARGET_DIR}" 2>&1)
assert_contains "$podman_output" "MOCK_PODMAN_RUN:" "Podman detected and invoked"
assert_contains "$podman_output" "--userns=keep-id" "Podman uses rootless --userns=keep-id flag"
assert_contains "$podman_output" "-v ${TARGET_DIR}:/home/minty/workspace:Z" "Workspace volume mounted with SELinux :Z flag"

# ------------------------------------------------------------
# Test 6: Docker daemon error handling
# ------------------------------------------------------------
test_case "aiab gracefully handles Docker daemon down"
cat << 'EOF' > "${MOCK_BIN}/docker"
#!/usr/bin/env bash
if [ "${1:-}" = "info" ]; then
    echo "Cannot connect to Docker daemon" >&2
    exit 1
fi
exit 0
EOF
daemon_down_output=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker "${AIAB_BIN}" 2>&1 || true)
assert_contains "$daemon_down_output" "Cannot connect to Docker daemon" "Detects and reports unavailable Docker daemon"

# ------------------------------------------------------------
# Test 7: entrypoint.sh argument routing
# ------------------------------------------------------------
test_case "entrypoint.sh default invokes agy with --dangerously-skip-permissions"
MOCK_AGY_LOG="${TEST_SANDBOX}/agy_invoked.log"
cat << 'EOF' > "${MOCK_BIN}/agy"
#!/usr/bin/env bash
echo "$@" > "${TEST_MOCK_LOG}"
EOF
chmod +x "${MOCK_BIN}/agy"

TEST_MOCK_LOG="${MOCK_AGY_LOG}" PATH="${MOCK_BIN}:${PATH}" "${ENTRYPOINT}"
agy_args=$(cat "${MOCK_AGY_LOG}")
assert_contains "$agy_args" "--dangerously-skip-permissions" "Default invocation passes --dangerously-skip-permissions"

test_case "entrypoint.sh forwards options with --dangerously-skip-permissions"
TEST_MOCK_LOG="${MOCK_AGY_LOG}" PATH="${MOCK_BIN}:${PATH}" "${ENTRYPOINT}" --continue --model test-model
agy_args=$(cat "${MOCK_AGY_LOG}")
assert_contains "$agy_args" "--dangerously-skip-permissions --continue --model test-model" "Options prepended with --dangerously-skip-permissions"

test_case "entrypoint.sh executes arbitrary command (e.g. echo)"
arbitrary_output=$("${ENTRYPOINT}" echo "hello-from-container")
assert_contains "$arbitrary_output" "hello-from-container" "Arbitrary commands bypass agy"

# ------------------------------------------------------------
# Test 8: shell/aiab.bash loading and function export
# ------------------------------------------------------------
test_case "shell/aiab.bash defines aiab function cleanly"
func_check=$(bash -c "source '${AIAB_BASH}' && type aiab | head -n 1")
assert_contains "$func_check" "aiab is a function" "aiab is exported as a bash function"

# ------------------------------------------------------------
# Test 9: Subcommand routing
# ------------------------------------------------------------
test_case "aiab clean invokes pruning"
cat << 'EOF' > "${MOCK_BIN}/docker"
#!/usr/bin/env bash
if [ "${1:-}" = "info" ]; then
    exit 0
fi
if [ "${1:-}" = "ps" ]; then
    exit 0
fi
if [ "${1:-}" = "image" ] && [ "${2:-}" = "prune" ]; then
    echo "MOCK_PRUNED"
    exit 0
fi
exit 0
EOF

clean_output=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker "${AIAB_BIN}" clean 2>&1)
assert_contains "$clean_output" "Cleanup finished!" "aiab clean executes cleanup flow"

# ------------------------------------------------------------
# Test 10: Kata Containers & Hypervisor Integration
# ------------------------------------------------------------
test_case "aiab check-kata runs diagnostic check"
check_kata_out=$(PATH="${MOCK_BIN}:${PATH}" "${AIAB_BIN}" check-kata 2>&1 || true)
assert_contains "$check_kata_out" "Kata Containers & KVM Hypervisor Diagnostic" "check-kata prints diagnostic header"
assert_contains "$check_kata_out" "Checking hardware virtualization" "check-kata checks KVM device"
assert_contains "$check_kata_out" "Checking Kata Containers installation" "check-kata checks Kata binaries"

test_case "aiab status outputs hypervisor isolation section"
cat << 'EOF' > "${MOCK_BIN}/docker"
#!/usr/bin/env bash
if [ "${1:-}" = "info" ]; then exit 0; fi
if [ "${1:-}" = "images" ]; then echo "IMAGE_LINE"; exit 0; fi
if [ "${1:-}" = "volume" ]; then echo "VOLUME_LINE"; exit 0; fi
if [ "${1:-}" = "run" ]; then echo "v1.0.0"; exit 0; fi
exit 0
EOF
status_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker "${AIAB_BIN}" status 2>&1)
assert_contains "$status_out" "Hypervisor Isolation (Kata Containers)" "status reports Hypervisor isolation section"

test_case "aiab --kata rejects execution when KVM is missing"
no_kvm_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${TEST_SANDBOX}/nonexistent_kvm" "${AIAB_BIN}" --kata 2>&1 || true)
assert_contains "$no_kvm_out" "Hardware virtualization is required for Kata Containers" "Reports error on missing KVM"

test_case "aiab --kata passes --runtime=kata-runtime and does not forward --kata to agy"
cat << 'EOF' > "${MOCK_BIN}/docker"
#!/usr/bin/env bash
if [ "${1:-}" = "info" ]; then
    if [ -n "${MOCK_DOCKER_INFO_OUTPUT:-}" ]; then
        echo "${MOCK_DOCKER_INFO_OUTPUT}"
    fi
    exit 0
fi
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then exit 0; fi
if [ "${1:-}" = "volume" ]; then exit 0; fi
if [ "${1:-}" = "run" ]; then
    echo "MOCK_DOCKER_RUN: $@"
    exit 0
fi
exit 0
EOF
MOCK_KVM="${TEST_SANDBOX}/mock_kvm"
touch "${MOCK_KVM}"
chmod 666 "${MOCK_KVM}"

kata_run_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" "${AIAB_BIN}" "${TARGET_DIR}" --kata --continue 2>&1)
assert_contains "$kata_run_out" "--runtime=kata-runtime" "Appends --runtime=kata-runtime to container run"
assert_contains "$kata_run_out" "Hypervisor Isolation: Kata Containers microVM active" "Displays hypervisor announcement banner"
assert_contains "$kata_run_out" "--continue" "Forwards target arguments"

run_cmd_line=$(echo "$kata_run_out" | grep "MOCK_DOCKER_RUN:" || true)
if echo "$run_cmd_line" | grep -q "agy-yolo:latest.*--kata"; then
    echo -e "  ${RED}✗ FAIL:${NC} --kata was forwarded to agy inside container"
    FAILED=$((FAILED + 1))
else
    echo -e "  ${GREEN}✓ PASS:${NC} --kata flag is filtered out of inner container arguments"
    PASSED=$((PASSED + 1))
fi

test_case "aiab supports AIAB_KATA=1 environment variable"
env_kata_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker AIAB_KATA=1 KVM_DEVICE="${MOCK_KVM}" "${AIAB_BIN}" "${TARGET_DIR}" 2>&1)
assert_contains "$env_kata_out" "--runtime=kata-runtime" "AIAB_KATA=1 appends --runtime=kata-runtime"

test_case "aiab --hypervisor works as alias for --kata"
alias_kata_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" "${AIAB_BIN}" "${TARGET_DIR}" --hypervisor 2>&1)
assert_contains "$alias_kata_out" "--runtime=kata-runtime" "--hypervisor flag enables Kata microVM runtime"

# ------------------------------------------------------------
# Test 11: Configuration Management & Persistence
# ------------------------------------------------------------
test_case "aiab config show displays settings and file path"
TEST_CONFIG="${TEST_SANDBOX}/test_config"
cfg_show_out=$(AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config show 2>&1)
assert_contains "$cfg_show_out" "=== agyInABasket Configuration ===" "Displays configuration header"
assert_contains "$cfg_show_out" "${TEST_CONFIG}" "Displays custom config file path"

test_case "aiab config set and get modify and read persistent settings"
AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config set AIAB_KATA 1 >/dev/null
val_kata=$(AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config get AIAB_KATA)
if [ "$val_kata" = "1" ]; then
    echo -e "  ${GREEN}✓ PASS:${NC} AIAB_KATA was set and retrieved as '1'"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ FAIL:${NC} Expected AIAB_KATA to be '1', got '$val_kata'"
    FAILED=$((FAILED + 1))
fi

AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config set DEFAULT_MODEL "Gemini 2.5 Pro" >/dev/null
val_model=$(AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config get DEFAULT_MODEL)
if [ "$val_model" = "Gemini 2.5 Pro" ]; then
    echo -e "  ${GREEN}✓ PASS:${NC} DEFAULT_MODEL was set and retrieved as 'Gemini 2.5 Pro'"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ FAIL:${NC} Expected DEFAULT_MODEL to be 'Gemini 2.5 Pro', got '$val_model'"
    FAILED=$((FAILED + 1))
fi

test_case "aiab activates Kata microVM by default when enabled in config file"
cfg_kata_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" "${TARGET_DIR}" 2>&1)
assert_contains "$cfg_kata_out" "--runtime=kata-runtime" "Persistent config enabled Kata microVM runtime"
assert_contains "$cfg_kata_out" "--model Gemini 2.5 Pro" "Persistent config injected default model"

test_case "aiab --no-kata overrides persistent config and disables Kata runtime"
no_kata_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" "${TARGET_DIR}" --no-kata 2>&1)
if echo "$no_kata_out" | grep -q -- "--runtime=kata-runtime"; then
    echo -e "  ${RED}✗ FAIL:${NC} --no-kata failed to disable Kata runtime"
    FAILED=$((FAILED + 1))
else
    echo -e "  ${GREEN}✓ PASS:${NC} --no-kata flag successfully disabled Kata runtime"
    PASSED=$((PASSED + 1))
fi

test_case "CLI --model overrides config DEFAULT_MODEL"
model_override_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" "${TARGET_DIR}" --model "Claude 3.7 Sonnet" 2>&1)
assert_contains "$model_override_out" "Claude 3.7 Sonnet" "CLI --model overrides config default model"

test_case "aiab config reset restores defaults"
AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config reset >/dev/null
reset_kata=$(AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config get AIAB_KATA)
reset_model=$(AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" config get DEFAULT_MODEL)
if [ "$reset_kata" = "auto" ] && [ -z "$reset_model" ]; then
    echo -e "  ${GREEN}✓ PASS:${NC} Configuration was reset to defaults (AIAB_KATA=auto)"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ FAIL:${NC} Reset failed (AIAB_KATA=$reset_kata, DEFAULT_MODEL=$reset_model)"
    FAILED=$((FAILED + 1))
fi

# ------------------------------------------------------------
# Test 12: Defaulting to Kata when installed
# ------------------------------------------------------------
test_case "aiab defaults to Kata microVM when installed and AIAB_KATA is auto"
# Create mock kata-runtime executable in PATH
cat << 'EOF' > "${MOCK_BIN}/kata-runtime"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${MOCK_BIN}/kata-runtime"

# With kata-runtime in PATH and MOCK_KVM present, default run should use Kata
auto_kata_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" "${TARGET_DIR}" 2>&1)
assert_contains "$auto_kata_out" "--runtime=kata-runtime" "Auto-detected Kata and enabled microVM by default"
assert_contains "$auto_kata_out" "Hypervisor Isolation: Kata Containers microVM active" "Auto-announced microVM banner"

test_case "aiab falls back to standard container when Kata is not installed and AIAB_KATA is auto"
# Remove mock kata-runtime
rm -f "${MOCK_BIN}/kata-runtime"
fallback_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" "${TARGET_DIR}" 2>&1)
if echo "$fallback_out" | grep -q -- "--runtime=kata-runtime"; then
    echo -e "  ${RED}✗ FAIL:${NC} Erroneously enabled Kata runtime when kata-runtime was missing"
    FAILED=$((FAILED + 1))
else
    echo -e "  ${GREEN}✓ PASS:${NC} Gracefully fell back to standard container when kata-runtime was missing"
    PASSED=$((PASSED + 1))
fi

test_case "aiab detects Kata binary in /opt/kata/bin/kata-runtime"
OPT_KATA_DIR="${TEST_SANDBOX}/opt/kata/bin"
mkdir -p "${OPT_KATA_DIR}"
cat << 'EOF' > "${OPT_KATA_DIR}/kata-runtime"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${OPT_KATA_DIR}/kata-runtime"

opt_kata_out=$(PATH="${OPT_KATA_DIR}:${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" AIAB_CONFIG_FILE="${TEST_CONFIG}" "${AIAB_BIN}" "${TARGET_DIR}" 2>&1)
assert_contains "$opt_kata_out" "--runtime=kata-runtime" "Auto-detected Kata static binary in /opt/kata/bin"

test_case "scripts/install-kata.sh detects and cleans up existing installations"
assert_contains "$(cat "${INSTALL_KATA_SH}")" "Clean up prior installation to prevent version conflicts" "install-kata.sh includes prior version cleanup step"
assert_contains "$(cat "${INSTALL_KATA_SH}")" "rm -rf /opt/kata" "install-kata.sh cleans existing /opt/kata directory"
assert_contains "$(cat "${INSTALL_KATA_SH}")" "rm -f /usr/local/bin/kata-runtime" "install-kata.sh cleans existing symlinks"

test_case "aiab handles Podman Kata incompatibility gracefully"
podman_kata_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=podman KVM_DEVICE="${MOCK_KVM}" "${AIAB_BIN}" "${TARGET_DIR}" --kata 2>&1 || true)
assert_contains "$podman_kata_out" "Podman does not support Kata Containers" "Informs user of Podman Kata incompatibility"

test_case "aiab routes Docker to io.containerd.kata.v2 when containerd-shim-kata-v2 is in PATH"
cat << 'EOF' > "${MOCK_BIN}/containerd-shim-kata-v2"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${MOCK_BIN}/containerd-shim-kata-v2"

docker_shim_out=$(PATH="${MOCK_BIN}:${PATH}" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" "${AIAB_BIN}" "${TARGET_DIR}" --kata 2>&1)
assert_contains "$docker_shim_out" "--runtime=io.containerd.kata.v2" "Docker automatically uses io.containerd.kata.v2 from PATH"

test_case "aiab preserves kata-runtime when explicitly registered in docker info"
docker_registered_out=$(PATH="${MOCK_BIN}:${PATH}" MOCK_DOCKER_INFO_OUTPUT="Runtimes: runc kata-runtime" CONTAINER_RUNTIME=docker KVM_DEVICE="${MOCK_KVM}" "${AIAB_BIN}" "${TARGET_DIR}" --kata 2>&1)
assert_contains "$docker_registered_out" "--runtime=kata-runtime" "Docker uses kata-runtime when present in docker info"
rm -f "${MOCK_BIN}/containerd-shim-kata-v2"

# Clean up sandbox
rm -rf "${TEST_SANDBOX}"

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "=========================================================="
echo -e "Total: ${TOTAL} checks | Passed: ${GREEN}${PASSED}${NC} | Failed: ${RED}${FAILED}${NC}"
echo "=========================================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
