#!/bin/bash
# BSG Bladerunner HammerBlade simulation runner for Guix
#
# Prerequisites:
#   1. Clone with submodules:
#      git clone --recursive https://github.com/bespoke-silicon-group/bsg_bladerunner
#
#   2. Build the RISC-V toolchain (one-time, ~30 min):
#      bash guix-run.sh toolchain
#
#   3. Build verilator 4.228 Guix package (one-time):
#      guix build -f guix.scm
#
#   4. Run an example:
#      bash guix-run.sh hello
#
# The toolchain build requires stripping glibc from C_INCLUDE_PATH
# which can't be done inside a Guix package build sandbox.
set -eu

BLADERUNNER_ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$BLADERUNNER_ROOT/bsg_manycore/software/riscv-tools/riscv-install"
TOOLCHAIN_SRC="$BLADERUNNER_ROOT/bsg_manycore/software/riscv-tools/riscv-gnu-toolchain"

# Find verilator-4 in the store
VERILATOR_PKG=$(guix build -f "$BLADERUNNER_ROOT/guix.scm" 2>/dev/null | tail -1)

# Create unified verilator directory (bin/ + include/ from share/verilator/)
VROOT="$BLADERUNNER_ROOT/verilator-guix"
mkdir -p "$VROOT"
ln -sfn "$VERILATOR_PKG/bin" "$VROOT/bin"
ln -sfn "$VERILATOR_PKG/share/verilator/include" "$VROOT/include"

# Patch hardware.mk to allow VERILATOR_ROOT override
sed -i 's/^VERILATOR_ROOT = /VERILATOR_ROOT ?= /' \
  "$BLADERUNNER_ROOT/bsg_replicant/libraries/platforms/bigblade-verilator/hardware.mk" 2>/dev/null || true
sed -i 's/^VERILATOR = /VERILATOR ?= /' \
  "$BLADERUNNER_ROOT/bsg_replicant/libraries/platforms/bigblade-verilator/hardware.mk" 2>/dev/null || true

# Add VL_THREADED if not already present
grep -q 'DVL_THREADED' \
  "$BLADERUNNER_ROOT/bsg_replicant/libraries/platforms/bigblade-verilator/link.mk" 2>/dev/null || \
  sed -i '/VERILATOR_OBJS.*DEFINES.*DVL_PRINTF/s/$/ -DVL_THREADED/' \
    "$BLADERUNNER_ROOT/bsg_replicant/libraries/platforms/bigblade-verilator/link.mk"
grep -q 'SIMOS.*DVL_THREADED' \
  "$BLADERUNNER_ROOT/bsg_replicant/libraries/platforms/bigblade-verilator/link.mk" 2>/dev/null || \
  sed -i '/$(SIMOS): INCLUDES += -I$(VERILATOR_ROOT)\/include$/a $(SIMOS): DEFINES += -DVL_THREADED' \
    "$BLADERUNNER_ROOT/bsg_replicant/libraries/platforms/bigblade-verilator/link.mk"

# Guix shell packages needed for building
GUIX_PKGS="gcc-toolchain@12 make perl python coreutils bc python-wrapper"

setup_env() {
  export BLADERUNNER_ROOT
  export BSG_MANYCORE_DIR="$BLADERUNNER_ROOT/bsg_manycore"
  export BASEJUMP_STL_DIR="$BLADERUNNER_ROOT/basejump_stl"
  export BSG_F1_DIR="$BLADERUNNER_ROOT/bsg_replicant"
  export BSG_PLATFORM=bigblade-verilator
  export VERILATOR_ROOT="$VROOT"
  export VERILATOR="$VROOT/bin/verilator"
  export RISCV="$INSTALL"
  export PATH="$INSTALL/bin:$VROOT/bin:$PATH"
  export CC=gcc
}

