#!/bin/bash
# Build ECL binary for Termux/Android deployment

set -e

echo "=== Building cl-rdf-server for ECL/Termux ==="
echo ""

# Check ECL is available
if ! command -v ecl &> /dev/null; then
    echo "Error: ECL not found. Install with: pkg install ecl"
    exit 1
fi

# Check Quicklisp
if [ ! -f "$HOME/quicklisp/setup.lisp" ]; then
    echo "Error: Quicklisp not found at ~/quicklisp/setup.lisp"
    echo "Install Quicklisp first:"
    echo "  curl -O https://beta.quicklisp.org/quicklisp.lisp"
    echo "  ecl --load quicklisp.lisp --eval \"(quicklisp-quickstart:install)\" --eval \"(ext:quit)\""
    exit 1
fi

# Build the binary
echo "Building binary (this may take a few minutes)..."
ecl -load build-ecl-binary.lisp

if [ -f "cl-rdf-http" ]; then
    echo ""
    echo "✓ Build successful!"
    echo ""
    echo "Binary created: ./cl-rdf-http"
    echo "Size: $(du -h cl-rdf-http | cut -f1)"
    echo ""
    echo "Usage:"
    echo "  ./cl-rdf-http              # Start server on port 8080"
    echo "  ./cl-rdf-http --port 3000  # Start on custom port"
    echo "  ./cl-rdf-http --help       # Show options"
    echo ""
else
    echo "Error: Build failed - binary not created"
    exit 1
fi
