#!/bin/bash
# Setup script to configure git to use .githooks directory

echo "Setting up git hooks for cl-rdf..."

# Configure git to use .githooks directory
git config core.hooksPath .githooks

if [ $? -eq 0 ]; then
    echo "✅ Git hooks configured successfully!"
    echo ""
    echo "Hooks enabled:"
    echo "  - pre-commit: Checks parenthesis balance and function lengths"
    echo ""
    echo "To disable: git config --unset core.hooksPath"
    echo "To bypass on a single commit: git commit --no-verify"
else
    echo "❌ Failed to configure git hooks"
    exit 1
fi
