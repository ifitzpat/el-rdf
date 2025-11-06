# Remote Graph Support Implementation Plan

## Overview

This document outlines the plan to add remote RDF graph support to el-rdf, enabling interaction with SPARQL endpoints while maintaining compatibility with the existing local graph implementation.

## Motivation

The Common Lisp RDF library (cl-rdf) has a `remote-graph` concept that uses generic functions (CLOS methods) to provide a uniform interface for both local and remote graphs. We want to bring similar functionality to el-rdf.

## Current Architecture

### Graph Data Structure

Currently, el-rdf graphs are association lists (alists) containing:

```elisp
'((spo . #<hash-table>)      ; Subject-Predicate-Object index
  (osp . #<hash-table>)      ; Object-Subject-Predicate index
  (pos . #<hash-table>)      ; Predicate-Object-Subject index
  (hooks . ...)              ; Hook system (add/delete/query hooks)
  (prefixes . ...)           ; Namespace prefixes
  (name . ...))              ; Optional graph name
```

### Core Operations

Key functions that operate on graphs:
- `add-triple` / `add-triples` - Add triples to graph
- `delete-triple` / `delete-triples` - Remove triples from graph
- `graph-query` - Query triples with pattern matching
- `ask` - Boolean queries
- `select` - SELECT-style queries

All functions take the graph as a **parameter**, not as a method receiver.

### Access Patterns

Internal code accesses graph fields using:
```elisp
(cdr (assoc 'spo graph))
(cdr (assoc 'hooks graph))
(setf (cdr (assoc 'prefixes graph)) new-value)
```

Approximately **28 locations** in `el-rdf.el` use this pattern.

## Implementation Options

We evaluated three approaches:

### Option A: EIEIO (CLOS for Emacs) ❌ Not Selected

**Approach:** Convert graphs to EIEIO classes with generic methods

```elisp
(defclass el-rdf-graph () ...)
(defclass el-rdf-remote-graph (el-rdf-graph) ...)
(cl-defmethod add-triples (triplist (graph el-rdf-graph)) ...)
(cl-defmethod add-triples (triplist (graph el-rdf-remote-graph)) ...)
```

**Pros:**
- Most similar to cl-rdf's CLOS approach
- Clean polymorphism
- Extensible for future graph types

**Cons:**
- Breaking change requiring conversion of ~30 internal locations
- All `(cdr (assoc ...))` → `(oref graph field)`
- Requires handling graph serialization/checkpointing
- More complex refactor

### Option B: Simple Type Dispatch ✅ RECOMMENDED

**Approach:** Add `type` field to alist, use conditional dispatch

