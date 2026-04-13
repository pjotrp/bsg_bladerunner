# BSG Bladerunner HammerBlade -- Guix Build

This file documents the three Guix packages defined in `guix.scm` that
together build and run a HammerBlade manycore simulation from source.

## Overview

The HammerBlade is a 128-core RISC-V manycore processor designed at the
University of Washington.  Simulating it requires three components:

1. **Verilator 4.228** -- translates the SystemVerilog RTL into C++
2. **RISC-V cross-compiler** -- GCC 9.2 targeting rv32imaf bare-metal
3. **Simulation harness** -- verilated model + host driver + RISC-V kernel

## Prerequisites

```
git clone --recursive https://github.com/bespoke-silicon-group/bsg_bladerunner
cd bsg_bladerunner
```

## Package 1: verilator-4

Verilator converts Verilog/SystemVerilog into cycle-accurate C++ models.
BSG Bladerunner requires v4.x (v5.x changed the API).

**Build:** `guix build -f guix.scm`  (when last line is `verilator-4`)

Steps:

1. Fetch verilator v4.228 source from GitHub.
2. Run `autoconf` (replaces the usual `autoreconf`/bootstrap).
3. Patch `/bin/echo` references to plain `echo`.
4. `./configure && make` -- standard GNU build.
5. Tests are skipped (they require a full test suite checkout).

Output: `bin/verilator`, `share/verilator/include/` (runtime headers).

## Package 2: bsg-riscv-toolchain

A bare-metal RISC-V cross-compiler for the HammerBlade manycore tiles.
The tiles run rv32imaf (32-bit, integer, multiply, atomics, single-float)
with a custom ABI (`riscv32-unknown-elf-dramfs`).

**Build:** change last line of `guix.scm` to `bsg-riscv-toolchain`, then
`guix build -f guix.scm`

### Source filtering

The source is the `riscv-gnu-toolchain` submodule inside `bsg_manycore/`.
It contains GCC 9.2, binutils 2.32, newlib, and support libraries.
The following are excluded to reduce size (~6 GB savings):

- `qemu`, `riscv-gdb`, `riscv-glibc`, `riscv-dejagnu` -- not needed
  for bare-metal
- `.git/`, `build-*`, `stamps/`, `riscv-install` -- build artifacts

### Configure phase

This is the most delicate part.  Three problems must be solved:

1. **glibc header leakage.**  Guix's `gcc-toolchain` puts glibc headers
   in `C_INCLUDE_PATH`.  When building a *bare-metal* cross-compiler,
   these headers leak into the cross-compiler's `cc1` search path.
   Newlib then picks up glibc's `limits.h` which uses `__GLIBC_USE()`,
   a macro that GCC 9.2 does not understand.

   Fix: override `C_INCLUDE_PATH` to contain *only*
   `linux-libre-headers/include` (needed for kernel types) and
   `zlib/include` (needed for LTO compression).  Unset `CPATH`.

2. **fixincludes copies host headers.**  GCC's fixincludes mechanism
   scans `/usr/include` (or equivalent) and copies "broken" headers
   into the cross-compiler.  In Guix, this copies glibc headers.

   Fix: replace `mkfixinc.sh` with a no-op script that creates an
   empty `fixinc.sh`.

3. **Missing limits.h.**  With fixincludes disabled, the cross-compiler
   lacks `include-fixed/limits.h`.  Newlib needs `CHAR_BIT`, `INT_MAX`,
   etc.

   Fix: create a minimal `limits.h` that defines these constants
   using GCC builtins (`__CHAR_BIT__`, `__INT_MAX__`, etc.).

After these fixes, configure runs with:
```
--disable-linux --with-arch=rv32imaf --with-abi=ilp32f
--disable-gdb --with-tune=bsg_vanilla_2020 --without-headers
```

### Build phase

The build has four stages:

**Stage 1: Binutils + GCC stage1**

```
make stamps/build-binutils-newlib    # assembler, linker, objdump, etc.
make stamps/build-gcc-newlib-stage1  # minimal GCC (no libc yet)
```

GCC's build checks that `tm.texi` (target machine documentation) is
up-to-date by comparing timestamps.  Guix's shebang patching changes
file timestamps, causing this check to fail.  The fix is to touch the
`s-tm-texi` stamp file so the check sees it as current.  If it still
fails, we touch all `s-tm-texi` files and retry.

