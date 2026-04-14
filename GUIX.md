# BSG Bladerunner HammerBlade -- Guix Build

This file documents the four Guix packages defined in `guix.scm` that
together build and run a HammerBlade manycore simulation from source.

## Overview

The HammerBlade is a 128-core RISC-V manycore processor designed at the
University of Washington.  Simulating it requires four components:

1. **Verilator 4.228** -- translates the SystemVerilog RTL into C++
2. **BSG Manycore** -- RTL, software libraries, and build infrastructure
3. **RISC-V cross-compiler** -- GCC 9.2 targeting rv32imaf bare-metal
4. **Simulation harness** -- verilated model + host driver + RISC-V kernel

## Prerequisites

No local checkout is needed.  All sources are fetched directly from
GitHub by Guix using `git-fetch`.

## Guix packages used from upstream

The following tools come from Guix rather than being built from source:

- **gcc-toolchain-12** -- host C/C++ compiler (builds verilated model, host driver)
- **gcc-toolchain-11** -- host compiler for building the RISC-V cross-compiler
- **gmp, mpfr, mpc, isl** -- GCC build prerequisites (used as system libraries)
- **perl, python** -- used by verilator and the BSG build system
- **autoconf, automake, bison, flex** -- GNU build tools for verilator and GCC
- **linux-libre-headers** -- kernel headers (needed by the cross-compiler configure)
- **zlib** -- compression library (LTO support in GCC, also linked into simsc)
- **git** -- the BSG Makefiles call `git rev-parse` to locate repository roots
- **bc** -- used by BSG machine config Makefiles for arithmetic
- **coreutils, which** -- standard Unix tools used during the build

## Packages defined in guix.scm

These are built as Guix packages in `guix.scm` because they are not
in upstream Guix or require BSG-specific versions:

- **verilator-4** -- Verilator 4.228; upstream Guix has v5.x but BSG requires v4.x (API change)
- **bsg-manycore** -- BSG Manycore source tree (RTL, software, build system) fetched from GitHub
- **bsg-riscv-toolchain** -- GCC 9.2 + binutils 2.32 + newlib + libgcc cross-compiler for `riscv32-unknown-elf-dramfs` with BSG-specific tuning (`-mtune=bsg_vanilla_2020`)
- **hammerblade-hello** -- verilates the RTL, cross-compiles the kernel, builds the simulation, and runs it

### Components built from source inside hammerblade-hello

These are compiled during the `hammerblade-hello` build from the
BSG source tree (not separate Guix packages):

- **DRAMSim3** -- DRAM simulator library, built from `basejump_stl/imports/DRAMSim3/`
- **BSG platform libraries** -- `libbsg_manycore_runtime.so`, `libbsg_manycore_regression.so`, `libdramsim3.so`, etc.
- **Verilated RTL model** -- the 128-core manycore SystemVerilog translated to ~600 C++ files by Verilator, compiled into `Vreplicant_tb_top__ALL.a` (~1.5 GB)
- **Host driver** -- `loader.c` compiled into `main.so`
- **RISC-V kernel** -- `main.c` cross-compiled into `main.riscv` using bsg-riscv-toolchain

## Package 1: verilator-4

Verilator converts Verilog/SystemVerilog into cycle-accurate C++ models.
BSG Bladerunner requires v4.x (v5.x changed the API).

**Build:** `guix build -f guix.scm`  (when last line is `verilator-4`)

**Source:** https://github.com/verilator/verilator (tag v4.228)

Steps:

1. Fetch verilator v4.228 source from GitHub.
2. Run `autoconf` (replaces the usual `autoreconf`/bootstrap).
3. Patch `/bin/echo` references to plain `echo`.
4. `./configure && make` -- standard GNU build.
5. Tests are skipped (they require a full test suite checkout).

Output: `bin/verilator`, `share/verilator/include/` (runtime headers).

## Package 2: bsg-manycore

BSG Manycore source tree containing SystemVerilog RTL, software
libraries, and build infrastructure for the HammerBlade manycore.

**Build:** change last line of `guix.scm` to `bsg-manycore`, then
`guix build -f guix.scm`

**Source:** https://github.com/bespoke-silicon-group/bsg_manycore
(commit bfe582b2, fetched with `recursive? #t` to include the
HardFloat submodule needed for RTL simulation)

This is a source-only package using `copy-build-system`.  It installs
the following directories to `share/bsg-manycore/`:

