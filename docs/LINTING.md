# Common Lisp Linting for cl-rdf

This document describes the linting tools used for the cl-rdf project and how to integrate them.

## Available Linters

### 1. sblint (SBCL-based Linter)

**Purpose**: Static analysis using SBCL compiler warnings

**Checks**:
- Undeclared variables
- Type problems
- Wrong number of function arguments
- Undefined functions
- ANSI CL standard violations
- **Parenthesis balance errors** ✅

**Installation**:
```bash
# Using Roswell
ros install sbcl
ros install cxxxr/sblint

# Or using Quicklisp
(ql:quickload :sblint)
```

**Usage**:
```bash
# Check all files in current directory
sblint

# Check specific files
sblint cl-rdf.lisp

# Check specific directories
sblint tests/
```

**Output Format**:
```
file:line:column: message
```

**CI Integration**: See `.github/workflows/lint.yml` (to be created)

**GitHub**: https://github.com/cxxxr/sblint

---

### 2. lisp-critic (Code Style Checker)

**Purpose**: Detect common Lisp anti-patterns

**Checks**:
- Global variable misuse
- Inefficient accumulation patterns (SETQ in DOLIST)
- Wrong comparison functions (EQUAL vs EQL)
- Arithmetic idioms ((+ N 1) → (1+ N))

**Installation**:
```bash
(ql:quickload :lisp-critic)
```

**Usage** (REPL only):
```lisp
(use-package :lisp-critic)

;; Critique a single form
(critique '(defun foo (x) (+ x 1)))

;; Critique a file
(critique-file "cl-rdf.lisp")
```

**CI Integration**: ❌ Not supported (REPL-only tool)

**GitHub**: https://github.com/g000001/lisp-critic

---

### 3. Function Length Checker (Custom)

**Purpose**: Enforce 25-line maximum function length rule

**Usage**:
```bash
./scripts/check-function-length.sh
```

**Exit Codes**:
- `0`: All functions within limit ✅
- `1`: Some functions exceed limit ❌

**Output**:
```
❌ cl-rdf.lisp:488: Function exceeds 25 lines (30 lines)
   (defun expand-duals (duals element &optional (reorder nil))
```

**CI Integration**: Ready ✅

---

## CI Integration Recommendations

### Option 1: Add sblint to GitHub Actions (Recommended)

Create `.github/workflows/lint.yml`:

```yaml
name: Lint

on: [push, pull_request]

jobs:
  sblint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Roswell
        run: |
          sudo apt-get update
          sudo apt-get install -y ros

      - name: Install sblint
        run: |
          ros install sbcl
          ros install cxxxr/sblint

      - name: Run sblint
        run: sblint cl-rdf.lisp tests/

  function-length:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Check function lengths
        run: ./scripts/check-function-length.sh
```

### Option 2: Pre-commit Hook (Local Development)

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash

echo "Running function length check..."
./scripts/check-function-length.sh

if [ $? -ne 0 ]; then
    echo ""
    echo "Pre-commit check failed. Commit blocked."
    echo "Fix the issues or use 'git commit --no-verify' to skip."
    exit 1
fi

echo "✅ Pre-commit checks passed"
exit 0
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

### Option 3: Manual Check (During Development)

Add to `Makefile`:

```makefile
.PHONY: lint
lint:
	@echo "Running sblint..."
	@sblint cl-rdf.lisp tests/ || true
	@echo ""
	@echo "Checking function lengths..."
	@./scripts/check-function-length.sh
```

Usage:
```bash
make lint
```

---

## Current Status

### Functions Exceeding 25-Line Limit

As of 2025-11-05, the following functions need refactoring:

1. **`expand-duals`** (30 lines) - cl-rdf.lisp:488
   - Extract threading logic into helper

2. **`triples` method** (28 lines) - cl-rdf.lisp:863
   - Extract COND branches into `%query-by-subject`, `%query-by-predicate`, etc.

3. **`raw-triples` method** (26 lines) - cl-rdf.lisp:916
   - Extract COND branches into helpers

4. **`delete-triple` method** (26 lines) - cl-rdf.lisp:430
   - Extract cleanup logic into helper

### Refactoring Priority

- **Priority 1**: Refactor before Phase 5 to maintain clean codebase ✅
- **Priority 2**: Add sblint to CI after refactoring
- **Priority 3**: Add function-length checker to CI

---

## Benefits

1. **Early Error Detection**: Catch parenthesis errors and undefined functions before CI runs
2. **Code Quality**: Enforce consistent style and avoid anti-patterns
3. **Maintainability**: Keep functions small and focused (25 lines max)
4. **Team Standards**: Automated enforcement of coding standards

---

## Resources

- [sblint GitHub](https://github.com/cxxxr/sblint)
- [lisp-critic GitHub](https://github.com/g000001/lisp-critic)
- [Common Lisp Style Guide](https://lisp-lang.org/style-guide/)
- [Google Common Lisp Style Guide](https://google.github.io/styleguide/lispguide.xml)
