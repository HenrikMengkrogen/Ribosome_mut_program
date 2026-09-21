# Ribosomal Mutation Program

A Rust-based RNA sequence design tool built with the ViennaRNA library.

The program uses ViennaRNA folding and minimum-free-energy (MFE) algorithms to generate RNA sequences that match a supplied dot-bracket secondary structure.

> **Note:** The `python/` folder and Python script are legacy files and are not used by the current program.

## Features

The program supports two sequence-generation modes:

1. **Generate from ambiguous nucleotides**  
   Generate sequences from an input sequence containing ambiguous RNA nucleotide symbols such as:

   - `N` — any nucleotide
   - `K` — `G` or `U`
   - `S` — `G` or `C`

2. **Generate from a preferred starting sequence**  
   When `RIBOSOMAL_RNA=True` is enabled in the program configuration, generation begins from the ribosomal large-subunit rRNA sequence.

   The output includes a percentage score indicating how much of the original sequence remains in the generated sequence.

## Supported platforms

Prebuilt static ViennaRNA dependencies are included for:

- macOS on `x86_64` / Intel Macs
- Linux on `x86_64`

The Linux build is tested in GitHub Actions.

Apple Silicon Macs may be able to run the project through Rosetta, but native Apple Silicon support is not currently documented or guaranteed.

## Requirements

### macOS

- Intel Mac (`x86_64`)
- Git
- Approximately 500 MB of free disk space for the Rust toolchain and build files

### Linux

- `x86_64` Linux
- Git
- Rust toolchain
- Clang and `libclang` development files, required by Rust `bindgen`

For Ubuntu or Debian-based Linux distributions:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  clang \
  libclang-dev \
  pkg-config \
  git \
  curl
```

## Quick start: macOS
Clone the repository and run the setup script:
```bash
git clone https://github.com/HenrikMengkrogen/Ribosome_mut_program.git && cd Ribosome_mut_program && bash setup.sh
```
The setup script installs required tools when needed and builds the project.

If Rust was not installed automatically, install it with:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
After installation, restart your terminal or load Rust into the current shell:
```bash
source "$HOME/.cargo/env"
```

## Quick start: Linux
Install the system requirements shown above, then install Rust if necessary:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```
```bash
git clone https://github.com/HenrikMengkrogen/Ribosome_mut_program.git
cd Ribosome_mut_program
cargo run
```

## Running the program
Run this command from the repository root, the directory containing Cargo.toml:
```bash
cargo run
```
For an optimized release build:
```bash
cargo run --release
```

## Input and output files
Input files are located in:
```bash
main/misc/
```
They are named with the input_ prefix.

Each input file must contain:

* An RNA sequence
* A matching RNA secondary structure in dot-bracket notation

For example:
```bash
Sequence: GGGAAACCC
Structure : (((...)))
```
The sequence and structure must have the same length
Generated output files are written to:
```bash
main/misc/output/
```


## Native dependencies
The project uses the following native libraries:

* ViennaRNA — RNA secondary-structure prediction and MFE folding
* GMP — GNU Multiple Precision Arithmetic Library
* MPFR — multiple-precision floating-point arithmetic
* GSL — GNU Scientific Library
* The required static archives are vendored in the repository under:
```bash
vendor/RNAlib/prebuilt/
```
Platform-specific libraries are stored in directories such as:
```bash
vendor/RNAlib/prebuilt/x86_64-unknown-linux-gnu/
```
The Rust build script selects the correct prebuilt library directory for the current target platform.


## Project Structure
```bash
Ribosome_mut_program/
├── Cargo.toml
├── Cargo.lock
├── build.rs
├── setup.sh
├── src/
│   └── main.rs
├── main/
│   └── misc/
│       ├── input_*.txt
│       └── output/
├── vendor/
│   └── RNAlib/
│       ├── include/
│       │   └── ViennaRNA/          # ViennaRNA C headers
│       └── prebuilt/
│           ├── x86_64-apple-darwin/
│           └── x86_64-unknown-linux-gnu/
│               ├── libRNA.a
│               ├── libgmp.a
│               ├── libmpfr.a
│               ├── libgsl.a
│               └── libgslcblas.a
└── .github/
    └── workflows/
        ├── build-linux-viennarna.yml
        └── test-all-platforms.yml

```
