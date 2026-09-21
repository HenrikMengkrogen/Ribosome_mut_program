#!/usr/bin/env bash
# Ribologic setup - macOS (Intel + Apple Silicon) and Linux (x86_64 + arm64)
# Windows users: run this inside WSL2 (Ubuntu recommended).
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}! $*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

# Version of ViennaRNA to build from source on Linux
VIENNARNA_VERSION="${VIENNARNA_VERSION:-2.6.4}"

# Always work from the directory this script lives in, so vendor/ ends up in the project
cd "$(dirname "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/RNAlib"

echo "Ribologic Setup"
echo "=================="

# ── Detect platform ─────────────────────────────────────────────
OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
        die "Native Windows shells aren't supported. Install WSL2 (https://learn.microsoft.com/windows/wsl/install), open an Ubuntu terminal, and run this script there."
        ;;
    *) die "Unsupported operating system: $OS_RAW" ;;
esac

case "$ARCH_RAW" in
    x86_64|amd64)  ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) die "Unsupported CPU architecture: $ARCH_RAW" ;;
esac

ok "Detected $OS ($ARCH)"

# ── Helpers ─────────────────────────────────────────────────────
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        warn "Not running as root and sudo not found; system package installs may fail."
    fi
fi

have() { command -v "$1" &>/dev/null; }

need_curl() {
    have curl || die "curl is required but not installed. Please install curl and re-run."
}

