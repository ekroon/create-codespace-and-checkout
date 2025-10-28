#!/bin/bash

# Test suite for create-codespace.sh

# Source the test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Source the library and module under test
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../create-codespace.sh"

echo "Running tests for create-codespace.sh..."
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

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

# Test 1: create_codespace returns codespace name on success
test_case "create_codespace returns codespace name on success"
export GH_MOCK_OUTPUT="test-codespace-456"
export GH_MOCK_EXIT_CODE=0
RESULT=$(create_codespace "test/repo" "large" ".devcontainer/devcontainer.json" "" 2>/dev/null | tail -n 1)
if [ "$RESULT" = "test-codespace-456" ]; then
    test_pass
else
    test_fail "Expected 'test-codespace-456', got '$RESULT'"
fi
unset GH_MOCK_OUTPUT
unset GH_MOCK_EXIT_CODE

# Test 2: create_codespace fails with permissions error
test_case "create_codespace fails with permissions error"
export GH_MOCK_OUTPUT="You must authorize or deny additional permissions"
export GH_MOCK_EXIT_CODE=1
if ! create_codespace "test/repo" "large" ".devcontainer/devcontainer.json" "" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected create_codespace to fail"
fi
unset GH_MOCK_OUTPUT
unset GH_MOCK_EXIT_CODE

# Test 3: create_codespace fails with generic error
test_case "create_codespace fails with generic error"
export GH_MOCK_OUTPUT="Some other error"
export GH_MOCK_EXIT_CODE=1
if ! create_codespace "test/repo" "large" ".devcontainer/devcontainer.json" "" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected create_codespace to fail"
fi
unset GH_MOCK_OUTPUT
unset GH_MOCK_EXIT_CODE

# Summary
echo ""
echo "================================"
echo "Test Summary for create-codespace.sh"
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
