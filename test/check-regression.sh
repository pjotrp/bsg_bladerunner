#!/bin/sh
# Regression test for HammerBlade SPMD examples.
# Checks binary hashes and cycle counts against baselines.
# Usage: check-regression.sh <manycore-dir> <replicant-dir>
#
# Baselines: cycle counts from riscv32-elf-gcc-bsg (GCC 14.3)
# with -mtune=bsg_vanilla_2020 -fno-inline-functions
set -eu

MANYCORE="$1"
REPLICANT="$2"
THRESHOLD="120"  # fail if >20% slower (cycles as percentage of baseline)

# name:baseline_cycles
BASELINES="hello:4033962
bsg_scalar_print:747918
fib:866466
mul_div:966366"

echo ""
echo "========================================"
echo "REGRESSION TEST: binary hash + cycles"
echo "========================================"
printf "%-20s  %-16s  %-10s  %-10s  %s\n" "example" "sha256[0:16]" "cycles" "baseline" "ratio"

FAIL=0
for entry in $BASELINES; do
    name="${entry%%:*}"
    base="${entry#*:}"

    riscv="$MANYCORE/software/spmd/$name/main.riscv"
    log="$REPLICANT/examples/spmd/$name/exec.log"

    # Hash
    if [ -f "$riscv" ]; then
        hash=$(sha256sum "$riscv" | cut -c1-16)
    else
        hash="missing"
    fi

    # Cycle count (first Unfreezing tile timestamp)
    cycles=""
    if [ -f "$log" ]; then
        cycles=$(grep -oE 'Unfreezing tile t=[0-9]+' "$log" \
                 | head -1 | grep -oE '[0-9]+$' || true)
    fi

    if [ -z "$cycles" ]; then
        printf "%-20s  %-16s  %-10s  %-10s  %s\n" \
            "$name" "$hash" "?" "$base" "(MISSING!)"
        FAIL=1
    else
        ratio=$(echo "scale=3; $cycles * 100 / $base" | bc)
        ratio_fmt=$(echo "scale=3; $cycles / $base" | bc)
        printf "%-20s  %-16s  %-10s  %-10s  %s\n" \
            "$name" "$hash" "$cycles" "$base" "$ratio_fmt"
        if [ "$(echo "$ratio > $THRESHOLD" | bc)" = "1" ]; then
            echo "  FAIL: $name is >20% slower than baseline"
            FAIL=1
        fi
    fi
done

echo "========================================"

if [ "$FAIL" -ne 0 ]; then
    echo "REGRESSION FAILED"
    exit 1
fi
echo "REGRESSION PASSED"
