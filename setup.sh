#!/usr/bin/env bash
# Ribologic setup
#
# Supported:
#   - macOS (Intel and Apple Silicon)
#   - Linux (x86_64 and arm64)
#   - Native Windows through MSYS2 MinGW64
#   - WSL2 (treated as Linux)
#
# Native Windows prerequisite:
#   1. Install MSYS2: https://www.msys2.org/
#   2. Open "MSYS2 MinGW x64"
#   3. Clone this repository and run:
#        ./setup.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}! $*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

# ViennaRNA versions.
#
# The Windows MinGW build uses 2.7.0 because this is the version verified
# by the Windows GitHub Actions workflow.
VIENNARNA_VERSION="${VIENNARNA_VERSION:-2.6.4}"
VIENNARNA_WINDOWS_VERSION="${VIENNARNA_WINDOWS_VERSION:-2.7.0}"

# Always run relative to this script, even when invoked from another folder.
cd "$(dirname "${BASH_SOURCE[0]}")"

PROJECT_DIR="$(pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/RNAlib"
NATIVE_VENDOR_LIB_DIR="$VENDOR_DIR/lib"
WINDOWS_TARGET="x86_64-pc-windows-gnu"
WINDOWS_VENDOR_LIB_DIR="$VENDOR_DIR/prebuilt/$WINDOWS_TARGET"

echo "Ribologic Setup"
echo "================"
echo ""

# ── Platform detection ──────────────────────────────────────────

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
    Darwin)
        OS="macos"
        ;;
    Linux)
        OS="linux"
        ;;
    MINGW*|MSYS*)
        OS="windows"
        ;;
    CYGWIN*)
        die "Cygwin is not supported. Install MSYS2 from https://www.msys2.org/ and run this script from the 'MSYS2 MinGW x64' terminal."
        ;;
    *)
        die "Unsupported operating system: $OS_RAW"
        ;;
esac

case "$ARCH_RAW" in
    x86_64|amd64)
        ARCH="x86_64"
        ;;
    arm64|aarch64)
        ARCH="arm64"
        ;;
    *)
        die "Unsupported CPU architecture: $ARCH_RAW"
        ;;
esac

if [[ "$OS" == "windows" && "$ARCH" != "x86_64" ]]; then
    die "Native Windows setup currently supports x86_64 only."
fi

ok "Detected $OS ($ARCH)"

# ── Common helpers ──────────────────────────────────────────────

have() {
    command -v "$1" >/dev/null 2>&1
}

need_curl() {
    have curl || die "curl is required but was not found."
}

cpu_count() {
    if have nproc; then
        nproc
    elif have sysctl; then
        sysctl -n hw.ncpu
    else
        echo 2
    fi
}

SUDO=""
if [[ "$OS" != "windows" && "$(id -u)" -ne 0 ]]; then
    if have sudo; then
        SUDO="sudo"
    else
        warn "sudo was not found. System package installation may fail."
    fi
fi

# ── Rust setup ──────────────────────────────────────────────────

