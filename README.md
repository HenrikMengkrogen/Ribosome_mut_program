# Ribosomal Mutation Program

RNA design tool using ViennaRNA's folding and MFE algorithms to generate RNA sequences.

It has two functions -> Generate from undefined nucleotides 'N's, 'K's and 'S's. And generate from a preferred start sequence, in this case the Ribosomal large subunit rRNA sequence when RIBOSMAL_RNA=True. This also outputs a percentage score of how much of the original sequence remains. 

NB! The python folder and script is not in use!

## Quick Start (macOS x86_64)

```bash
git clone https://github.com/HenrikMengkrogen/Ribosome_mut_program.git && cd Ribosome_mut_program && bash setup.sh
```

```bash
curl https://sh.rustup.rs -sSf | sh
```



That's it. The setup script will:
1. Install Rust (if needed)
2. Install Homebrew + dependencies (if vendored libraries aren't included)
3. Build and run the project

## Requirements

- **macOS** on **x86_64** (Intel Mac)
- ~500MB free disk space (for Rust toolchain + dependencies)

## How it works

All dependencies (ViennaRNA, GSL, MPFR, GMP) are **statically linked** into the binary. The final executable has no external library dependencies — only macOS system libraries:

```
/usr/lib/libc++.1.dylib
/usr/lib/libSystem.B.dylib
/usr/lib/libz.1.dylib
/usr/lib/libiconv.2.dylib
```

This means the compiled binary can be copied to any x86_64 Mac and run without installing anything.
## How to use
Go to ./main/src and then type
```bash
cargo run
```
Input files are found in ./main/misc and are labeled input_*. It is important that the file always contains sequence and structure as dot-bracket format. Once the sequence generation is complete the output file will be written out in ./main/misc/output/

## Project structure

```
Ribosomal_mut_program/
├── Cargo.toml
├── build.rs              # Links static libraries
├── setup.sh              # One-command setup
├── .cargo/config.toml    # Environment variables for build
├── src/
│   └── main.rs
└── vendor/RNAlib/        # Bundled static libraries + headers
    ├── lib/
    │   ├── libRNA.a       # ViennaRNA
    │   ├── libgsl.a       # GNU Scientific Library
    │   ├── libgslcblas.a
    │   ├── libmpfr.a      # Multi-precision float
    │   ├── libgmp.a       # GNU multi-precision
    │   ├── libstdc++.a    # Stub (C++ provided by libc++)
    │   └── libgomp.a      # Stub (OpenMP not used)
    └── include/ViennaRNA/ # C headers for bindgen
```
