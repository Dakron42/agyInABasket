# Changelog

All notable changes to `agyInABasket` (`aiab`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-09-25

### Added
- **Hardware Hypervisor Isolation (Kata Containers)**: Optional microVM isolation via `--kata` / `--hypervisor`, running containers within dedicated KVM virtual machines.
- **Zero-Config containerd Discovery**: Dynamic resolution of `io.containerd.kata.v2` from `$PATH` without requiring modifications to `/etc/docker/daemon.json`.
- **Modern Kata 3.32.0+ Support**: Bundles the fix for Docker 29+ private time namespaces (PR #13082 / Issue #13080).
- **Automated Kata Installer**: [`scripts/install-kata.sh`](scripts/install-kata.sh) for downloading, verifying, and symlinking Kata Containers static releases.
- **Diagnostics**: `aiab check-kata` command to inspect host KVM virtualization, kernel acceleration modules (`vhost`, `vhost_net`, `vhost_vsock`), and runtime status.
- **Persistent Configuration Menu**: `aiab config` interactive menu and scriptable CLI (`aiab config get/set/show/reset`) with XDG-compliant storage.
- **Engine Routing**: Intelligent auto-routing from Podman to Docker when Kata microVM isolation is requested.
- **CLI Options**: Added `--dry-run`, `--version` (`-V`), and `--key=value` syntax support (`--model=...`, `--effort=...`).
- **Container User Config**: Support for custom container usernames via `AIAB_CONTAINER_USER` (defaults to `minty`).
- **CI Enhancements**: Added ShellCheck linting and Dockerfile build verification to GitHub Actions.

### Changed
- Refactored `cmd_update` and `cmd_rebuild` to use a shared `_build_image` helper.
- Optimized config parser to use native bash parameter expansion instead of subshell `sed` processes.
- Updated `entrypoint.sh` YOLO mode detection to iterate exact arguments rather than substring matching.
- Streamlined `shell/aiab.bash` into a pure delegation wrapper targeting `aiab`.
- Replaced `busybox` dependency in `cmd_backup_auth` with the existing container image (`${AGY_IMAGE}`).
- Sanitized session slug naming to prevent trailing underscores from command substitution.

---

## [1.0.0] - 2026-09-24

### Added
- Initial release of `agyInABasket` (`aiab`).
- Sandboxed Google Antigravity CLI execution with `--dangerously-skip-permissions`.
- Dual container engine support: Docker and rootless Podman.
- Host UID/GID dynamic alignment during container image build.
- Persistent volumes for authentication (`agy-data`) and configuration (`agy-config`).
- Maintenance subcommands: `update`, `rebuild`, `status`, `clean`, `backup-auth`, `reset-auth`, and `uninstall`.
- Automated standalone test runner in `tests/test_runner.sh`.