setup_rust() {
    if ! have cargo && [[ -f "$HOME/.cargo/env" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    fi

    if ! have cargo; then
        need_curl

        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

        if [[ -f "$HOME/.cargo/env" ]]; then
            # shellcheck disable=SC1091
            source "$HOME/.cargo/env"
        fi
    fi

    have cargo || die "Rust installation failed; cargo was not found."
    ok "Rust ready: $(cargo --version)"
}

# ── Native macOS/Linux library checks ───────────────────────────

NATIVE_VENDOR_LIBS=(
    libRNA.a
    libgsl.a
    libgslcblas.a
    libmpfr.a
    libgmp.a
)

native_vendor_complete() {
    local lib

    for lib in "${NATIVE_VENDOR_LIBS[@]}"; do
        [[ -f "$NATIVE_VENDOR_LIB_DIR/$lib" ]] || return 1
    done

    return 0
}

# ── Windows MinGW library checks ────────────────────────────────

WINDOWS_VENDOR_LIBS=(
    libRNA.a
    libgsl.a
    libgslcblas.a
    libmpfr.a
    libgmp.a
)

windows_vendor_complete() {
    local lib

    for lib in "${WINDOWS_VENDOR_LIBS[@]}"; do
        [[ -f "$WINDOWS_VENDOR_LIB_DIR/$lib" ]] || return 1
    done

    return 0
}

# ── macOS ───────────────────────────────────────────────────────

copy_brew_lib() {
    local formula="$1"
    local lib="$2"
    local prefix
    local source_file

    prefix="$(brew --prefix "$formula")"
    source_file="$prefix/lib/$lib"

    if [[ ! -f "$source_file" ]]; then
        source_file="$(
            find "$(brew --cellar "$formula")" \
                -name "$lib" \
                -type f \
                -print \
                -quit 2>/dev/null || true
        )"
    fi

    if [[ -n "$source_file" && -f "$source_file" ]]; then
        cp "$source_file" "$NATIVE_VENDOR_LIB_DIR/"
        return 0
    fi

    return 1
}

setup_macos() {
    if ! xcode-select -p >/dev/null 2>&1; then
        echo "Installing Xcode Command Line Tools..."
        xcode-select --install || true
        die "Finish installing Xcode Command Line Tools, then run ./setup.sh again."
    fi

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
        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    have brew || die "Homebrew installation failed."

    echo "Installing macOS dependencies..."
    brew install gsl mpfr gmp viennarna llvm

    mkdir -p "$NATIVE_VENDOR_LIB_DIR" "$VENDOR_DIR/include"

    echo "Copying GSL, MPFR, and GMP static libraries..."

    for pair in \
        "gsl:libgsl.a" \
        "gsl:libgslcblas.a" \
        "mpfr:libmpfr.a" \
        "gmp:libgmp.a"
    do
        local formula="${pair%%:*}"
        local library="${pair##*:}"

        copy_brew_lib "$formula" "$library" ||
            die "Could not find $library in Homebrew formula $formula."
    done

    if copy_brew_lib viennarna libRNA.a; then
        echo "Using Homebrew ViennaRNA static library."

        local rna_include
        rna_include="$(brew --prefix viennarna)/include/ViennaRNA"

        if [[ -d "$rna_include" ]]; then
            cp -R "$rna_include" "$VENDOR_DIR/include/"
        fi
    else
        warn "Homebrew did not provide static libRNA.a; building ViennaRNA from source."
        build_viennarna_native
    fi

    ok "macOS native libraries ready"
}

# ── Linux ───────────────────────────────────────────────────────

install_linux_packages() {
    if have apt-get; then
        echo "Using apt..."
        $SUDO apt-get update
        $SUDO apt-get install -y \
            build-essential \
            curl \
            pkg-config \
            clang \
            libclang-dev \
            libgsl-dev \
            libmpfr-dev \
            libgmp-dev

    elif have dnf; then
        echo "Using dnf..."
        $SUDO dnf install -y \
            gcc \
            gcc-c++ \
            make \
            curl \
            pkgconf-pkg-config \
            clang \
            clang-libs \
            gsl-devel \
            gsl-static \
            mpfr-devel \
            gmp-devel \
            gmp-static

    elif have yum; then
        echo "Using yum..."
        $SUDO yum install -y \
            gcc \
            gcc-c++ \
            make \
            curl \
            pkgconfig \
            clang \
            gsl-devel \
            mpfr-devel \
            gmp-devel

    elif have pacman; then
        echo "Using pacman..."
        $SUDO pacman -Sy --needed --noconfirm \
            base-devel \
            curl \
            pkgconf \
            clang \
            gsl \
            mpfr \
            gmp

    elif have zypper; then
        echo "Using zypper..."
        $SUDO zypper --non-interactive install \
            gcc \
            gcc-c++ \
            make \
            curl \
            pkg-config \
            clang \
            libclang-devel \
            gsl-devel \
            mpfr-devel \
            gmp-devel

    else
        die "No supported Linux package manager found. Install a C compiler, make, curl, libclang, GSL, MPFR, and GMP development packages manually."
    fi
}

find_static_lib() {
    local name="$1"
    local path

    path="$(gcc -print-file-name="$name" 2>/dev/null || true)"

    if [[ -n "$path" && -f "$path" ]]; then
        echo "$path"
        return 0
    fi

    for dir in /usr/lib64 /usr/lib /usr/local/lib /usr/lib/*-linux-gnu; do
        if [[ -f "$dir/$name" ]]; then
            echo "$dir/$name"
            return 0
        fi
    done

    return 1
}

setup_linux() {
    install_linux_packages
    mkdir -p "$NATIVE_VENDOR_LIB_DIR" "$VENDOR_DIR/include"

    if [[ ! -f "$NATIVE_VENDOR_LIB_DIR/libRNA.a" ]]; then
        build_viennarna_native
    fi

    echo "Copying Linux static GSL, MPFR, and GMP libraries..."

    local lib
    local source_file

    for lib in libgsl.a libgslcblas.a libmpfr.a libgmp.a; do
        source_file="$(find_static_lib "$lib")" ||
            die "Could not find $lib. Install the relevant static development package."

        cp "$source_file" "$NATIVE_VENDOR_LIB_DIR/"
    done

    ok "Linux native libraries ready"
}

# ── Build ViennaRNA for macOS/Linux ─────────────────────────────

build_viennarna_native() {
    need_curl

    local temp_dir
    temp_dir="$(mktemp -d)"

    echo "Building ViennaRNA $VIENNARNA_VERSION from source..."

    curl --fail --location \
        --retry 5 \
        --retry-delay 5 \
        -o "$temp_dir/viennarna.tar.gz" \
        "https://github.com/ViennaRNA/ViennaRNA/releases/download/v${VIENNARNA_VERSION}/ViennaRNA-${VIENNARNA_VERSION}.tar.gz"

    tar -xzf "$temp_dir/viennarna.tar.gz" -C "$temp_dir"

    pushd "$temp_dir/ViennaRNA-${VIENNARNA_VERSION}" >/dev/null

    if [[ "$OS" == "macos" ]]; then
        export CFLAGS="${CFLAGS:-} -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion"
    fi

    ./configure \
        --prefix="$VENDOR_DIR" \
        --disable-shared \
        --enable-static \
        --with-pic \
        --without-perl \
        --without-python \
        --without-doc \
        --without-kinfold \
        --without-forester \
        --without-rnalocmin \
        --disable-lto \
        --disable-openmp

    make -j"$(cpu_count)"
    make install

    popd >/dev/null

    rm -rf "$temp_dir"

    [[ -f "$NATIVE_VENDOR_LIB_DIR/libRNA.a" ]] ||
        die "ViennaRNA build did not produce $NATIVE_VENDOR_LIB_DIR/libRNA.a"
}

# ── Native Windows through MSYS2 MinGW64 ────────────────────────

setup_windows() {
    [[ "${MSYSTEM:-}" == "MINGW64" ]] ||
        die "Run this script from the 'MSYS2 MinGW x64' terminal, not PowerShell, CMD, Git Bash, WSL, or the plain MSYS2 terminal."

    export PATH="/mingw64/bin:$PATH"
    export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig"

    echo "Installing MSYS2 MinGW dependencies..."

    pacman -Sy --needed --noconfirm \
        mingw-w64-x86_64-toolchain \
        mingw-w64-x86_64-clang \
        mingw-w64-x86_64-pkgconf \
        mingw-w64-x86_64-gmp \
        mingw-w64-x86_64-mpfr \
        mingw-w64-x86_64-gsl \
        git \
        curl \
        make \
        autoconf \
        automake \
        libtool \
        bison \
        flex

    rustup target add "$WINDOWS_TARGET"

    local temp_dir
    local rna_archive

    temp_dir="$(mktemp -d)"

    echo "Building ViennaRNA $VIENNARNA_WINDOWS_VERSION for Windows MinGW..."

    pushd "$temp_dir" >/dev/null

    curl --fail --location \
        --retry 5 \
        --retry-delay 5 \
        --connect-timeout 30 \
        --max-time 300 \
        -o "ViennaRNA-${VIENNARNA_WINDOWS_VERSION}.tar.gz" \
        "https://github.com/ViennaRNA/ViennaRNA/releases/download/v${VIENNARNA_WINDOWS_VERSION}/ViennaRNA-${VIENNARNA_WINDOWS_VERSION}.tar.gz"

    tar -xf "ViennaRNA-${VIENNARNA_WINDOWS_VERSION}.tar.gz"
    cd "ViennaRNA-${VIENNARNA_WINDOWS_VERSION}"

    export CC=gcc
    export CXX=g++
    export CPPFLAGS="-I$PWD/src -I/mingw64/include"
    export CFLAGS="-std=gnu17 -fno-lto"
    export CXXFLAGS="-std=gnu++17 -fno-lto -include cstdint"
    export LDFLAGS="-fno-lto -L/mingw64/lib -lws2_32 -lwinmm"

    ./configure \
        --prefix="/mingw64" \
        --disable-shared \
        --enable-static \
        --without-openmp \
        --without-swig \
        --without-svm \
        --without-forester

    make -j1

    rna_archive="$(find . -type f -name libRNA.a -print -quit)"

    [[ -n "$rna_archive" ]] ||
        die "ViennaRNA build did not produce libRNA.a."

    mkdir -p "$WINDOWS_VENDOR_LIB_DIR"

    cp "$rna_archive" "$WINDOWS_VENDOR_LIB_DIR/libRNA.a"
    cp /mingw64/lib/libgmp.a "$WINDOWS_VENDOR_LIB_DIR/libgmp.a"
    cp /mingw64/lib/libmpfr.a "$WINDOWS_VENDOR_LIB_DIR/libmpfr.a"
    cp /mingw64/lib/libgsl.a "$WINDOWS_VENDOR_LIB_DIR/libgsl.a"
    cp /mingw64/lib/libgslcblas.a "$WINDOWS_VENDOR_LIB_DIR/libgslcblas.a"

    popd >/dev/null
    rm -rf "$temp_dir"

    windows_vendor_complete ||
        die "Windows libraries were not staged correctly in $WINDOWS_VENDOR_LIB_DIR."

    ok "Windows GNU libraries ready in $WINDOWS_VENDOR_LIB_DIR"
}

# ── Main ────────────────────────────────────────────────────────

setup_rust

case "$OS" in
    macos)
        if native_vendor_complete; then
            ok "macOS vendored libraries already present"
        else
            setup_macos
        fi
        ;;

    linux)
        if native_vendor_complete; then
            ok "Linux vendored libraries already present"
        else
            setup_linux
        fi
        ;;

    windows)
        if windows_vendor_complete; then
            ok "Windows GNU vendored libraries already present"
        else
            setup_windows
        fi
        ;;
esac

echo ""
ok "Setup complete for $OS ($ARCH)"
echo ""

if [[ "$OS" == "windows" ]]; then
    echo "Run the program with:"
    echo "  cargo run --target $WINDOWS_TARGET"
    echo ""
    echo "Run tests with:"
    echo "  cargo test --target $WINDOWS_TARGET"
else
    echo "Run the program with:"
    echo "  cargo run"
    echo ""
    echo "Run tests with:"
    echo "  cargo test"
fi

