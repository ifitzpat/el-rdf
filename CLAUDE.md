# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

el-rdf is an in-memory RDF triple store implemented in Emacs Lisp. It provides SPARQL-like query operations, TTL file import, and graph visualization capabilities.

## Common Lisp Port (cl-rdf)

**IMPORTANT**: This repository contains both the original Emacs Lisp implementation (el-rdf) and an in-progress Common Lisp port (cl-rdf).

### Port Status

- **Branch**: `claude/cl-port-011CUpNDW7sG6n2sHxzXJPCp`
- **Plan**: See `CL-PORT-PLAN.md` for complete implementation roadmap
- **Progress**: Phase 1 (Core utilities) - in progress

### Key Differences: el-rdf vs cl-rdf

**Symbol Format**:
- **el-rdf**: Uses colon separator `namespace:resource` (e.g., `schema:Person`, `foaf:name`)
- **cl-rdf**: Uses period separator `namespace.resource` (e.g., `schema.Person`, `foaf.name`)
- **Reason**: Colon is reserved for CL packages; period won't conflict with SPARQL 1.1 property paths

**Variables**:
- Both use `$variable` syntax (e.g., `$subject`, `$name`) - works in both languages

**Wildcards**:
- Both use `t` as wildcard matching any value

**Format Conversion**:
- Conversion functions provided for interoperability between el-rdf and cl-rdf serialized graphs
- See Phase 13 in CL-PORT-PLAN.md for details

### TDD Workflow for cl-rdf Port

**CRITICAL**: The cl-rdf port uses Test-Driven Development with GitHub Actions CI. You MUST follow this workflow:

#### Step 1: Write Test First
```lisp
;; In tests/cl-rdf-tests.lisp
(in-suite :core)

(test variablep
  "Test variable predicate - identifies symbols starting with $"
  (is (variablep '$subject))
  (is (variablep '$name))
  (is (not (variablep 'regular-symbol)))
  (is (not (variablep "string")))
  (is (not (variablep 42))))
```

#### Step 2: Commit & Push (Test Should Fail)
```bash
git add tests/cl-rdf-tests.lisp
git commit -m "Add test for variablep"
git push origin claude/cl-port-011CUpNDW7sG6n2sHxzXJPCp
```
→ GitHub Actions runs → **Test FAILS** (expected - function not implemented)

#### Step 3: Implement Function
```lisp
;; In cl-rdf.lisp
(defun variablep (symbol)
  "Return T if SYMBOL is a SPARQL variable (starts with $).

  Variables are identified by a leading $ character in the symbol name.

  Examples:
    (variablep '$subject) => T
    (variablep '$name) => T
    (variablep 'regular-symbol) => NIL"
  (and (symbolp symbol)
       (let ((name (symbol-name symbol)))
         (and (> (length name) 0)
              (char= (char name 0) #\$)))))
```

#### Step 4: Commit & Push (Test Should Pass)
```bash
git add cl-rdf.lisp
git commit -m "Implement variablep with full test coverage"
git push origin claude/cl-port-011CUpNDW7sG6n2sHxzXJPCp
```
→ GitHub Actions runs → **Test PASSES** ✓

#### Step 5: Verify CI Results

**Automated CI Check** (Preferred):
```bash
./scripts/check-ci.sh
```

This script:
- Uses public GitHub API (no authentication needed)
- Shows latest run status, conclusion, and failed steps
- Returns: 0=passed, 1=failed, 2=in progress

**Manual Check** (Fallback):
- Go to https://github.com/ifitzpat/el-rdf/actions
- View latest workflow run
- Verify tests pass on both SBCL and ECL

**Expected Output** when tests pass:
```
✅ CI PASSED
```

**If tests fail**:
The script shows the failed step name and provides a link to view full details on GitHub.

### Important Notes for cl-rdf Development

1. **Always write tests before implementation** - This is non-negotiable for the port
2. **Push after each phase** - Write test → push → implement → push
3. **Check both implementations** - CI tests on SBCL and ECL, both must pass
4. **Follow the plan** - Implement functions in order according to CL-PORT-PLAN.md phases
5. **One function at a time** - Don't implement multiple functions in one commit
6. **Clear commit messages** - Format: "Add test for X" then "Implement X with test coverage"
7. **Evaluate threading opportunities** - When porting each function, evaluate whether threading with bordeaux-threads could provide performance benefits. Consider:
   - Large dataset processing (batch operations, index updates)
   - Independent query operations that could be parallelized
   - I/O operations (file reading, content reference resolution)
   - Multi-clause query evaluation where clauses are independent
   - Note: Simple predicates and utilities likely won't benefit from threading

