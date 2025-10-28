#!/bin/bash

# Test suite for codespace-commands.sh

# Source the test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Source the library and module under test
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../codespace-commands.sh"

echo "Running tests for codespace-commands.sh..."
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

# Test 1: wait_for_codespace_ready succeeds immediately
test_case "wait_for_codespace_ready succeeds immediately"
if wait_for_codespace_ready "test-cs" "test-repo" 3 1 >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected wait_for_codespace_ready to succeed"
fi

# Test 2: fetch_remote succeeds
test_case "fetch_remote succeeds"
if fetch_remote "test-cs" "test-repo" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected fetch_remote to succeed"
fi

# Test 3: upload_terminfo succeeds
test_case "upload_terminfo succeeds"
if upload_terminfo "test-cs" "xterm-ghostty" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected upload_terminfo to succeed"
fi

# Test 4: checkout_branch with existing remote branch
test_case "checkout_branch with existing remote branch"
export GH_MOCK_OUTPUT="refs/heads/main"
if checkout_branch "test-cs" "test-repo" "main" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected checkout_branch to succeed"
fi
unset GH_MOCK_OUTPUT

# Test 5: checkout_branch with new branch
test_case "checkout_branch with new branch"
export GH_MOCK_OUTPUT=""
if checkout_branch "test-cs" "test-repo" "new-branch" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected checkout_branch to succeed with new branch"
fi
unset GH_MOCK_OUTPUT

# Test 6: wait_for_configuration_complete succeeds
test_case "wait_for_configuration_complete succeeds"
export GH_MOCK_LOGS="Finished configuring codespace."
if wait_for_configuration_complete "test-cs" 3 1 >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected wait_for_configuration_complete to succeed"
fi
unset GH_MOCK_LOGS

# Test 7: wait_for_configuration_complete times out gracefully
test_case "wait_for_configuration_complete times out gracefully"
export GH_MOCK_LOGS="Still configuring..."
if ! wait_for_configuration_complete "test-cs" 2 1 >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected wait_for_configuration_complete to timeout"
fi
unset GH_MOCK_LOGS

# Summary
echo ""
echo "================================"
echo "Test Summary for codespace-commands.sh"
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
