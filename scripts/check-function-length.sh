#!/bin/bash
# Check that all functions are <= 30 lines (excluding docstrings, comments, blank lines)

MAX_LINES=30
FAILED=0

echo "Checking function lengths (max $MAX_LINES lines per function)..."

# AWK script to count function body lines
awk '
BEGIN {
    in_func = 0
    func_name = ""
    start_line = 0
    body_lines = 0
    in_docstring = 0
    max_lines = '"$MAX_LINES"'
    failed = 0
}

# Match function definition
/^[[:space:]]*\(def(un|method|generic)/ {
    if (in_func && body_lines > max_lines) {
        printf "❌ %s:%d: Function exceeds %d lines (%d lines)\n", FILENAME, start_line, max_lines, body_lines
        printf "   %s\n", func_name
        failed = 1
    }
    in_func = 1
    func_name = $0
    gsub(/^[[:space:]]+/, "", func_name)  # trim leading whitespace
    start_line = NR
    body_lines = 0
    in_docstring = 0
    next
}

in_func {
    # Skip blank lines
    if (/^[[:space:]]*$/) next

    # Detect start of docstring
    if (!in_docstring && /^[[:space:]]*"/) {
        in_docstring = 1
        next
    }

    # Detect end of docstring (line ending with ")
    if (in_docstring && /"[[:space:]]*$/) {
        in_docstring = 0
        next
    }

    # Skip lines within docstring
    if (in_docstring) next

    # Skip comment lines
    if (/^[[:space:]]*;/) next

    # Count this as a body line
    body_lines++
}

END {
    # Check last function
    if (in_func && body_lines > max_lines) {
        printf "❌ %s:%d: Function exceeds %d lines (%d lines)\n", FILENAME, start_line, max_lines, body_lines
        printf "   %s\n", func_name
        failed = 1
    }

    exit failed
}
' cl-rdf.lisp

if [ $? -eq 0 ]; then
    echo "✅ All functions are within $MAX_LINES line limit"
    exit 0
else
    echo ""
    echo "⚠️  Some functions exceed the $MAX_LINES line limit"
    echo "   Consider refactoring into smaller utility functions"
    exit 1
fi
