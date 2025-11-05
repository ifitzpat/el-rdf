# Common Lisp Port Implementation Plan

## Overview

This document outlines the plan for porting `el-rdf.el` to Common Lisp as `cl-rdf.lisp`. The port will maintain API compatibility where possible while adapting to Common Lisp idioms and addressing platform-specific differences.

## Target Compatibility

- **Primary**: SBCL (Steel Bank Common Lisp)
- **Secondary**: ECL (Embeddable Common Lisp)
- **Testing Framework**: FiveAM

## Key Porting Challenges

### 1. RDF Resource Naming Convention

**Issue**: el-rdf uses symbols like `namespace:resource` for RDF resources. In Common Lisp, the colon `:` is reserved for package separators.

**Solutions Considered**:
1. Use strings for all RDF resources (most portable but less convenient)
2. Use a different separator like `/` or `-` (e.g., `namespace/resource`)
3. Use symbols with escaped colons (e.g., `|namespace:resource|`)
4. Implement a custom reader macro

**Chosen Solution**: Use **symbols with vertical bars** for RDF resources: `|namespace:resource|`
- Preserves visual similarity to original
- Works with existing CL reader
- Allows querying with standard symbol operations
- Recommendation: Provide helper macro `rdf-sym` to create these: `(rdf-sym "schema:Person")`

### 2. SPARQL Variables

**Issue**: el-rdf uses `$variable` syntax for SPARQL-like variables.

**Solution**: Continue using this convention - CL allows `$` in symbols. Works as-is.
- Example: `$subject`, `$name`, `$age`

### 3. Emacs Buffer Operations

**Issue**: Several functions rely on Emacs buffer operations that don't exist in CL.

**Affected Functions**:
- `save-graph` - uses `find-file-noselect`, `get-buffer-create`, `with-current-buffer`
- `load-graph` - uses `find-file-noselect`, `get-buffer-create`, `with-current-buffer`
- `import-ttl` - uses `with-temp-buffer`, `insert-file-contents`
- `render-graph` - uses `with-temp-file`, `shell-command`

**Solutions**:
- **File I/O**: Replace with `with-open-file`, standard CL `read`/`write` operations
- **String processing**: Replace buffer operations with string operations
- **Shell commands**: Use `uiop:run-program` (portable across implementations)

### 4. Dependencies

**Emacs Lisp Dependencies**:
- `dash` - List manipulation library
- `cl-seq` - Common Lisp sequence functions (already in CL)

**Common Lisp Equivalents**:
- Most `dash` functions have CL equivalents or can be implemented with `alexandria`
- Specific mappings:
  - `-remove` → `remove-if`
  - `-filter` → `remove-if-not`
  - `-uniq` → `remove-duplicates`
  - `-any` → `some`
  - `-every` → `every`
  - `mapcan` → already in CL

**Proposed CL Dependencies**:
- `alexandria` - Utilities library (standard in CL ecosystem)
- `fiveam` - Testing framework
- `ironclad` - For MD5 hashing (content references)
- `uiop` - Portable pathname/filesystem operations (included in ASDF3)

## Project Structure

```
cl-rdf/
├── cl-rdf.asd           # ASDF system definition
├── cl-rdf.lisp          # Main implementation
├── package.lisp         # Package definition
├── tests/
│   ├── test-package.lisp
│   └── cl-rdf-tests.lisp
└── README-CL.md         # CL-specific documentation
```

## ASDF System Definition

```lisp
;;;; cl-rdf.asd

(asdf:defsystem #:cl-rdf
  :description "In-memory RDF triple store for Common Lisp"
  :author "Ian FitzPatrick <ian@ianfitzpatrick.eu>"
  :license "GPLv3"
  :version "0.3.0"
  :depends-on (#:alexandria
               #:ironclad
               #:uiop)
  :components ((:file "package")
               (:file "cl-rdf" :depends-on ("package")))
  :in-order-to ((test-op (test-op #:cl-rdf/tests))))

(asdf:defsystem #:cl-rdf/tests
  :description "Test suite for cl-rdf"
  :depends-on (#:cl-rdf #:fiveam)
  :components ((:module "tests"
                :components ((:file "test-package")
                             (:file "cl-rdf-tests" :depends-on ("test-package")))))
  :perform (test-op (o c) (symbol-call :fiveam '#:run! :cl-rdf)))
```

