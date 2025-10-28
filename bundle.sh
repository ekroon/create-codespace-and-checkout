#!/bin/bash

# Bundle script - creates a self-contained executable
# This bundles lib.sh, create-codespace.sh, codespace-commands.sh, and create-codespace-and-checkout.sh
# into a single executable file

set -e

OUTPUT_FILE="${1:-create-codespace-and-checkout}"

cat > "$OUTPUT_FILE" << 'EOF'
#!/bin/bash

# Self-contained bundled version of create-codespace-and-checkout
# This file was automatically generated - do not edit manually

# ============================================================================
# lib.sh - Common library functions
# ============================================================================

EOF

# Append lib.sh content (skip shebang)
tail -n +2 lib.sh >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'

# ============================================================================
# create-codespace.sh - Codespace creation module
# ============================================================================

EOF

# Append create-codespace.sh content (skip shebang and source line)
tail -n +2 create-codespace.sh | grep -v "^source.*lib.sh" | grep -v "^# shellcheck source=" | grep -v '^SCRIPT_DIR=' >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'

# ============================================================================
# codespace-commands.sh - Codespace commands module
# ============================================================================

EOF

# Append codespace-commands.sh content (skip shebang and source line)
tail -n +2 codespace-commands.sh | grep -v "^source.*lib.sh" | grep -v "^# shellcheck source=" | grep -v '^SCRIPT_DIR=' >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'

# ============================================================================
# Main script - create-codespace-and-checkout.sh
# ============================================================================

EOF

# Append main script content (skip shebang and source lines)
tail -n +2 create-codespace-and-checkout.sh | \
    grep -v "^source.*lib.sh" | \
    grep -v "^source.*create-codespace.sh" | \
    grep -v "^source.*codespace-commands.sh" | \
    grep -v "^# shellcheck source=" | \
    grep -v '^SCRIPT_DIR=' | \
    grep -v '^# Get the directory where this script is located' \
    >> "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"

echo "Created bundled executable: $OUTPUT_FILE"