**Stage 2: Install GCC headers**

The normal `make install` for GCC fails (tm.texi again), so we manually
copy GCC's internal headers (`stddef.h`, `stdarg.h`, `stdbool.h`, etc.)
from `build-gcc-newlib-stage1/gcc/include/` to the output prefix.
We also install our minimal `limits.h` into `include-fixed/`.

**Stage 3: Newlib + newlib-nano**

```
make stamps/build-newlib       # full newlib (libc.a, libm.a)
make stamps/build-newlib-nano  # size-optimized variant
make stamps/merge-newlib-nano  # install nano as libc_nano.a alongside libc.a
```

Newlib is a C library for embedded/bare-metal targets.  It provides
`printf`, `malloc`, `memcpy`, etc.  The nano variant trades features
for smaller code size.

**Stage 4: libgcc**

```
make stamps/build-gcc-newlib-stage2  # full GCC with libgcc
```

Stage2 rebuilds GCC now that newlib is available, producing `libgcc.a`
(compiler runtime: soft-float routines, integer division, etc.).
This is copied to the output prefix.

### Output

```
bin/riscv32-unknown-elf-dramfs-gcc   # cross-compiler
bin/riscv32-unknown-elf-dramfs-as    # assembler
bin/riscv32-unknown-elf-dramfs-ld    # linker
lib/gcc/.../9.2.0/libgcc.a          # compiler runtime
riscv32-unknown-elf-dramfs/lib/libc.a   # newlib
riscv32-unknown-elf-dramfs/lib/libm.a   # math library
```

### Shebang doubling bug

An earlier version replaced `/bin/sh` globally in all Makefiles.
Generated Makefiles (in `build-*/`) already contained correct Guix
store paths like `/gnu/store/.../bash/bin/bash`.  The substitute matched
`/bin/bash` as a *substring* of the store path, producing
`.../bash/.../bash/bin/bash` -- a doubled, nonexistent path.

Fix: only patch Makefiles in the source tree (skip `build-*` dirs),
and use anchored patterns (`^SHELL =`) instead of bare `/bin/sh`.

## Package 3: hammerblade-hello

Builds and runs the HammerBlade "hello world" simulation end-to-end.
This is the most complex package -- it verilates the full 128-core
manycore RTL and runs a RISC-V program on it.

**Build:** change last line of `guix.scm` to `hammerblade-hello`, then
`guix build -f guix.scm`

### Source filtering

The source is the entire `bsg_bladerunner` checkout (~13 GB), filtered
down to ~500 MB by excluding:

- `.git/` -- git history
- `riscv-tools/` -- 6.8 GB (packaged separately as bsg-riscv-toolchain)
- `machines/*/bigblade-verilator/` -- 1.7 GB pre-built simulation models
- `debug/`, `syn/`, `ci/` -- unused for this build
- `verilator/src/`, `verilator/test/` -- verilator source (packaged separately)
- Pre-built SPMD artifacts (`.o`, `.riscv`, `.so`, `.log`)

### Build phase

The build phase does the following:

**1. Create verilator directory layout**

Verilator installs `bin/` and `share/verilator/include/` in separate
locations.  BSG expects `VERILATOR_ROOT/bin/` and
`VERILATOR_ROOT/include/` side by side.  We create a unified directory
with symlinks to both.

**2. Initialize git repositories**

The BSG Makefiles call `git rev-parse --show-toplevel` to find the
repository root.  The submodules have `.git` files (gitdir references)
that point to the parent `.git/modules/` which was filtered out.
We delete these broken `.git` files and run `git init` +
`git commit --allow-empty` in each submodule so `git rev-parse` works.

**3. Set environment variables**

The BSG build system expects these variables:

- `BLADERUNNER_ROOT` -- top of the checkout
- `BSG_MANYCORE_DIR` -- path to bsg_manycore (RTL + software)
- `BASEJUMP_STL_DIR` -- path to BaseJump STL (IP library)
- `BSG_F1_DIR` -- path to bsg_replicant (simulation harness)
- `VERILATOR_ROOT`, `VERILATOR` -- verilator binary and headers
- `RISCV` -- cross-compiler prefix

**4. Patch Makefiles**