## Implementation Phases

### Phase 1: Core Data Structures and Utilities (Foundation)

**Order**: These are prerequisites for everything else.

1. **Package definition** (`package.lisp`)
   - Test: N/A (boilerplate)
   - Define package with exports
   - Set up reader syntax if needed

2. **Basic predicates**
   - `variablep` (rename from `variable?` for CL conventions)
   - `var-or-wildp`
   - Test first: Check `$var` returns T, regular symbols return NIL

3. **Blank node generation**
   - `bnode`
   - Test first: Generate blank nodes, verify format `_:G<number>`
   - Note: Use `gensym` with custom prefix

4. **Utility functions**
   - `namespace` (extract namespace from symbol)
   - Test first: `(namespace '|schema:Person|)` → `"schema"`

5. **Graph structure**
   - `make-graph`
   - Test first: Create graph, verify it has SPO/OSP/POS hash tables
   - Structure: plist or CLOS class (recommend CLOS for extensibility)

### Phase 2: Triple Storage (Core Functionality)

6. **Alist manipulation helpers**
   - `update-dual`
   - `remove-dual`
   - Test first: Add/remove values from nested alist structure

7. **Single triple operations**
   - `add-triple`
   - `delete-triple`
   - Test first: Add triple, verify it appears in all three indices
   - Test first: Delete triple, verify it's removed from all indices and cleanup works

8. **Triple expansion**
   - `expand-duals`
   - Test first: Convert internal alist format to triple list
   - Note: Remove `sit-for` yielding - not needed in CL

9. **Bulk operations**
   - `add-triples`
   - `delete-triples`
   - Test first: Add multiple triples, verify hooks are called
   - Note: Implement hook system in parallel

### Phase 3: Hook System

10. **Hook management**
    - `add-hook-to-graph`
    - `remove-hook-from-graph`
    - `get-graph-hooks`
    - Test first: Add hook, verify it's called on operations
    - Test first: Remove hook, verify it's no longer called

### Phase 4: Triple Retrieval

11. **Basic retrieval**
    - `triples` (main query function)
    - Test first: Query with different patterns, verify correct index is used
    - Test first: Verify `a`/`rdf:type` equivalence

12. **Raw retrieval**
    - `raw-triples`
    - Test first: Verify content references are NOT resolved

### Phase 5: Pattern Matching

13. **Pattern matching core**
    - `augmented-eq` (equality that handles strings/numbers)
    - `pat-match` (pattern matching against input)
    - Test first: Match variables, wildcards, literals

14. **Graph traversal**
    - `traverse-graph`
    - `filter-triples`
    - Test first: Apply pattern to triple set, get bindings

### Phase 6: Query Execution Engine

15. **Binding utilities**
    - `clean-bindings`
    - `compatible-bindings-p` (rename from `compatible-bindings?`)
    - `update-bindings`
    - Test first: Merge compatible bindings, reject incompatible ones

16. **Pattern normalization**
    - `normalize-pattern`
    - Test first: Normalize `rdf:type` to `a` only for concrete patterns

17. **Core query engine**
    - `graph-query-internal`
    - `graph-query` (public interface)
    - Test first: Single clause queries
    - Test first: Multi-clause queries
    - Test first: OPTIONAL clause support
    - Test first: Binding structure consistency

### Phase 7: Query Operations

18. **Boolean queries**
    - `ask`
    - Test first: Return T for matching pattern, NIL otherwise

19. **Variable projection**
    - `binding-val`
    - `bindings-from-row`
    - `select`
    - Test first: Project specific variables from results

20. **Triple construction**
    - `expand-list-bindings`
    - `construct`
    - Test first: Build new triples from query results

21. **Filtering**
    - `eval-with-bindings`
    - `filter`
    - Test first: Apply predicate to filter results

22. **Pattern-based deletion**
    - `delete-data`
    - Test first: Delete triples matching pattern

### Phase 8: Content Reference System