```elisp
(defun make-graph (&optional name)
  `((type . local)  ; Add type indicator
    (spo . ,(make-hash-table :test 'eq))
    ...))

(defun make-remote-graph (endpoint &optional name)
  `((type . remote)
    (endpoint . ,endpoint)
    (repository . "default")
    (auth . nil)
    (cache . ,(make-hash-table :test 'equal))
    (name . ,name)))

(defun add-triples (triplist graph)
  (pcase (alist-get 'type graph)
    ('local (add-triples--local triplist graph))
    ('remote (add-triples--remote triplist graph))))
```

**Pros:**
- **Backward compatible** - existing code continues working
- No EIEIO dependency
- Simple to understand and debug
- Incremental implementation possible

**Cons:**
- Manual dispatch in each function
- Less "elegant" than true generic functions

### Option C: Hook-Based Approach ❌ Not Selected

**Approach:** Use existing hook system to override behavior

**Cons:**
- Hook semantics don't fit all operations cleanly
- Less clear separation of concerns

## Selected Approach: Option B (Type Dispatch)

We're proceeding with **Option B** for the following reasons:

1. **Backward Compatibility** - Zero breaking changes for existing users
2. **Simplicity** - Clear, explicit dispatch logic
3. **Incremental Development** - Can implement one operation at a time
4. **No Additional Dependencies** - Works with standard Emacs Lisp

## Implementation Plan

### Phase 1: Foundation

#### 1.1 Update Dependencies

- Replace `request` with `plz` in Package-Requires
- `plz` provides simpler, more modern HTTP requests

```elisp
;; Before:
;; Package-Requires: ((emacs "27.1")(request)(dash "20250312.1307"))

;; After:
;; Package-Requires: ((emacs "27.1")(plz)(dash "20250312.1307"))
```

#### 1.2 Add Type Field to make-graph

```elisp
(defun make-graph (&optional name)
  "Create a new RDF graph with optional NAME for checkpointing."
  `((type . local)  ; NEW: Add type indicator
    (spo . ,(make-hash-table :test 'eq))
    (osp . ,(make-hash-table :test 'equal))
    (pos . ,(make-hash-table :test 'eq))
    (hooks . ((add-hooks . ,(list))
              (delete-hooks . ,(list))
              (query-hooks . ,(list))))
    (prefixes . ())
    (name . ,name)))
```

#### 1.3 Create Remote Graph Constructor

```elisp
(defun make-remote-graph (endpoint &optional name repository auth)
  "Create a remote RDF graph backed by a SPARQL endpoint.

ENDPOINT: Base URL of the SPARQL endpoint (e.g., \"http://localhost:7200\")
NAME: Optional graph name for identification
REPOSITORY: Repository/database name (default: \"default\")
AUTH: Optional authentication alist '((username . \"user\") (password . \"pass\"))"
  `((type . remote)
    (endpoint . ,endpoint)
    (repository . ,(or repository "default"))
    (auth . ,auth)
    (cache . ,(make-hash-table :test 'equal))
    (prefixes . ())
    (name . ,name)
    ;; Remote graphs support hooks too
    (hooks . ((add-hooks . ,(list))
              (delete-hooks . ,(list))
              (query-hooks . ,(list))))))
```

#### 1.4 Add Helper Predicates

```elisp
(defun graph-type (graph)
  "Return the type of GRAPH ('local or 'remote)."
  (or (alist-get 'type graph) 'local))  ; Default to local for backward compat

(defun local-graph-p (graph)
  "Return non-nil if GRAPH is a local graph."
  (eq (graph-type graph) 'local))

(defun remote-graph-p (graph)
  "Return non-nil if GRAPH is a remote graph."
  (eq (graph-type graph) 'remote))
```

### Phase 2: SPARQL Translation Layer

#### 2.1 Triple to SPARQL INSERT Translation

```elisp
(defun el-rdf--triple-to-sparql (triple &optional graph-uri)
  "Convert a TRIPLE to SPARQL triple notation.
Returns a string like \"<subject> <predicate> <object> .\""
  (let ((subject (nth 0 triple))
        (predicate (nth 1 triple))
        (object (nth 2 triple)))
    (format "%s %s %s ."
            (el-rdf--term-to-sparql subject)
            (el-rdf--term-to-sparql predicate)
            (el-rdf--term-to-sparql object))))

(defun el-rdf--term-to-sparql (term)
  "Convert an el-rdf term to SPARQL notation."
  (cond
   ;; URI/symbol → <uri> or prefix:local
   ((symbolp term)
    (let ((term-str (symbol-name term)))
      (if (string-match "^\\([^:]+\\):\\(.+\\)$" term-str)
          ;; Prefixed name (e.g., foaf:Person)
          term-str
        ;; Plain symbol → wrap in angle brackets
        (format "<%s>" term-str))))

   ;; String literal → "string"
   ((stringp term)
    (format "\"%s\"" (el-rdf--escape-sparql-string term)))

   ;; Number → typed literal
   ((numberp term)
    (format "\"%s\"^^<http://www.w3.org/2001/XMLSchema#integer>" term))

   ;; List → collection (not implemented in phase 1)
   ((listp term)
    (error "Collections not yet supported in remote graphs"))

   (t (error "Unknown term type: %S" term))))

(defun el-rdf--escape-sparql-string (str)
  "Escape special characters in STR for SPARQL."
  (replace-regexp-in-string
   "\\\\" "\\\\\\\\"
   (replace-regexp-in-string "\"" "\\\\\"" str)))

(defun el-rdf--triples-to-sparql-insert (triples &optional graph-uri)
  "Convert TRIPLES to a SPARQL INSERT DATA query."
  (let ((triple-strs (mapcar #'el-rdf--triple-to-sparql triples)))
    (format "INSERT DATA {\n  %s\n}"
            (string-join triple-strs "\n  "))))
```

#### 2.2 Graph Query to SPARQL SELECT Translation

```elisp
(defun el-rdf--pattern-to-sparql (pattern)
  "Convert an el-rdf query pattern to SPARQL triple pattern.
Pattern: ($x friend $y) → \"?x <friend> ?y\""
  (let ((subject (nth 0 pattern))
        (predicate (nth 1 pattern))
        (object (nth 2 pattern)))
    (format "%s %s %s ."
            (el-rdf--pattern-term-to-sparql subject)
            (el-rdf--pattern-term-to-sparql predicate)
            (el-rdf--pattern-term-to-sparql object))))

(defun el-rdf--pattern-term-to-sparql (term)
  "Convert a pattern term (which may be a variable) to SPARQL."
  (cond
   ;; Variable: $x → ?x
   ((and (symbolp term)
         (string-prefix-p "$" (symbol-name term)))
    (concat "?" (substring (symbol-name term) 1)))

   ;; Constant term
   (t (el-rdf--term-to-sparql term))))

(defun el-rdf--patterns-to-sparql-select (patterns variables)
  "Convert el-rdf PATTERNS to a SPARQL SELECT query.
VARIABLES: List of variables to select (e.g., ($x $y))"
  (let ((var-strs (mapcar (lambda (v)
                            (concat "?" (substring (symbol-name v) 1)))
                          variables))
        (pattern-strs (mapcar #'el-rdf--pattern-to-sparql patterns)))
    (format "SELECT %s WHERE {\n  %s\n}"
            (string-join var-strs " ")
            (string-join pattern-strs "\n  "))))
```

### Phase 3: HTTP Communication Layer

#### 3.1 SPARQL Update (INSERT/DELETE)

```elisp
(defun el-rdf--sparql-update (update-query graph)
  "Execute a SPARQL UPDATE query against remote GRAPH.
Returns t on success, signals error on failure."
  (let* ((endpoint (alist-get 'endpoint graph))
         (repository (alist-get 'repository graph))
         (auth (alist-get 'auth graph))
         (update-url (format "%s/repositories/%s/statements"
                            endpoint repository))
         (headers `(("Content-Type" . "application/sparql-update"))))

    ;; Add auth if provided
    (when auth
      (let ((username (alist-get 'username auth))
            (password (alist-get 'password auth)))
        (when (and username password)
          (push `("Authorization" .
                  ,(concat "Basic "
                           (base64-encode-string
                            (format "%s:%s" username password))))
                headers))))

    ;; Send request with plz
    (condition-case err
        (progn
          (plz 'post update-url
            :headers headers
            :body update-query
            :as 'string)
          t)
      (plz-error
       (error "SPARQL update failed: %S" err)))))
```

#### 3.2 SPARQL Query (SELECT)

```elisp
(defun el-rdf--sparql-query (query-string graph)
  "Execute a SPARQL SELECT query against remote GRAPH.
Returns parsed JSON results."
  (let* ((endpoint (alist-get 'endpoint graph))
         (repository (alist-get 'repository graph))
         (auth (alist-get 'auth graph))
         (query-url (format "%s/repositories/%s" endpoint repository))
         (headers `(("Content-Type" . "application/sparql-query")
                    ("Accept" . "application/sparql-results+json"))))

    ;; Add auth if provided
    (when auth
      (let ((username (alist-get 'username auth))
            (password (alist-get 'password auth)))
        (when (and username password)
          (push `("Authorization" .
                  ,(concat "Basic "
                           (base64-encode-string
                            (format "%s:%s" username password))))
                headers))))

    ;; Send request with plz
    (condition-case err
        (let ((response (plz 'post query-url
                          :headers headers
                          :body query-string
                          :as 'string)))
          (json-read-from-string response))
      (plz-error
       (error "SPARQL query failed: %S" err)))))
```

#### 3.3 Parse SPARQL JSON Results

```elisp
(defun el-rdf--parse-sparql-results (json-results)
  "Parse SPARQL JSON results into el-rdf bindings format.
Converts from:
  {\"results\": {\"bindings\": [{\"x\": {\"type\": \"uri\", \"value\": \"...\"}}]}}
To:
  ((($x . value1)) (($x . value2)) ...)"
  (let* ((bindings (alist-get 'bindings
                              (alist-get 'results json-results)))
         (results '()))
    (dolist (binding bindings)
      (let ((binding-alist '()))
        (dolist (var-binding binding)
          (let* ((var-name (car var-binding))
                 (var-data (cdr var-binding))
                 (var-type (alist-get 'type var-data))
                 (var-value (alist-get 'value var-data))
                 ;; Convert ?x back to $x
                 (el-var (intern (concat "$" (symbol-name var-name))))
                 (el-value (el-rdf--sparql-value-to-term var-value var-type)))
            (push (cons el-var el-value) binding-alist)))
        (push (nreverse binding-alist) results)))
    (nreverse results)))

(defun el-rdf--sparql-value-to-term (value type)
  "Convert a SPARQL result VALUE of TYPE to an el-rdf term."
  (pcase type
    ("uri" (intern value))
    ("literal" value)
    ("typed-literal" value)  ; TODO: Handle datatypes
    ("bnode" (intern value))
    (_ value)))
```

### Phase 4: Dispatch Layer

#### 4.1 Refactor add-triple/add-triples

```elisp
;; Rename current implementation
(defun add-triple--local (triple graph)
  "Add a single triple to a local graph.
Original implementation from add-triple."
  (let* ((newsub (nth 0 triple))
         (newpred (if (eq (nth 1 triple) 'rdf:type) 'a (nth 1 triple)))
         (newobj (el-rdf--process-triple-object (nth 2 triple)))
         (spo (cdr (assoc 'spo graph)))
         (osp (cdr (assoc 'osp graph)))
         (pos (cdr (assoc 'pos graph)))
         ;; ... rest of current implementation
         )))

(defun add-triple--remote (triple graph)
  "Add a single triple to a remote graph via SPARQL INSERT."
  (let ((insert-query (el-rdf--triples-to-sparql-insert (list triple))))
    (el-rdf--sparql-update insert-query graph)))

;; New dispatching version
(defun add-triple (triple graph)
  "Add TRIPLE to GRAPH (local or remote)."
  (pcase (graph-type graph)
    ('local (add-triple--local triple graph))
    ('remote (add-triple--remote triple graph))
    (_ (error "Unknown graph type: %S" (graph-type graph)))))

;; Bulk operations
(defun add-triples--local (triplist graph)
  "Add multiple triples to local graph."
  (mapc (lambda (x) (add-triple--local x graph)) triplist)
  ;; Call add-hooks
  (let ((add-hooks (cdr (assoc 'add-hooks (cdr (assoc 'hooks graph))))))
    (mapc (lambda (hook) (funcall hook graph 'add-triples triplist))
          add-hooks)))

(defun add-triples--remote (triplist graph)
  "Add multiple triples to remote graph via SPARQL INSERT."
  ;; More efficient: batch all triples into one INSERT
  (let ((insert-query (el-rdf--triples-to-sparql-insert triplist)))
    (el-rdf--sparql-update insert-query graph)
    ;; Call add-hooks
    (let ((add-hooks (cdr (assoc 'add-hooks (cdr (assoc 'hooks graph))))))
      (mapc (lambda (hook) (funcall hook graph 'add-triples triplist))
            add-hooks))))

(defun add-triples (triplist graph)
  "Add multiple triples to GRAPH (local or remote)."
  (pcase (graph-type graph)
    ('local (add-triples--local triplist graph))
    ('remote (add-triples--remote triplist graph))
    (_ (error "Unknown graph type: %S" (graph-type graph)))))
```

#### 4.2 Refactor delete-triple/delete-triples

```elisp
(defun delete-triple--local (triple graph)
  "Delete a single triple from local graph."
  ;; Current implementation
  ...)

(defun delete-triple--remote (triple graph)
  "Delete a single triple from remote graph via SPARQL DELETE."
  (let* ((subject (nth 0 triple))
         (predicate (nth 1 triple))
         (object (nth 2 triple))
         (delete-query
          (format "DELETE DATA {\n  %s\n}"
                  (el-rdf--triple-to-sparql triple))))
    (el-rdf--sparql-update delete-query graph)))

(defun delete-triple (triple graph)
  "Delete TRIPLE from GRAPH (local or remote)."
  (pcase (graph-type graph)
    ('local (delete-triple--local triple graph))
    ('remote (delete-triple--remote triple graph))
    (_ (error "Unknown graph type: %S" (graph-type graph)))))

;; Similar for delete-triples
```

#### 4.3 Refactor graph-query

```elisp
(defun graph-query--local (clauses graph &optional bindings)
  "Query local graph."
  ;; Current implementation
  (el-rdf--graph-query-internal clauses graph bindings))

(defun graph-query--remote (clauses graph &optional bindings)
  "Query remote graph via SPARQL SELECT."
  ;; Extract variables from clauses
  (let* ((variables (el-rdf--extract-variables clauses))
         (sparql-query (el-rdf--patterns-to-sparql-select clauses variables))
         (json-results (el-rdf--sparql-query sparql-query graph)))
    (el-rdf--parse-sparql-results json-results)))

(defun graph-query (clauses graph &optional bindings)
  "Query GRAPH (local or remote) with CLAUSES."
  ;; Call query-hooks
  (let ((query-hooks (cdr (assoc 'query-hooks (cdr (assoc 'hooks graph))))))
    (mapc (lambda (hook) (funcall hook graph 'graph-query clauses))
          query-hooks))

  ;; Dispatch based on graph type
  (let ((raw-results
         (pcase (graph-type graph)
           ('local (graph-query--local clauses graph bindings))
           ('remote (graph-query--remote clauses graph bindings))
           (_ (error "Unknown graph type: %S" (graph-type graph))))))
    (if raw-results
        (el-rdf--normalize-binding-results raw-results)
      raw-results)))

(defun el-rdf--extract-variables (clauses)
  "Extract all variables from CLAUSES.
Returns a list of unique variables like ($x $y $z)."
  (let ((vars '()))
    (dolist (clause clauses)
      (dolist (term clause)
        (when (and (symbolp term)
                   (string-prefix-p "$" (symbol-name term)))
          (add-to-list 'vars term))))
    (nreverse vars)))
```

### Phase 5: Testing

#### 5.1 Unit Tests for SPARQL Translation

```elisp
(ert-deftest test-triple-to-sparql ()
  "Test conversion of el-rdf triples to SPARQL notation."
  (should (equal (el-rdf--triple-to-sparql '(alice friend bob))
                 "<alice> <friend> <bob> ."))
  (should (equal (el-rdf--triple-to-sparql '(alice name "Alice"))
                 "<alice> <name> \"Alice\" .")))

(ert-deftest test-pattern-to-sparql ()
  "Test conversion of query patterns to SPARQL."
  (should (equal (el-rdf--pattern-to-sparql '($x friend $y))
                 "?x <friend> ?y ."))
  (should (equal (el-rdf--pattern-to-sparql '(alice friend $y))
                 "<alice> <friend> ?y .")))
```

#### 5.2 Integration Tests (Requires SPARQL Endpoint)

```elisp
(ert-deftest test-remote-graph-add-query ()
  "Test adding and querying triples on a remote graph.
Requires a SPARQL endpoint at http://localhost:7200."
  :tags '(:integration :remote)
  (skip-unless (el-rdf--endpoint-available-p "http://localhost:7200"))

  (let ((remote-graph (make-remote-graph "http://localhost:7200"
                                         "test-graph"
                                         "test-repo")))
    ;; Add triples
    (add-triples '((alice friend bob)
                   (bob friend charlie)) remote-graph)

    ;; Query them back
    (let ((results (graph-query '(($x friend $y)) remote-graph)))
      (should (member '(($x . alice) ($y . bob)) results))
      (should (member '(($x . bob) ($y . charlie)) results)))))
```

#### 5.3 Compatibility Tests

```elisp
(ert-deftest test-backward-compatibility ()
  "Ensure existing code works with type field addition."
  (let ((graph (make-graph)))
    ;; Should default to local type
    (should (eq (graph-type graph) 'local))
    (should (local-graph-p graph))

    ;; All existing operations should work
    (add-triples '((alice friend bob)) graph)
    (should (ask '((alice friend bob)) graph))))
```

### Phase 6: Documentation

#### 6.1 Update README.org

Add section on remote graphs:

```org
** Remote Graphs

el-rdf supports remote RDF graphs backed by SPARQL endpoints.

*** Creating a Remote Graph

#+begin_src elisp
(setq my-remote-graph
      (make-remote-graph "http://localhost:7200"
                         "my-graph"
                         "my-repository"))
#+end_src

*** Using Remote Graphs

Remote graphs support the same API as local graphs:

#+begin_src elisp
;; Add triples
(add-triples '((alice friend bob)
               (bob friend charlie))
             my-remote-graph)

;; Query
(graph-query '(($x friend $y)) my-remote-graph)

;; Ask
(ask '((alice friend bob)) my-remote-graph)
#+end_src

*** Supported Endpoints

Remote graphs are tested with:
- GraphDB
- Apache Jena Fuseki
- Blazegraph
- Any SPARQL 1.1 compliant endpoint
```

#### 6.2 Add Docstrings

Ensure all new functions have comprehensive docstrings.

## Implementation Checklist

### Phase 1: Foundation
- [ ] Update Package-Requires: replace `request` with `plz`
- [ ] Add `(type . local)` to `make-graph`
- [ ] Implement `make-remote-graph`
- [ ] Implement `graph-type`, `local-graph-p`, `remote-graph-p`

### Phase 2: SPARQL Translation
- [ ] Implement `el-rdf--term-to-sparql`
- [ ] Implement `el-rdf--triple-to-sparql`
- [ ] Implement `el-rdf--triples-to-sparql-insert`
- [ ] Implement `el-rdf--pattern-term-to-sparql`
- [ ] Implement `el-rdf--pattern-to-sparql`
- [ ] Implement `el-rdf--patterns-to-sparql-select`
- [ ] Implement `el-rdf--extract-variables`

### Phase 3: HTTP Communication
- [ ] Implement `el-rdf--sparql-update`
- [ ] Implement `el-rdf--sparql-query`
- [ ] Implement `el-rdf--parse-sparql-results`
- [ ] Implement `el-rdf--sparql-value-to-term`
- [ ] Add authentication support
- [ ] Add error handling with retries

### Phase 4: Dispatch Layer
- [ ] Refactor `add-triple` → `add-triple--local` + `add-triple--remote` + dispatch
- [ ] Refactor `add-triples` → `add-triples--local` + `add-triples--remote` + dispatch
- [ ] Refactor `delete-triple` → `delete-triple--local` + `delete-triple--remote` + dispatch
- [ ] Refactor `delete-triples` → `delete-triples--local` + `delete-triples--remote` + dispatch
- [ ] Refactor `graph-query` → `graph-query--local` + `graph-query--remote` + dispatch
- [ ] Ensure hooks work for both local and remote graphs

### Phase 5: Testing
- [ ] Unit tests for SPARQL translation functions
- [ ] Unit tests for helper predicates
- [ ] Integration tests with real SPARQL endpoint (tagged)
- [ ] Backward compatibility tests
- [ ] Hook execution tests for remote graphs

### Phase 6: Documentation
- [ ] Update README.org with remote graph examples
- [ ] Add docstrings to all new functions
- [ ] Create examples directory with remote graph usage
- [ ] Document supported SPARQL endpoints
- [ ] Document authentication configuration

### Phase 7: Polish
- [ ] Add caching support for remote queries
- [ ] Add batch operation optimization
- [ ] Add connection pooling/reuse
- [ ] Add timeout configuration
- [ ] Performance benchmarks (local vs remote)

## Future Enhancements

### Caching Strategy

```elisp
(defun graph-query--remote (clauses graph &optional bindings)
  "Query remote graph with optional caching."
  (let* ((cache (alist-get 'cache graph))
         (cache-key (prin1-to-string clauses))
         (cached-result (gethash cache-key cache)))
    (if cached-result
        cached-result
      (let* ((variables (el-rdf--extract-variables clauses))
             (sparql-query (el-rdf--patterns-to-sparql-select clauses variables))
             (json-results (el-rdf--sparql-query sparql-query graph))
             (results (el-rdf--parse-sparql-results json-results)))
        ;; Cache for 60 seconds
        (puthash cache-key results cache)
        results))))
```

### Async Support

```elisp
(defun add-triples-async (triplist graph callback)
  "Add triples to remote graph asynchronously.
Calls CALLBACK with (success-p error-message) when complete."
  (when (remote-graph-p graph)
    (let ((insert-query (el-rdf--triples-to-sparql-insert triplist)))
      (plz 'post (format "%s/repositories/%s/statements"
                        (alist-get 'endpoint graph)
                        (alist-get 'repository graph))
        :headers '(("Content-Type" . "application/sparql-update"))
        :body insert-query
        :then (lambda (_) (funcall callback t nil))
        :else (lambda (err) (funcall callback nil err))))))
```

### Named Graphs Support

```elisp
(defun make-remote-graph (endpoint &optional name repository auth graph-uri)
  "...
GRAPH-URI: Optional named graph URI for SPARQL GRAPH clauses."
  `((type . remote)
    (endpoint . ,endpoint)
    (repository . ,(or repository "default"))
    (graph-uri . ,graph-uri)  ; NEW
    ...))

(defun el-rdf--triples-to-sparql-insert (triples &optional graph)
  "Convert TRIPLES to INSERT DATA, optionally into a named graph."
  (let ((graph-uri (and graph (alist-get 'graph-uri graph)))
        (triple-strs (mapcar #'el-rdf--triple-to-sparql triples)))
    (if graph-uri
        (format "INSERT DATA { GRAPH <%s> {\n  %s\n} }"
                graph-uri
                (string-join triple-strs "\n  "))
      (format "INSERT DATA {\n  %s\n}"
              (string-join triple-strs "\n  ")))))
```

## Dependencies

### Required
- `plz` - Modern HTTP library for Emacs
- `json` - JSON parsing (built-in)
- `dash` - List utilities (existing dependency)

### Optional
- A running SPARQL 1.1 endpoint for remote graphs

## Backward Compatibility

All existing code will continue to work without modification:

```elisp
;; Existing code - no changes needed
(let ((graph (make-graph)))
  (add-triples '((alice friend bob)) graph)
  (graph-query '(($x friend $y)) graph))
```

The `(type . local)` field is added automatically and old graphs will be treated as local by default.

## Performance Considerations

| Operation | Local | Remote | Notes |
|-----------|-------|--------|-------|
| add-triple | O(1) | O(network) | Remote requires HTTP round-trip |
| add-triples (bulk) | O(n) | O(network) | Remote batches into single INSERT |
| graph-query | O(index lookup) | O(network + endpoint processing) | Caching helps |

**Recommendation:** For bulk operations on remote graphs, always use `add-triples` instead of looping `add-triple` to minimize network requests.

## References

- SPARQL 1.1 Query: https://www.w3.org/TR/sparql11-query/
- SPARQL 1.1 Update: https://www.w3.org/TR/sparql11-update/
- plz library: https://github.com/alphapapa/plz.el
- GraphDB REST API: https://graphdb.ontotext.com/documentation/
