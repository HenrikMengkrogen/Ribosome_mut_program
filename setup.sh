#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Ribologic Setup"
echo "=================="

# ── Check platform ──────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    echo "This setup is for macOS only."
    exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    echo "This setup is for x86_64 macOS only (detected: $ARCH)"
    exit 1
fi
echo -e "${GREEN} macOS x86_64 detected${NC}"

# ── Install Rust ────────────────────────────────────────────────
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo -e "${GREEN} Rust installed${NC}"
else
    echo -e "${GREEN} Rust already installed${NC}"
fi

# ── Check for vendored libraries ─────────────────────────────────
if [[ -f "vendor/RNAlib/lib/libRNA.a" ]]; then
    echo -e "${GREEN} Vendored libraries already present${NC}"
else
    echo "Vendored libraries not found — installing via Homebrew..."

    # Install Homebrew if needed
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    echo -e "${GREEN} Homebrew ready${NC}"

    # Install dependencies
    echo "Installing GSL, MPFR, GMP, ViennaRNA..."
    brew install gsl mpfr gmp viennarna

    # Copy static libraries
    echo "Copying static libraries to vendor/..."
    mkdir -p vendor/RNAlib/lib vendor/RNAlib/include

    PREFIX=$(brew --prefix)
    cp "$PREFIX/lib/libRNA.a"       vendor/RNAlib/lib/
    cp "$PREFIX/lib/libgsl.a"       vendor/RNAlib/lib/
    cp "$PREFIX/lib/libgslcblas.a"  vendor/RNAlib/lib/
    cp "$PREFIX/lib/libmpfr