23. **Content reference utilities**
    - `content-reference-p`
    - `store-large-content` (using Ironclad for MD5)
    - `resolve-content-reference`
    - Test first: Large strings become file references
    - Test first: Content is deduplicated by hash
    - Test first: References are transparently resolved

24. **Content reference integration**
    - `process-triple-object`
    - `resolve-triple-object`
    - `resolve-triple-objects`
    - Test first: Integration with add-triple and triples

### Phase 9: Serialization (File I/O)

25. **Triple serialization**
    - `triples-to-string`
    - Test first: Serialize triples, handle symbols with `#` correctly
    - Use `prin1-to-string` or `write-to-string` with proper settings

26. **Graph persistence**
    - `save-graph`
    - `load-graph`
    - Test first: Save/load roundtrip preserves all triples
    - **CL Implementation**: Use `with-open-file` instead of buffers
    ```lisp
    (defun save-graph (graph filename)
      (let ((triples (raw-triples '(t t t) graph)))
        (with-open-file (out filename
                         :direction :output
                         :if-exists :supersede)
          (write triples :stream out :case :preserve))))

    (defun load-graph (graph filename)
      (with-open-file (in filename :direction :input)
        (let ((triples (read in)))
          (add-triples triples graph))))
    ```

### Phase 10: Checkpointing System

27. **Checkpoint utilities**
    - `get-checkpoint-dir`
    - `checkpoint-file-path`
    - Test first: Directory creation, path generation

28. **Checkpoint operations**
    - `register-graph-for-checkpointing`
    - `checkpoint-hook`
    - `save-named-graph`
    - `restore-named-graph`
    - Test first: Automatic checkpointing on modifications
    - Test first: Recovery from checkpoint

29. **Checkpoint metadata**
    - `save-checkpoint-metadata`
    - `load-checkpoint-metadata`
    - `list-checkpoints`
    - `delete-checkpoint`
    - Test first: Metadata persistence

### Phase 11: TTL Import (Complex, Buffer-Heavy)

30. **TTL parsing utilities**
    - `register-prefix`
    - `expand-prefixed-iri`
    - `intern-rdf-resource`
    - Test first: Prefix registration and expansion

31. **TTL value parsing**
    - `parse-ttl-value`
    - Test first: Parse literals, IRIs, blank nodes
    - **CL Implementation**: Use string operations, no buffers

32. **TTL tokenization**
    - `simple-tokenize-ttl`
    - Test first: Tokenize various TTL constructs
    - **CL Implementation**: Pure string processing
    ```lisp
    (defun simple-tokenize-ttl (content)
      "Tokenize TTL content string"
      (let ((tokens '())
            (pos 0)
            (len (length content)))
        ;; Implement character-by-character parsing
        ...))
    ```

33. **TTL structure parsing**
    - `parse-rdf-collection`
    - `parse-blank-node-bracket`
    - `parse-simple-ttl-statement`
    - Test first: Parse collections, blank nodes, statements
    - **CL Implementation**: Use arrays/vectors for O(1) access

34. **TTL import**
    - `parse-ttl-content`
    - `import-ttl`
    - Test first: Full TTL file import
    - **CL Implementation**:
    ```lisp
    (defun import-ttl (filename graph &optional namespace)
      (let ((content (uiop:read-file-string filename)))
        (parse-ttl-content graph content namespace)))
    ```

### Phase 12: Visualization (Optional, Lower Priority)

35. **Graph rendering**
    - `render-triple`
    - `nodes`, `literals`
    - `apply-node-styles`
    - `render-triples`
    - Test first: Generate DOT format

36. **Export to formats**
    - `render-graph`
    - `render-graph-json`
    - Test first: Export to SVG/JSON via Graphviz
    - **CL Implementation**: Use `uiop:run-program` for `dot` command
    ```lisp
    (defun render-graph (triples filename &optional styles)
      (let ((dot-file "/tmp/graph.dot"))
        (with-open-file (out dot-file :direction :output :if-exists :supersede)
          (write-string (render-triples triples styles) out))
        (uiop:run-program (list "dot" dot-file "-Tsvg" "-o" filename))))
    ```

## Testing Strategy

### Test-Driven Development Approach

For each function:
1. **Write test first** using FiveAM
2. **Run test** (it should fail)
3. **Implement function**
4. **Run test again** (it should pass)
5. **Refactor** if needed