build_toolchain() {
  echo "=== Building RISC-V rv32imaf cross-compiler toolchain ==="
  echo "This takes ~30 minutes..."

  # Find linux-libre-headers include path
  LINUX_INC=$(find /gnu/store -maxdepth 2 -name "include" \
    -path "*/linux-libre-headers-6*/include" 2>/dev/null | head -1)
  if [ -z "$LINUX_INC" ]; then
    LINUX_INC=$(guix build linux-libre-headers 2>/dev/null | head -1)/include
  fi

  TOOLCHAIN_PKGS="$GUIX_PKGS autoconf automake bison curl flex \
    gettext-minimal git-minimal gmp libtool linux-libre-headers \
    texinfo wget which zlib"

  guix shell $TOOLCHAIN_PKGS -- bash -c "
    export C_INCLUDE_PATH=$LINUX_INC
    export CPLUS_INCLUDE_PATH=$LINUX_INC
    unset CPATH
    export CONFIG_SHELL=\$(which bash)
    export SHELL=\$(which bash)

    cd $TOOLCHAIN_SRC

    # Clean if needed
    if [ ! -f stamps/build-binutils-newlib ]; then
      rm -rf build-* stamps
      # No-op fixincludes
      cat > riscv-gcc/fixincludes/mkfixinc.sh << 'FIXEOF'
#!/bin/sh
mkdir -p \"\$1\"
printf '#!/bin/sh\nexit 0\n' > \"\$1/fixinc.sh\"
chmod +x \"\$1/fixinc.sh\"
printf '#!/bin/sh\nexit 0\n' > fixinc.sh
chmod +x fixinc.sh
FIXEOF
      chmod +x riscv-gcc/fixincludes/mkfixinc.sh

      \$(which bash) configure --prefix=$INSTALL \
        --disable-linux --with-arch=rv32imaf --with-abi=ilp32f \
        --disable-gdb --with-tune=bsg_vanilla_2020 \
        --without-headers CONFIG_SHELL=\$(which bash)
    fi

    # Fix shebangs
    find . -name Makefile -exec sed -i \"s|/bin/sh|\$(which bash)|g\" {} + 2>/dev/null

    make SHELL=\$(which bash) -j\$(nproc) \
      CFLAGS_FOR_TARGET_EXTRA='-fno-common' stamps/build-newlib
    make SHELL=\$(which bash) -j\$(nproc) \
      CFLAGS_FOR_TARGET_EXTRA='-fno-common' stamps/build-newlib-nano
    make SHELL=\$(which bash) -j\$(nproc) \
      CFLAGS_FOR_TARGET_EXTRA='-fno-common' stamps/merge-newlib-nano

    # Build libgcc
    touch build-gcc-newlib-stage1/gcc/s-tm-texi 2>/dev/null
    touch build-gcc-newlib-stage2/gcc/s-tm-texi 2>/dev/null
    cd build-gcc-newlib-stage2
    make SHELL=\$(which bash) -j\$(nproc) all-target-libgcc
    cp gcc/libgcc.a $INSTALL/lib/gcc/riscv32-unknown-elf-dramfs/9.2.0/

    echo '=== Toolchain build complete ==='
  "

  echo "Installed to: $INSTALL"
  echo "GCC: $($INSTALL/bin/riscv32-unknown-elf-dramfs-gcc --version | head -1)"
}

run_example() {
  local example="$1"
  local machine="$BSG_F1_DIR/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"

  echo "=== Running SPMD example: $example ==="
  guix shell $GUIX_PKGS -- bash -c "
    $(declare -f setup_env)
    setup_env
    cd \$BSG_F1_DIR/examples/spmd/$example
    make BSG_PLATFORM=bigblade-verilator \
      BSG_MACHINE_PATH=$machine \
      exec.log
    echo '=== RESULT ==='
    cat exec.log | tail -20
  "
}

case "${1:-help}" in
  toolchain)
    build_toolchain
    ;;
  hello|factorial|fib|nprimes|coremark)
    setup_env
    run_example "$1"
    ;;
  help)
    echo "Usage: bash guix-run.sh {toolchain|hello|factorial|fib|nprimes|coremark}"
    echo ""
    echo "  toolchain  - Build RISC-V cross-compiler (one-time, ~30 min)"
    echo "  hello      - Run hello world SPMD example"
    echo "  factorial  - Run factorial example"
    echo "  fib        - Run fibonacci example"
    echo "  nprimes    - Run prime number example"
    echo "  coremark   - Run CoreMark benchmark"
    ;;
  *)
    echo "Unknown command: $1"
    echo "Try: bash guix-run.sh help"
    exit 1
    ;;
esac
