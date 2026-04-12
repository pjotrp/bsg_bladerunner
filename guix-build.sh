#!/bin/bash
# BSG Bladerunner build script for Guix
#
# Prerequisites:
#   git clone --recursive https://github.com/bespoke-silicon-group/bsg_bladerunner
#   cd bsg_bladerunner
#   git submodule update --init --recursive
#
# Usage:
#   guix shell gcc-toolchain@12 make autoconf automake libtool curl wget \
#     gmp gawk bison flex texinfo gperf expat dtc cmake python perl git \
#     nss-certs bc -- bash guix-build.sh
#
# Or step by step:
#   bash guix-build.sh verilator
#   bash guix-build.sh riscv
#   bash guix-build.sh examples
set -eu

BLADERUNNER_ROOT="$(cd "$(dirname "$0")" && pwd)"
export BLADERUNNER_ROOT
export BSG_MANYCORE_DIR=$BLADERUNNER_ROOT/bsg_manycore
export BASEJUMP_STL_DIR=$BLADERUNNER_ROOT/basejump_stl
export BSG_F1_DIR=$BLADERUNNER_ROOT/bsg_replicant

STEP="${1:-all}"

build_verilator() {
    echo "=== Building Verilator (v4.228) ==="
    cd $BLADERUNNER_ROOT/verilator
    # Use v4.228 which compiles with gcc 12
    git checkout v4.228 2>/dev/null || true
    make clean 2>/dev/null || true
    rm -rf src/obj_dbg src/obj_opt bin/verilator_bin*
    autoconf
    ./configure --prefix=$(pwd)
    make -j$(nproc)
    echo "  Verilator built: $(bin/verilator --version)"
}

build_riscv() {
    echo "=== Building RISC-V Toolchain ==="
    cd $BSG_MANYCORE_DIR/software/riscv-tools
    # Checkout repos if needed
    if [ ! -d riscv-gnu-toolchain ]; then
        make checkout-repos
    fi
    make install-clean
    echo "  RISC-V toolchain installed"
}

run_examples() {
    echo "=== Running Examples ==="
    export VERILATOR_ROOT=$BLADERUNNER_ROOT/verilator
    export VERILATOR=$VERILATOR_ROOT/bin/verilator
    export BSG_PLATFORM=bigblade-verilator
    export RISCV=$BSG_MANYCORE_DIR/software/riscv-tools/riscv-install
    export PATH=$RISCV/bin:$VERILATOR_ROOT/bin:$PATH

    cd $BSG_F1_DIR/examples
    echo "Available examples:"
    ls -d */
}

case "$STEP" in
    verilator) build_verilator ;;
    riscv) build_riscv ;;
    examples) run_examples ;;
    all)
        build_verilator
        build_riscv
        run_examples
        ;;
    *) echo "Usage: $0 {verilator|riscv|examples|all}" ;;
esac