### Test Organization

```lisp
;;;; tests/cl-rdf-tests.lisp

(in-package #:cl-rdf-tests)

(def-suite :cl-rdf
  :description "Master test suite for cl-rdf")

(def-suite :core :in :cl-rdf
  :description "Core data structures and utilities")

(def-suite :storage :in :cl-rdf
  :description "Triple storage operations")

(def-suite :query :in :cl-rdf
  :description "Query execution")

(def-suite :ttl :in :cl-rdf
  :description "TTL import")

;; Example test structure
(in-suite :core)

(test variablep
  "Test variable predicate"
  (is (variablep '$subject))
  (is (variablep '$name))
  (is (not (variablep 'regular-symbol)))
  (is (not (variablep "string")))
  (is (not (variablep 42))))

(test make-graph
  "Test graph creation"
  (let ((g (make-graph)))
    (is (hash-table-p (graph-spo g)))
    (is (hash-table-p (graph-osp g)))
    (is (hash-table-p (graph-pos g)))
    (is (null (graph-name g)))))
```

### Running Tests

```lisp
;; Load system with tests
(asdf:test-system :cl-rdf)

;; Or run specific suite
(fiveam:run! :cl-rdf)
(fiveam:run! :core)
(fiveam:run! :query)
```

## Symbol Naming Conventions

Following Common Lisp conventions:

- **Predicates**: End with `p` not `?`
  - `variablep` instead of `variable?`
  - `var-or-wildp` instead of `var-or-wild?`
  - `optional-clause-p` instead of `optional-clause?`

- **Private/internal functions**: Prefix with `%` or use separate internal package
  - `%graph-query-internal` instead of `el-rdf--graph-query-internal`
  - Or: Use separate `cl-rdf-internal` package

- **Constants**: Use `+name+` convention
  - `+max-string-length+` instead of `el-rdf-max-string-length`

- **Special variables**: Use `*name*` convention
  - `*debug*` instead of `el-rdf-debug`
  - `*checkpoint-dir*` instead of `el-rdf-checkpoint-dir`

## Data Structure Choices

### Graph Representation

**Option 1: Plist (matches el-rdf closely)**
```lisp
(defun make-graph (&optional name)
  (list :spo (make-hash-table :test 'eq)
        :osp (make-hash-table :test 'equal)
        :pos (make-hash-table :test 'eq)
        :hooks (list :add-hooks nil
                     :delete-hooks nil
                     :query-hooks nil)
        :prefixes nil
        :name name))
```

**Option 2: CLOS (more idiomatic CL)**
```lisp
(defclass graph ()
  ((spo :initform (make-hash-table :test 'eq) :accessor graph-spo)
   (osp :initform (make-hash-table :test 'equal) :accessor graph-osp)
   (pos :initform (make-hash-table :test 'eq) :accessor graph-pos)
   (add-hooks :initform nil :accessor graph-add-hooks)
   (delete-hooks :initform nil :accessor graph-delete-hooks)
   (query-hooks :initform nil :accessor graph-query-hooks)
   (prefixes :initform nil :accessor graph-prefixes)
   (name :initarg :name :initform nil :accessor graph-name)))

(defun make-graph (&optional name)
  (make-instance 'graph :name name))
```

**Recommendation**: Use **CLOS** for better extensibility and CL idioms.

## Compatibility Notes

### SBCL vs ECL Differences

Most code will be portable, but watch for:

1. **Hash table performance**: SBCL has highly optimized hash tables, ECL may be slower
2. **File I/O**: Use `uiop` functions for portability
3. **External programs**: `uiop:run-program` works on both
4. **Threading**: If added later, use `bordeaux-threads`

### Testing on Both Implementations

```bash
# SBCL
sbcl --eval "(asdf:test-system :cl-rdf)" --quit

# ECL
ecl --eval "(asdf:test-system :cl-rdf)" --eval "(ext:quit)"
```

## Migration Path for Users

### API Compatibility Layer

Provide compatibility macros for el-rdf users:

```lisp
;; Allow question mark predicates
(defmacro variable? (x)
  `(variablep ,x))