- `v/` -- Manycore RTL (SystemVerilog)
- `software/` -- SPMD examples, bsg_manycore_lib, mk build system
  (riscv-tools excluded -- packaged separately as bsg-riscv-toolchain)
- `imports/` -- HardFloat and other dependencies
- `machines/` -- machine configurations
- `testbenches/` -- testbench files
- `Makefile` -- top-level Makefile

The `riscv-tools/` directory under `software/` is excluded from the
install plan since the toolchain is packaged separately.

## Package 3: bsg-riscv-toolchain

A bare-metal RISC-V cross-compiler for the HammerBlade manycore tiles.
The tiles run rv32imaf (32-bit, integer, multiply, atomics, single-float)
with a custom ABI (`riscv32-unknown-elf-dramfs`).

**Build:** change last line of `guix.scm` to `bsg-riscv-toolchain`, then
`guix build -f guix.scm`

### Source

The top-level source is fetched from GitHub:
https://github.com/bespoke-silicon-group/riscv-gnu-toolchain
(commit 6567088)

Three submodules are fetched as separate `origin` definitions and
copied into the source tree during the `populate-submodules` phase:

- **riscv-binutils** (commit d91cadb4) from https://github.com/riscv/riscv-binutils-gdb
- **riscv-gcc** (commit 894ea43d) from https://github.com/bespoke-silicon-group/riscv-gcc
- **riscv-newlib** (commit fa35f8c5) from https://github.com/bespoke-silicon-group/bsg_newlib_dramfs

The remaining submodules (qemu, riscv-gdb, riscv-glibc, riscv-dejagnu)
are not needed for a bare-metal cross-compiler and are not fetched.
This avoids downloading several GB of unnecessary source code.

### Configure phase

This is the most delicate part.  Three problems must be solved:

1. **glibc header leakage.**  Guix's `gcc-toolchain` puts glibc headers
   in `C_INCLUDE_PATH`.  When building a *bare-metal* cross-compiler,
   these headers leak into the cross-compiler's `cc1` search path.
   Newlib then picks up glibc's `limits.h` which uses `__GLIBC_USE()`,
   a macro that GCC 9.2 does not understand.

   Fix: override `C_INCLUDE_PATH` to contain *only*
   `linux-libre-headers/include`, `zlib/include`, and the GCC
   prerequisite libraries (`gmp`, `mpfr`, `mpc`, `isl`).
   Set `LIBRARY_PATH` similarly.  Unset `CPATH`.

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

## Package 4: hammerblade-hello

Builds and runs the HammerBlade "hello world" simulation end-to-end.
This is the most complex package -- it verilates the full 128-core
manycore RTL and runs a RISC-V program on it.

**Build:** change last line of `guix.scm` to `hammerblade-hello`, then
`guix build -f guix.scm`

### Source

The top-level source is fetched from GitHub:
https://github.com/bespoke-silicon-group/bsg_bladerunner
(commit 8100e97, tag v8.3.2)

A snippet removes submodule stubs that are packaged separately
(`bsg_manycore`, `aws-fpga`, `verilator`).

Two submodules are fetched as separate `origin` definitions and
copied into the source tree during the `populate-submodules` phase:

- **bsg_replicant** (commit 83e2441b) from https://github.com/bespoke-silicon-group/bsg_replicant
- **basejump_stl** (commit 5c66f9de, recursive for DRAMSim3) from https://github.com/bespoke-silicon-group/basejump_stl

The package also uses `bsg-manycore` and `bsg-riscv-toolchain` as
native-inputs.

### Build phase

The build phase does the following:

**1. Copy bsg_manycore from package**

The bsg-manycore package contents are copied from the Guix store into
the build tree at `bsg_manycore/`.  A copy (not symlink) is needed
because the build writes artifacts into this directory.

**2. Create verilator directory layout**

Verilator installs `bin/` and `share/verilator/include/` in separate
locations.  BSG expects `VERILATOR_ROOT/bin/` and
`VERILATOR_ROOT/include/` side by side.  We create a unified directory
with symlinks to both.

**3. Initialize git repositories**

The BSG Makefiles call `git rev-parse --show-toplevel` to find the
repository root.  We run `git init` + `git commit --allow-empty` in
each component directory so `git rev-parse` works.

**4. Set environment variables**

The BSG build system expects these variables:

