#!/usr/bin/env bash
#
# tests/test_runner.sh: Test suite for agyInABasket (aiab)
#

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIAB_BIN="${REPO_DIR}/bin/aiab"
ENTRYPOINT="${REPO_DIR}/entrypoint.sh"
INSTALL_SH="${REPO_DIR}/scripts/install.sh"
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
bash -n "${AIAB_BASH}"
assert_success $? "All bash scripts pass 'bash -n' syntax verification"

test_case "Permissions check"
[ -x "${AIAB_BIN}" ] && [ -x "${ENTRYPOINT}" ] && [ -x "${INSTALL_SH}" ]
assert_success $? "bin/aiab, entrypoint.sh, and scripts/install.sh are executable"

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
assert_contains "$output" "backup-auth" "Lists 'backup-auth' subcommand"
assert_contains "$output" "reset-auth" "Lists 'reset-auth' subcommand"
assert_contains "$output" "uninstall" "Lists 'uninstall' subcommand"
assert_contains "$output" "--kata" "Lists '--kata' argument"
assert_contains "$output" "KATA_RUNTIME" "Lists 'KATA_RUNTIME' config"

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
if [ "${1:-}" = "info" ]; then exit 0; fi
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