;; Allow dash-style function names
(defmacro -remove (fn list)
  `(remove-if ,fn ,list))
```

### Symbol Conversion Utilities

```lisp
(defun elisp-symbol-to-rdf (elisp-symbol-name)
  "Convert elisp symbol name like 'schema:Person' to CL symbol |schema:Person|"
  (intern elisp-symbol-name))

(defmacro rdf-sym (name-string)
  "Create RDF symbol from string: (rdf-sym \"schema:Person\") => |schema:Person|"
  (intern name-string))
```

## Documentation

### Docstrings

Every exported function must have a docstring:

```lisp
(defun add-triple (triple graph)
  "Add a TRIPLE to GRAPH, updating all three indices (SPO, OSP, POS).

TRIPLE is a list of three elements: (subject predicate object).
GRAPH is a graph object created by MAKE-GRAPH.

The predicate rdf:type is normalized to 'a' for storage.
Large string objects are automatically stored as content references.

Does not trigger hooks. Use ADD-TRIPLES for bulk operations with hooks."
  ...)
```

### README-CL.md

Create CL-specific documentation covering:
- Installation instructions
- Quickstart guide
- API differences from el-rdf
- Symbol naming conventions
- Common Lisp-specific features

## Future Enhancements

### Beyond Initial Port

1. **CLOS integration**: Use CLOS for better OOP patterns
2. **Concurrency**: Add thread-safe operations with locks
3. **Persistence backends**: Add database backends (PostgreSQL, SQLite)
4. **SPARQL 1.1**: Expand query language support
5. **Streaming**: Support streaming large datasets
6. **Optimizations**: Profile and optimize hot paths
7. **RDF/XML**: Add RDF/XML import/export
8. **N-Triples**: Add N-Triples format support

## Success Criteria

### Phase 1-7 (MVP - Minimum Viable Port)

- [ ] All core triple operations working
- [ ] Query execution engine complete
- [ ] All basic query operations (ASK, SELECT, CONSTRUCT, FILTER)
- [ ] Test coverage >80%
- [ ] Works on both SBCL and ECL
- [ ] Basic documentation complete

### Phase 8-10 (Feature Complete)

- [ ] Content reference system working
- [ ] Serialization working
- [ ] Checkpointing system working
- [ ] Test coverage >90%

### Phase 11-12 (Full Parity)

- [ ] TTL import working
- [ ] Graph visualization working
- [ ] Test coverage >95%
- [ ] Performance benchmarks showing comparable performance to el-rdf

## Development Workflow

### Iterative Development

For each function:

```bash
# 1. Write test
emacs tests/cl-rdf-tests.lisp

# 2. Load in REPL
sbcl
* (ql:quickload :cl-rdf/tests)
* (fiveam:run! :core)  ; Should fail

# 3. Implement function
* (load "cl-rdf.lisp")
* (fiveam:run! :core)  ; Should pass

# 4. Commit
git add tests/cl-rdf-tests.lisp cl-rdf.lisp
git commit -m "Implement function-name with tests"
```

### Commit Strategy

- One commit per function (or small group of related functions)
- Include both test and implementation in same commit
- Clear commit messages: "Implement add-triple with full test coverage"

## Timeline Estimate

- **Phase 1-2**: 2-3 days (Foundation + Storage)
- **Phase 3-5**: 2-3 days (Hooks + Retrieval + Pattern Matching)
- **Phase 6-7**: 3-4 days (Query Engine + Operations)
- **Phase 8-10**: 2-3 days (Content Refs + Serialization + Checkpointing)
- **Phase 11**: 3-4 days (TTL Import - most complex)
- **Phase 12**: 1-2 days (Visualization - optional)

**Total**: ~13-19 days of focused work

## Next Steps

1. ✅ Create branch `claude/cl-port-011CUpNDW7sG6n2sHxzXJPCp`
2. ✅ Write this implementation plan
3. Commit this plan
4. Create package.lisp with package definition
5. Create cl-rdf.asd with system definition
6. Create tests/test-package.lisp
7. Create tests/cl-rdf-tests.lisp with test suites
8. Begin Phase 1: Core utilities

---

**Note**: This is a living document. Update as implementation progresses and new challenges are discovered.
