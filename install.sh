#!/usr/bin/env bash
# DrawingLens installer — downloads the native dist from the public releases repo
# (no Python required). Usage:
#   curl -fsSL <raw>/install.sh | bash                     # installs dlens (CLI)
#   curl -fsSL <raw>/install.sh | bash -s drawinglens-mcp  # installs MCP server
#   curl -fsSL <raw>/install.sh | bash -s all              # both
# Env overrides: DLENS_HOME (dist root), BIN_DIR (symlink dir).
set -euo pipefail

REPO="nightby/drawinglens-releases"
BASE="https://github.com/${REPO}/releases/latest/download"
DLENS_HOME="${DLENS_HOME:-$HOME/.local/share/drawinglens}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
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

install_one() {
    local name="$1" suffix tarball url
    suffix="$(asset_suffix)"
    tarball="${name}-${suffix}.tar.gz"
    url="${BASE}/${tarball}"

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

    mkdir -p "$DLENS_HOME" "$BIN_DIR"
    rm -rf "${DLENS_HOME:?}/${name}"
    tar -xzf "$TMP/$tarball" -C "$DLENS_HOME"
    if [ "$(uname -s)" = "Darwin" ]; then
        xattr -dr com.apple.quarantine "${DLENS_HOME}/${name}" 2>/dev/null || true
    fi

    ln -sfn "${DLENS_HOME}/${name}/${name}" "${BIN_DIR}/${name}"
    echo "→ installed ${BIN_DIR}/${name} -> ${DLENS_HOME}/${name}/"

    "${BIN_DIR}/${name}" --help >/dev/null 2>&1 ||
        die "installed binary failed to run: ${BIN_DIR}/${name}"
    echo "→ verified: ${name} --help"
    rm -rf "$TMP"
    TMP=""
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
    case ":$PATH:" in
        *":${BIN_DIR}:"*) ;;
        *)
            echo ""
            echo "NOTE: ${BIN_DIR} is not on PATH. Add it:"
            echo "  export PATH=\"${BIN_DIR}:\$PATH\""
            ;;
    esac
}

main "$@"
