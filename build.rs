use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(
        env::var("CARGO_MANIFEST_DIR")
            .expect("CARGO_MANIFEST_DIR is not set"),
    );

    let prefix = manifest_dir.join("vendor").join("RNAlib");
    let include_dir = prefix.join("include");
    let lib_dir = prefix.join("lib");

    if !include_dir.join("ViennaRNA").exists() {
        panic!(
            "ViennaRNA headers are missing. Expected: {}",
            include_dir.join("ViennaRNA").display()
        );
    }

    if !lib_dir.join("libRNA.a").exists() {
        panic!(
            "Vendored ViennaRNA static library is missing. Expected: {}",
            lib_dir.join("libRNA.a").display()
        );
    }

    println!("cargo:rerun-if-changed={}", include_dir.display());
    println!("cargo:rerun-if-changed={}", lib_dir.display());

    println!("cargo:rustc-link-search=native={}", lib_dir.display());

    println!("cargo:rustc-link-lib=static=RNA");
    println!("cargo:rustc-link-lib=static=gsl");
    println!("cargo:rustc-link-lib=static=gslcblas");
    println!("cargo:rustc-link-lib=static=mpfr");
    println!("cargo:rustc-link-lib=static=gmp");

    let target_os = env::var("CARGO_CFG_TARGET_OS")
        .expect("CARGO_CFG_TARGET_OS is not set");

    match target_os.as_str() {
        "linux" => {
            println!("cargo:rustc-link-lib=m");
            println!("cargo:rustc-link-lib=pthread");
            println!("cargo:rustc-link-lib=dl");
            println!("cargo:rustc-link-lib=z");
        }
        "macos" => {
            println!("cargo:rustc-link-lib=framework=CoreFoundation");
            println!("cargo:rustc-link-lib=iconv");
            println!("cargo:rustc-link-lib=z");
        }
        other => panic!("Unsupported target OS: {other}"),
    }
}

