#!/bin/bash

# Test suite for lib.sh

# Source the test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Source the library under test
source "$SCRIPT_DIR/../lib.sh"

echo "Running tests for lib.sh..."
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Test: _gum_set_default sets variable when not set
test_case() {
    local test_name="$1"
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "Test $TEST_COUNT: $test_name... "
}

test_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "✓ PASS"
}

test_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "✗ FAIL: $1"
}

# Test 1: _gum_set_default sets variable when not set
test_case "_gum_set_default sets variable when not set"
unset TEST_VAR
_gum_set_default TEST_VAR "default_value"
if [ "$TEST_VAR" = "default_value" ]; then
    test_pass
else
    test_fail "Expected TEST_VAR to be 'default_value', got '$TEST_VAR'"
fi

# Test 2: _gum_set_default does not override existing variable
test_case "_gum_set_default does not override existing variable"
export TEST_VAR="existing_value"
_gum_set_default TEST_VAR "default_value"
if [ "$TEST_VAR" = "existing_value" ]; then
    test_pass
else
    test_fail "Expected TEST_VAR to remain 'existing_value', got '$TEST_VAR'"
fi

# Test 3: init_gum_logging sets GUM_LOG_LEVEL_FOREGROUND
test_case "init_gum_logging sets GUM_LOG_LEVEL_FOREGROUND"
unset GUM_LOG_LEVEL_FOREGROUND
init_gum_logging
if [ "$GUM_LOG_LEVEL_FOREGROUND" = "212" ]; then
    test_pass
else
    test_fail "Expected GUM_LOG_LEVEL_FOREGROUND to be '212', got '$GUM_LOG_LEVEL_FOREGROUND'"
fi

# Test 4: retry_until succeeds on first attempt
test_case "retry_until succeeds on first attempt"
mock_success_command() {
    return 0
}
if retry_until 3 1 "test" mock_success_command >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected retry_until to succeed"
fi

# Test 5: retry_until fails after max attempts
test_case "retry_until fails after max attempts"
mock_fail_command() {
    return 1
}
if ! retry_until 2 1 "test" mock_fail_command >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected retry_until to fail after max attempts"
fi

# Test 6: retry_until succeeds on retry
test_case "retry_until succeeds on retry"
ATTEMPT_COUNT=0
mock_retry_command() {
    ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
    if [ $ATTEMPT_COUNT -ge 2 ]; then
        return 0
    fi
    return 1
}
if retry_until 3 1 "test" mock_retry_command >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected retry_until to succeed on retry"
fi

# Summary
echo ""
echo "================================"
echo "Test Summary for lib.sh"
echo "================================"
echo "Total tests: $TEST_COUNT"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "================================"

if [ $FAIL_COUNT -eq 0 ]; then
    echo "All tests passed! ✓"
    exit 0
else
    echo "Some tests failed! ✗"
    exit 1
fi