### cl-rdf Project Structure

```
el-rdf/
├── package.lisp              # CL package definition
├── cl-rdf.asd                # ASDF system definition
├── cl-rdf.lisp               # Main implementation
├── tests/
│   ├── test-package.lisp     # Test suite organization
│   └── cl-rdf-tests.lisp     # Test implementations
├── .github/workflows/
│   └── cl-rdf-tests.yml      # CI configuration
└── CL-PORT-PLAN.md           # Complete implementation plan
```

### Running cl-rdf Tests Locally (If Available)

```bash
# SBCL
sbcl --eval "(asdf:test-system :cl-rdf)" --quit

# ECL
ecl --eval "(asdf:test-system :cl-rdf)" --eval "(ext:quit)"

# Or in REPL
(ql:quickload :cl-rdf/tests)
(fiveam:run! :cl-rdf)           ; Run all tests
(fiveam:run! :core)             ; Run core suite only
(fiveam:run! :storage)          # Run storage suite only
```

### cl-rdf Dependencies

- **alexandria** - Utilities library
- **ironclad** - For MD5 hashing (content references)
- **uiop** - Portable filesystem operations (included with ASDF)
- **fiveam** - Testing framework

**IMPORTANT**: When adding new dependencies to `cl-rdf.asd`, you MUST also update:
1. **`guix.scm`** - Add corresponding `sbcl-*` package to `inputs` or `native-inputs`
2. **`.github/workflows/cl-rdf-tests.yml`** - Add to `qlfile-template` if not in Quicklisp
3. **`CL-PORT-PLAN.md`** - Update dependencies list in the plan

Forgetting to update guix.scm will cause local Guix shell testing to fail with missing dependencies!

## Development Commands (el-rdf)

### Running Tests
```bash
make test
# Or explicitly:
emacs -batch -l ert -l test-el-rdf.el -f ert-run-tests-batch-and-exit
```

### Loading in Emacs
```elisp
(load-file "el-rdf.el")
(require 'el-rdf)
```

There is no build or compilation step - this is pure Emacs Lisp.

## Code Architecture

### Triple Storage System

el-rdf uses three hash table indices for efficient querying:

- **SPO** (Subject-Predicate-Object): Primary index by subject, stores `((predicate . (obj1 obj2 ...)))`
- **OSP** (Object-Subject-Predicate): Index by object for reverse lookups, stores `((subject . (pred1 pred2 ...)))`
- **POS** (Predicate-Object-Subject): Index by predicate, stores `((object . (subj1 subj2 ...)))`

The `add-triple` and `delete-triple` functions maintain all three indices. The `triples` function chooses which index to use based on the query pattern.

### Query Execution Flow

1. **Pattern Selection** (`triples` function): Determines which index to use based on non-variable components
2. **Pattern Matching** (`pat-match` function): Matches patterns against retrieved triples, returns variable bindings
3. **Binding Management** (`graph-query` / `el-rdf--graph-query-internal`): Handles complex multi-clause queries
4. **Result Projection** (`select`, `construct`, `ask`): Transforms raw bindings into result format

### Important Query Semantics

- Variables are symbols starting with `$` (e.g., `$subject`, `$name`)
- The symbol `t` acts as a wildcard matching any value
- `rdf:type` and `a` are treated as equivalent at storage time (normalized to `a`)
- Query results maintain triple-nested structure: `(((bindings1)) ((bindings2)))` where each binding is a list of `(var . value)` pairs

### Content Reference System

Large strings (> `el-rdf-max-string-length`, default 1000 chars) are automatically stored as file references:
- Content is hashed with MD5 and stored in `XDG_CACHE_HOME/el-rdf/content-<hash>.txt`
- Triple objects store `"file:content-<hash>.txt"` references
- `triples` function automatically resolves references (use `raw-triples` to preserve references)
- Enables deduplication and reduces memory usage for large literals

### Checkpointing System

Named graphs can be automatically saved on modifications:
- Register with `el-rdf-register-graph-for-checkpointing`
- Checkpoints saved to `XDG_CACHE_HOME/el-rdf/checkpoints/<name>.checkpoint`
- Metadata includes operation type, data size, timestamp, call stack
- Recover with `el-rdf-recover-from-checkpoint` or `el-rdf-restore-named-graph`

