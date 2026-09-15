#!/usr/bin/env bash

set -euo pipefail

# Configuration
LINE_COUNT="${1:-2000000}"
OUTPUT_FILE="${2:-resources/stress_200k.txt}"
TASK_PATTERN="(A) TEST STRING @test +test due:2026-09-16"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "=== usyuo Stress Test Generator ==="
echo "Target lines : ${LINE_COUNT}"
echo "Output file  : ${OUTPUT_FILE}"
echo "Task string  : ${TASK_PATTERN}"
echo "Generating..."


set +o pipefail
yes "${TASK_PATTERN}" | head -n "${LINE_COUNT}" > "${OUTPUT_FILE}"
set -o pipefail

FILE_SIZE=$(du -h "${OUTPUT_FILE}" | cut -f1)
ACTUAL_LINES=$(wc -l < "${OUTPUT_FILE}")

echo "✔ Successfully generated ${ACTUAL_LINES} lines (${FILE_SIZE}) in ${OUTPUT_FILE}!"
echo ""
echo "To launch interactive stress test:"
echo "  ./build/usyuo ${OUTPUT_FILE}"
echo ""
echo "To run automated performance benchmark:"
echo "  printf 'tag @test\ntoday\nsort date\nexit\n' | ./build/usyuo ${OUTPUT_FILE}"