- `hardware.mk`: change `VERILATOR_ROOT =` to `VERILATOR_ROOT ?=`
  so the environment variable takes effect.
- `link.mk`: add `-DVL_THREADED` to the verilator compile defines.
  Without this, `verilated_threads.h` is included but `VL_THREADED`
  is not defined, causing `VL_LOCK_SPINS` and `VL_CPU_RELAX` to be
  undeclared.

**5. Symlink RISC-V toolchain**

The kernel Makefile hardcodes the path
`bsg_manycore/software/riscv-tools/riscv-install/bin/`.
We create a symlink from this path to the Guix-packaged toolchain.

**6. Run `make exec.log`**

This single make target triggers the entire build chain:

```
make exec.log
  |
  +-- main.so (host driver)
  |     +-- loader.c -> loader.o -> main.so (shared library)
  |     Compiles the host-side test harness that loads the RISC-V
  |     binary into simulated DRAM and manages the simulation.
  |
  +-- main.riscv (RISC-V kernel)
  |     +-- main.c -> main.o (cross-compiled with rv32imaf GCC)
  |     +-- bsg_manycore_lib.a (BSG runtime: printf, tile config)
  |     +-- crt.o (C runtime startup)
  |     +-- bsg_link.ld (linker script, generated by Python)
  |     Links into a bare-metal ELF binary for the manycore tiles.
  |
  +-- simsc (simulation binary, ~67 MB)
  |     +-- Verilator runs on SystemVerilog RTL
  |     |   Input: ~100 .sv files from bsg_manycore + basejump_stl
  |     |   Output: ~600 C++ files in exec/ directory
  |     +-- g++ compiles all generated C++ files (-O2 -march=native)
  |     +-- ar creates Vreplicant_tb_top__ALL.a (~1.5 GB static library)
  |     +-- Compiles bsg_manycore_simulator.cpp (DPI interface)
  |     +-- Compiles verilated.cpp, verilated_threads.cpp (runtime)
  |     +-- Links everything into simsc with shared libraries:
  |           libbsg_manycore_runtime.so, libdramsim3.so, etc.
  |
  +-- Run simulation:
        simsc main.so main.riscv hello 1 1
        |
        Output captured to exec.log:
          - Machine configuration (128 cores, HBM DRAM, 1.5 GHz)
          - Kernel loading into simulated DRAM
          - "Hello from core 15, 7" (corner tile prints)
          - DRAM values verification
          - Finish packet from simulation
```

The verilated model compilation is the bottleneck -- compiling ~600
C++ files sequentially takes 60+ minutes.

### Install phase

Copies `exec.log` to `$out/share/hammerblade/hello-exec.log`.

## Quick reference

```bash
# Build verilator 4.228
guix build -f guix.scm   # (with last line = verilator-4)

# Build RISC-V cross-compiler
# (edit last line to bsg-riscv-toolchain)
guix build -f guix.scm

# Build and run hello world simulation
# (edit last line to hammerblade-hello)
guix build -f guix.scm

# Alternative: use guix-run.sh for interactive use
bash guix-run.sh toolchain   # build cross-compiler via guix shell
bash guix-run.sh hello       # run hello example
```

## Architecture

```
bsg_bladerunner/
  |-- guix.scm              # Package definitions (this file)
  |-- guix-run.sh            # Interactive runner (guix shell wrapper)
  |-- project.mk             # Top-level Makefile variables
  |-- basejump_stl/          # BaseJump STL IP library (FIFOs, muxes, etc.)
  |-- bsg_manycore/
  |     |-- v/               # Manycore RTL (SystemVerilog)
  |     |-- software/
  |     |     |-- spmd/hello/ # Hello world kernel (main.c)
  |     |     |-- bsg_manycore_lib/ # BSG runtime library
  |     |     |-- mk/        # Build system for RISC-V kernels
  |     |     +-- riscv-tools/ # Cross-compiler source (6.8 GB)
  |     +-- imports/          # DRAMSim3, other dependencies
  +-- bsg_replicant/
        |-- libraries/
        |     +-- platforms/bigblade-verilator/  # Verilator platform
        |-- machines/
        |     +-- pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel/
        |           # 1x1 pod, 16x8 tiles, Ruche network, HBM DRAM
        +-- examples/spmd/hello/  # Host-side test harness
```
