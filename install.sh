#!/usr/bin/env bash
# DrawingLens installer — downloads the native dist from the public releases repo
# (no Python required). Usage:
#   curl -fsSL <raw>/install.sh | bash                     # installs dlens (CLI)
#   curl -fsSL <raw>/install.sh | bash -s drawinglens-mcp  # installs MCP server
#   curl -fsSL <raw>/install.sh | bash -s all              # both
#
# Layout: dist dirs live under DLENS_HOME (default ~/.local/share/drawinglens),
# binaries are symlinked into BIN_DIR (default ~/.local/bin, or wherever an
# existing installation was found). If BIN_DIR is not on PATH the installer
# appends an export line to the user's shell rc. When installing dlens, the
# SKILL.md is also propagated into every detected agent skills directory.
#
# Env overrides: DLENS_HOME, BIN_DIR, NO_SKILL=1 (skip agent-skill propagation).
set -euo pipefail

REPO="nightby/drawinglens-releases"
BASE="https://github.com/${REPO}/releases/latest/download"
DLENS_HOME="${DLENS_HOME:-$HOME/.local/share/drawinglens}"
TMP=""

cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; return 0; }
trap cleanup EXIT

die() { echo "install.sh: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

asset_suffix() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Darwin) os="macos" ;;
        Linux) os="linux" ;;
        *) die "unsupported OS: $os (windows-x64 builds pending)" ;;
    esac
    case "$arch" in
        arm64 | aarch64) arch="arm64" ;;
        x86_64 | amd64) arch="x64" ;;
        *) die "unsupported arch: $arch" ;;
    esac
    printf '%s-%s' "$os" "$arch"
}

pick_bin_dir() {
    local name="$1" existing
    if [ -n "${BIN_DIR:-}" ]; then
        printf '%s' "$BIN_DIR"
        return
    fi
    # Upgrade in place: an existing command wins over the default location.
    existing="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$existing" ]; then
        dirname "$existing"
    else
        printf '%s' "$HOME/.local/bin"
    fi
}

ensure_path() {
    local bin_dir="$1" rc
    case ":$PATH:" in
        *":${bin_dir}:"*) return 0 ;;
    esac
    if [ "$(uname -s)" = "Darwin" ] || [ -n "${ZSH_VERSION:-}" ]; then
        rc="$HOME/.zshrc"
    else
        rc="$HOME/.bashrc"
    fi
    if ! grep -qF "$bin_dir" "$rc" 2>/dev/null; then
        {
            echo ""
            echo "export PATH=\"${bin_dir}:\$PATH\""
        } >>"$rc"
        echo "→ added ${bin_dir} to PATH in ${rc} (new shells only)"
    fi
    echo "NOTE: this shell still lacks ${bin_dir} on PATH — use ${bin_dir}/<name> directly or export it now."
}

install_one() {
    local name="$1" suffix tarball url bin_dir
    suffix="$(asset_suffix)"
    tarball="${name}-${suffix}.tar.gz"
    url="${BASE}/${tarball}"
    bin_dir="$(pick_bin_dir "$name")"

    TMP="$(mktemp -d)"
    echo "→ downloading ${url}"
    curl -fsSL "$url" -o "$TMP/$tarball" ||
        die "download failed — asset $tarball may not exist for your platform"

    if curl -fsSL "${BASE}/SHA256SUMS" -o "$TMP/SHA256SUMS" 2>/dev/null; then
        if command -v shasum >/dev/null 2>&1; then
            (cd "$TMP" && grep " ${tarball}$" SHA256SUMS | shasum -a 256 -c - >/dev/null) ||
                die "checksum mismatch for $tarball"
            echo "→ checksum ok"
        elif command -v sha256sum >/dev/null 2>&1; then
            (cd "$TMP" && grep " ${tarball}$" SHA256SUMS | sha256sum -c - >/dev/null) ||
                die "checksum mismatch for $tarball"
            echo "→ checksum ok"
        fi
    fi

    mkdir -p "$DLENS_HOME" "$bin_dir"
    rm -rf "${DLENS_HOME:?}/${name}"
    tar -xzf "$TMP/$tarball" -C "$DLENS_HOME"
    if [ "$(uname -s)" = "Darwin" ]; then
        xattr -dr com.apple.quarantine "${DLENS_HOME}/${name}" 2>/dev/null || true
    fi

    ln -sfn "${DLENS_HOME}/${name}/${name}" "${bin_dir}/${name}"
    echo "→ installed ${bin_dir}/${name} -> ${DLENS_HOME}/${name}/"

    "${bin_dir}/${name}" --help >/dev/null 2>&1 ||
        die "installed binary failed to run: ${bin_dir}/${name}"
    echo "→ verified: ${name} --help"
    rm -rf "$TMP"
    TMP=""
    ensure_path "$bin_dir"
}

# Propagate the agent skill into every detected host skills dir via the
# installed CLI's canonical writer (keeps fingerprint/overwrite discipline).
propagate_skill() {
    [ "${NO_SKILL:-}" = "1" ] && return 0
    local dlens="$1" host skills
    for host in \
        "$HOME/.agents/skills" \
        "$HOME/.claude/skills" \
        "$HOME/.config/devin/skills" \
        "$HOME/.cursor/skills" \
        "$HOME/.codeium/windsurf/skills" \
        "$HOME/.copilot/skills" \
        "$HOME/.kiro/skills" \
        "$HOME/.codebuddy/skills"; do
        # only where the host itself is present
        [ -d "$(dirname "$host")" ] || continue
        if skills="$("$dlens" skill install --dir "$host" 2>&1)"; then
            echo "→ skill installed: ${host}/drawinglens/SKILL.md"
        else
            echo "→ skill skipped for ${host}: ${skills}"
        fi
    done
}

main() {
    need curl
    need tar
    local target="${1:-dlens}"
    case "$target" in
        dlens | drawinglens-mcp) install_one "$target" ;;
        all)
            install_one dlens
            install_one drawinglens-mcp
            ;;
        *) die "usage: install.sh [dlens|drawinglens-mcp|all]" ;;
    esac
    # dlens carries `skill install`; propagate into detected agent homes.
    case "$target" in
        dlens | all) propagate_skill "$(pick_bin_dir dlens)/dlens" ;;
    esac
    echo "Done."
}

main "$@"
