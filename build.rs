fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let vendor_lib = format!("{}/vendor/RNAlib/lib", manifest_dir);

    println!("cargo:rustc-link-search=native={}", vendor_lib);

    // ViennaRNA static library
    println!("cargo:rustc-link-lib=static=RNA");

    // GSL static libraries (gsl depends on gslcblas)
    println!("cargo:rustc-link-lib=static=gsl");
    println!("cargo:rustc-link-lib=static=gslcblas");

    // MPFR static library (depends on gmp)
    println!("cargo:rustc-link-lib=static=mpfr");

    // GMP static library
    println!("cargo:rustc-link-lib=static=gmp");

    // C++ standard library (system, available on all macOS)
    println!("cargo:rustc-link-lib=dylib=c++");

    // System libraries (available on all macOS)
    println!("cargo:rustc-link-lib=dylib=m");
    println!("cargo:rustc-link-lib=dylib=z");
    println!("cargo:rustc-link-lib=dylib=pthread");

    println!("cargo:rerun-if-changed=vendor/RNAlib/lib/libRNA.a");
}