- `BLADERUNNER_ROOT` -- top of the checkout
- `BSG_MANYCORE_DIR` -- path to bsg_manycore (RTL + software)
- `BASEJUMP_STL_DIR` -- path to BaseJump STL (IP library)
- `BSG_F1_DIR` -- path to bsg_replicant (simulation harness)
- `VERILATOR_ROOT`, `VERILATOR` -- verilator binary and headers
- `RISCV` -- cross-compiler prefix

**5. Patch Makefiles**

- `hardware.mk`: change `VERILATOR_ROOT =` to `VERILATOR_ROOT ?=`
  so the environment variable takes effect.
- `link.mk`: add `-DVL_THREADED` to the verilator compile defines
  and to the simulator object CXXFLAGS.  Without this,
  `verilated_threads.h` is included but `VL_THREADED` is not defined,
  causing `VL_LOCK_SPINS` and `VL_CPU_RELAX` to be undeclared.

**6. Symlink RISC-V toolchain**

The kernel Makefile hardcodes the path
`bsg_manycore/software/riscv-tools/riscv-install/bin/`.
We create a symlink from this path to the Guix-packaged toolchain.

**7. Run `make exec.log`**

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
          - "Hello from core 0, 0 in group origin=(0,0)."
          - DRAM values verification
          - "Received finish packet from ( 16,  8)"
```

The verilated model compilation is the bottleneck -- compiling ~600
C++ files sequentially takes ~78 minutes.

### Pre-built shared library cleanup

The source tree contains pre-built `.so` files (e.g. `libdramsim3.so`,
`libbsg_manycore_runtime.so`) that have hardcoded source paths baked
in at compile time.  For example, `libdramsim3.so` uses a compile-time
`-DBASEJUMP_STL_DIR="..."` to locate DRAMSim3 config files.  If these
pre-built libraries are kept, they reference paths from the original
checkout (e.g. `/fast/pjotr/.../basejump_stl/imports/DRAMSim3/configs/`)
which don't exist in the build sandbox.

Fix: delete all `.so` files from `bsg_replicant/` before building,
forcing the make system to rebuild them with correct sandbox paths.

### Install phase

Copies `exec.log` to `$out/share/hammerblade/hello-exec.log`.

### Verified output

```
Manycore stderr>> Hello!
Manycore>> Hello from core 0, 0 in group origin=(0,0).
BSG INFO: Received finish packet from ( 16,  8)
```

## Quick reference

```bash
# Build verilator 4.228
guix build -f guix.scm   # (with last line = verilator-4)

# Build BSG Manycore source package
# (edit last line to bsg-manycore)
guix build -f guix.scm

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

## Package dependency graph

```
hammerblade-hello          (from GitHub, commit 8100e97)
  |-- verilator-4          (Verilator 4.228, from GitHub)
  |-- bsg-manycore         (RTL + software, from GitHub, recursive)
  |-- bsg-riscv-toolchain  (cross-compiler, from GitHub)
  |     |-- riscv-binutils-source  (binutils 2.32)
  |     |-- riscv-gcc-source       (GCC 9.2)
  |     +-- riscv-newlib-source    (newlib for dramfs)
  |-- bsg-replicant-source (simulation harness, from GitHub)
  +-- basejump-stl-source  (IP library + DRAMSim3, from GitHub, recursive)
```

## Architecture

```
bsg_bladerunner/
  |-- guix.scm              # Package definitions (this file)
  |-- guix-run.sh            # Interactive runner (guix shell wrapper)
  |-- project.mk             # Top-level Makefile variables
  |-- basejump_stl/          # BaseJump STL IP library (FIFOs, muxes, etc.)
  |-- bsg_manycore/          # [separate package: bsg-manycore]
  |     |-- v/               # Manycore RTL (SystemVerilog)
  |     |-- software/
  |     |     |-- spmd/hello/ # Hello world kernel (main.c)
  |     |     |-- bsg_manycore_lib/ # BSG runtime library
  |     |     +-- mk/        # Build system for RISC-V kernels
  |     +-- imports/          # HardFloat, other dependencies
  +-- bsg_replicant/
        |-- libraries/
        |     +-- platforms/bigblade-verilator/  # Verilator platform
        |-- machines/
        |     +-- pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel/
        |           # 1x1 pod, 16x8 tiles, Ruche network, HBM DRAM
        +-- examples/spmd/hello/  # Host-side test harness
```