# ── Install Rust ────────────────────────────────────────────────
if ! have cargo; then
    if [[ -f "$HOME/.cargo/env" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    fi
fi

if ! have cargo; then
    need_curl
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
    ok "Rust installed"
else
    ok "Rust already installed"
fi

# ── Vendored libraries already present? ─────────────────────────
VENDOR_LIBS=(libRNA.a libgsl.a libgslcblas.a libmpfr.a libgmp.a)

vendor_complete() {
    for lib in "${VENDOR_LIBS[@]}"; do
        [[ -f "$VENDOR_DIR/lib/$lib" ]] || return 1
    done
    return 0
}

# ── macOS: install deps with Homebrew and copy static libs ──────
setup_macos() {
    # Locate or install Homebrew
    if ! have brew; then
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [[ -x "$candidate" ]]; then
                eval "$("$candidate" shellenv)"
                break
            fi
        done
    fi

    if ! have brew; then
        need_curl
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Apple Silicon installs to /opt/homebrew, Intel to /usr/local
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    have brew || die "Homebrew installation failed."
    ok "Homebrew ready"

    echo "Installing GSL, MPFR, GMP, ViennaRNA..."
    brew install gsl mpfr gmp viennarna

    echo "Copying static libraries to vendor/..."
    mkdir -p "$VENDOR_DIR/lib" "$VENDOR_DIR/include"

    # Each formula has its own prefix; --prefix <formula> is correct on both Intel and ARM
    copy_brew_lib() {
        local formula="$1" lib="$2"
        local src
        src="$(brew --prefix "$formula")/lib/$lib"
        [[ -f "$src" ]] || die "Could not find $lib at $src"
        cp "$src" "$VENDOR_DIR/lib/"
    }

    copy_brew_lib viennarna libRNA.a
    copy_brew_lib gsl       libgsl.a
    copy_brew_lib gsl       libgslcblas.a
    copy_brew_lib mpfr      libmpfr.a
    copy_brew_lib gmp       libgmp.a

    # Headers
    local rna_inc
    rna_inc="$(brew --prefix viennarna)/include/ViennaRNA"
    if [[ -d "$rna_inc" ]]; then
        cp -R "$rna_inc" "$VENDOR_DIR/include/"
    else
        warn "ViennaRNA headers not found at $rna_inc"
    fi
}

# ── Linux: install deps with the system package manager ─────────
install_linux_packages() {
    if have apt-get; then
        echo "Using apt..."
        $SUDO apt-get update
        $SUDO apt-get install -y build-essential curl pkg-config \
            libgsl-dev libmpfr-dev libgmp-dev
    elif have dnf; then
        echo "Using dnf..."
        $SUDO dnf install -y gcc gcc-c++ make curl pkgconf-pkg-config \
            gsl-devel gsl-static mpfr-devel gmp-devel gmp-static
    elif have yum; then
        echo "Using yum..."
        $SUDO yum install -y gcc gcc-c++ make curl pkgconfig \
            gsl-devel mpfr-devel gmp-devel
    elif have pacman; then
        echo "Using pacman..."
        $SUDO pacman -Sy --needed --noconfirm base-devel curl pkgconf gsl mpfr gmp
    elif have zypper; then
        echo "Using zypper..."
        $SUDO zypper --non-interactive install gcc gcc-c++ make curl pkg-config \
            gsl-devel mpfr-devel gmp-devel
    else
        die "No supported package manager found (apt, dnf, yum, pacman, zypper). Install a C compiler, make, curl, and the GSL/MPFR/GMP development packages manually, then re-run."
    fi
}

# Ask the compiler where a static library lives (handles multiarch paths like
# /usr/lib/x86_64-linux-gnu and /usr/lib/aarch64-linux-gnu automatically)
find_static_lib() {
    local name="$1" path
    path="$(gcc -print-file-name="$name" 2>/dev/null || true)"
    if [[ -n "$path" && -f "$path" ]]; then
        echo "$path"
        return 0
    fi
    # Fallback search
    for dir in /usr/lib64 /usr/lib /usr/local/lib /usr/lib/*-linux-gnu; do
        if [[ -f "$dir/$name" ]]; then
            echo "$dir/$name"
            return 0
        fi
    done
    return 1
}

build_viennarna_from_source() {
    need_curl
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    echo "Building ViennaRNA $VIENNARNA_VERSION from source (this takes a few minutes)..."
    curl -fsSL "https://github.com/ViennaRNA/ViennaRNA/releases/download/v${VIENNARNA_VERSION}/ViennaRNA-${VIENNARNA_VERSION}.tar.gz" \
        -o "$tmp/viennarna.tar.gz"
    tar -xzf "$tmp/viennarna.tar.gz" -C "$tmp"

    pushd "$tmp/ViennaRNA-${VIENNARNA_VERSION}" >/dev/null
    ./configure \
        --prefix="$VENDOR_DIR" \
        --disable-shared --enable-static \
        --with-pic \
        --without-perl --without-python --without-doc \
        --without-kinfold --without-forester --without-rnalocmin \
        --disable-lto --disable-openmp >/dev/null
    make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
    make install >/dev/null
    popd >/dev/null
}

setup_linux() {
    install_linux_packages
    ok "System packages installed"

    mkdir -p "$VENDOR_DIR/lib" "$VENDOR_DIR/include"

    # Distros rarely ship a static libRNA.a, so build it into vendor/RNAlib
    if [[ ! -f "$VENDOR_DIR/lib/libRNA.a" ]]; then
        build_viennarna_from_source
    fi
    [[ -f "$VENDOR_DIR/lib/libRNA.a" ]] || die "ViennaRNA build did not produce libRNA.a"
    ok "ViennaRNA built"

    echo "Copying static libraries to vendor/..."
    for lib in libgsl.a libgslcblas.a libmpfr.a libgmp.a; do
        if src="$(find_static_lib "$lib")"; then
            cp "$src" "$VENDOR_DIR/lib/"
        else
            die "Could not find $lib. On Fedora/RHEL install the *-static packages (e.g. gsl-static, gmp-static); on Arch make sure gsl, mpfr, and gmp are installed."
        fi
    done
}

# ── Main library setup ──────────────────────────────────────────
if vendor_complete; then
    ok "Vendored libraries already present"
else
    echo "Vendored libraries not found — installing dependencies..."
    if [[ "$OS" == "macos" ]]; then
        setup_macos
    else
        setup_linux
    fi

    vendor_complete || die "Some vendored libraries are still missing in $VENDOR_DIR/lib"
    ok "Vendored libraries ready in vendor/RNAlib"
fi

# ── Done ────────────────────────────────────────────────────────
echo ""
ok "Setup complete for $OS ($ARCH)"
echo "If cargo isn't found in a new terminal, run:  source \"\$HOME/.cargo/env\""
