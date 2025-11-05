#!/bin/bash
# Ultra-naive parenthesis balance checker for Lisp files
# Simply counts ( and ) without any context awareness
#
# LIMITATIONS:
# - Counts parens in strings (e.g., "(hello)")
# - Counts parens in comments (e.g., ; comment with (parens))
# - Counts character literals like #\( and #\)
#
# Despite these limitations, it's useful for catching obvious balance errors
# and runs in <0.1 seconds. For detailed analysis, use: sblint <file>

if [ -z "$1" ]; then
    FILES="cl-rdf.lisp tests/cl-rdf-tests.lisp"
else
    FILES="$@"
fi

FAILED=0

for FILE in $FILES; do
    if [ ! -f "$FILE" ]; then
        echo "⚠️  File not found: $FILE"
        continue
    fi

    # Count all ( and ) characters
    OPEN=$(grep -o '(' "$FILE" | wc -l)
    CLOSE=$(grep -o ')' "$FILE" | wc -l)
    DIFF=$((OPEN - CLOSE))

    if [ $DIFF -eq 0 ]; then
        echo "✅ $FILE: Balanced ($OPEN opening, $CLOSE closing)"
    else
        FAILED=1
        if [ $DIFF -gt 0 ]; then
            echo "❌ $FILE: UNBALANCED - $DIFF extra opening paren(s)"
            echo "   ($OPEN opening, $CLOSE closing)"
        else
            DIFF_ABS=$((-DIFF))
            echo "❌ $FILE: UNBALANCED - $DIFF_ABS extra closing paren(s)"
            echo "   ($OPEN opening, $CLOSE closing)"
        fi
    fi
done

echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ All files have balanced parentheses"
    echo ""
    echo "Note: This is a naive check that counts ALL parens (including in strings/comments)."
    echo "For files that compile successfully, balanced count = correct parenthesization."
    exit 0
else
    echo "❌ Parenthesis balance check FAILED"
    echo ""
    echo "💡 Tips:"
    echo "   - Check for missing/extra parens in recent changes"
    echo "   - Use editor paren matching (% in vim, C-M-f/C-M-b in emacs)"
    echo "   - For detailed error location: sblint $FILE"
    exit 1
fi
