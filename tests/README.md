# Tests for create-codespace-and-checkout

This directory contains tests for the refactored create-codespace-and-checkout script.

## Test Structure

The codebase has been refactored into modular components:
- `lib.sh` - Common library functions (logging, retry logic)
- `create-codespace.sh` - Codespace creation logic
- `codespace-commands.sh` - Commands to run in codespaces with retry logic

Each module has corresponding tests:
- `test_lib.sh` - Tests for lib.sh
- `test_create_codespace.sh` - Tests for create-codespace.sh
- `test_codespace_commands.sh` - Tests for codespace-commands.sh

## Running Tests

To run all tests:

```bash
./tests/run_tests.sh
```

To run a specific test suite:

```bash
./tests/test_lib.sh
./tests/test_create_codespace.sh
./tests/test_codespace_commands.sh
```

## Test Helpers

The tests use mocked commands to avoid requiring actual GitHub CLI and other dependencies during testing. Mock implementations are provided in `test_helpers.sh`.

## Test Coverage

The test suite covers:
- Retry logic with various scenarios (immediate success, retry on failure, max attempts)
- Codespace creation with success and error cases
- Branch checkout for both existing and new branches
- Configuration completion waiting with timeout
- Terminal terminfo upload
- Remote git operations

All tests use mocked commands to simulate the actual GitHub CLI and other external dependencies, making them fast and reliable without requiring real codespace creation.
