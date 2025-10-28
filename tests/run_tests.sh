#!/bin/bash

# Main test runner script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Running all tests for create-codespace-and-checkout"
echo "========================================"
echo ""

# Track overall results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Run each test suite
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    if [ -f "$test_file" ]; then
        TOTAL_SUITES=$((TOTAL_SUITES + 1))
        echo ""
        echo "Running $(basename "$test_file")..."
        echo "----------------------------------------"
        
        if bash "$test_file"; then
            PASSED_SUITES=$((PASSED_SUITES + 1))
        else
            FAILED_SUITES=$((FAILED_SUITES + 1))
        fi
        
        echo ""
    fi
done

# Print overall summary
echo "========================================"
echo "Overall Test Summary"
echo "========================================"
echo "Test suites run: $TOTAL_SUITES"
echo "Suites passed: $PASSED_SUITES"
echo "Suites failed: $FAILED_SUITES"
echo "========================================"

if [ $FAILED_SUITES -eq 0 ]; then
    echo "✓ All test suites passed!"
    exit 0
else
    echo "✗ Some test suites failed!"
    exit 1
fi