### Hook System

Graphs support hooks for CRUD operations:
- **add-hooks**: Called after `add-triples` (not `add-triple`)
- **delete-hooks**: Called after `delete-triples` (not `delete-triple`)
- **query-hooks**: Called during `graph-query` execution
- Hooks receive: `(graph operation data)`
- Manage with `add-hook-to-graph`, `remove-hook-from-graph`, `get-graph-hooks`

### TTL Import System

The `import-ttl` function parses Turtle (TTL) files:
- Tokenizer handles quoted strings (including triple-quoted), IRIs, blank nodes, comments
- Supports `@prefix` directives, angle bracket IRIs, blank node brackets `[ ... ]`, RDF collections `( ... )`
- URIs are compressed to prefixed form (e.g., `<http://schema.org/Person>` → `schema:Person`)
- Optional namespace parameter prefixes imported resources
- Blank nodes use el-rdf's `bnode` function (`_:G<number>` format)
- Language tags are currently stripped from literals

### Critical Implementation Details

**Triple Normalization:**
- `rdf:type` is normalized to `a` in `add-triple` (line 323)
- Queries handle equivalence by transforming results in `triples` function (lines 464-476)
- Never normalize patterns containing variables - equivalence is handled at retrieval time

**Binding Structure Consistency:**
- All query paths must return triple-nested structure for consistency
- Use `el-rdf--normalize-binding-results` to ensure uniform output
- Single-clause queries wrap results: `(mapcar #'list bindings)` (line 859)

**Large Dataset Handling:**
- Batch processing in `expand-duals` (lines 392-423) with `sit-for` yields to prevent stack overflow
- `max-lisp-eval-depth`, `max-specpdl-size`, `max-macroexpand-depth` increased to 5000+ (lines 35-40)
- Universal pattern queries (`t t t`) use batched key processing (lines 486-522)

**Serialization:**
- `triples-to-string` uses `%S` format for proper symbol quoting, critical for symbols with `#` characters (line 597)
- `save-graph` uses `raw-triples` to preserve file references
- `load-graph` reads serialized data with standard `read` function

## Key Functions Reference

**Graph Management:**
- `make-graph` - Create new graph with optional name for checkpointing
- `add-triple` / `add-triples` - Add data (only `add-triples` triggers hooks)
- `delete-triple` / `delete-triples` - Remove data (only `delete-triples` triggers hooks)
- `triples` - Retrieve triples matching pattern (resolves content references)
- `raw-triples` - Retrieve without resolving content references

**Querying:**
- `graph-query` (alias: `where`) - Core pattern matching with OPTIONAL support
- `select` - Project variable bindings from query results
- `ask` - Boolean query, returns t/nil
- `construct` - Build new triples from query results
- `filter` - Apply predicate to filter bindings
- `delete-data` - Pattern-based deletion

**Import/Export:**
- `import-ttl` - Parse and import Turtle file
- `save-graph` / `load-graph` - Serialize/deserialize graph
- `render-graph` - Export to SVG via Graphviz
- `render-graph-json` - Export to JSON format

## Testing

The test suite (test-el-rdf.el) provides comprehensive coverage:
- Basic CRUD operations
- Query patterns (SELECT, ASK, CONSTRUCT, FILTER, OPTIONAL)
- Hook system functionality
- Checkpointing and recovery
- Content reference system
- TTL import with various edge cases (blank nodes, collections, language tags, nested structures)
- Serialization roundtrip tests

When modifying core functionality, ensure existing tests pass and add new tests for edge cases.

## Common Pitfalls

1. **Don't normalize patterns with variables** - The `triples` function handles `a`/`rdf:type` equivalence automatically
2. **Only bulk operations trigger hooks** - `add-triple` and `delete-triple` do not call hooks, only `add-triples` and `delete-triples`
3. **Binding structure must be consistent** - All query execution paths must maintain triple-nested structure
4. **Use `%S` for symbol serialization** - Required for symbols containing special characters like `#`
5. **RDF collections require careful parsing** - Avoid duplicate `rdf:rest` triples and ensure punctuation doesn't become list items
6. **Content references are transparent** - Most code should use `triples` not `raw-triples` to get resolved content

## Dependencies

- Emacs 27.1+
- dash (list manipulation library from MELPA)
- cl-seq (Common Lisp sequence functions, built-in)
- Graphviz `dot` command (optional, for visualization)
