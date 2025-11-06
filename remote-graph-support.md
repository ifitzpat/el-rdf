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

## Hook Architecture for Remote Graphs

### The Dual Context Problem

The existing hook system (`add-hooks`, `delete-hooks`, `query-hooks`) allows users to register functions that run when graph operations occur. For remote graphs, we need to consider **two different execution contexts**:

#### 1. Client-Side Hooks (Most Common)

These should run **in Emacs**, on the client machine:

- **LLM calls** - Sending triples to language models for analysis
- **Logging/debugging** - Recording operations locally
- **Validation** - Checking data before sending to remote
- **Client-side caching** - Storing frequently accessed results
- **UI updates** - Updating Emacs buffers or displays
- **Local transformations** - Preprocessing data before remote storage

**Example:**
```elisp
(defun llm-analysis-hook (graph operation data)
  "Send new triples to LLM for entity extraction."
  (when (eq operation 'add-triples)
    (let ((analysis (call-llm-api data)))
      (process-llm-response analysis))))

(add-hook-to-graph my-remote-graph 'add-hooks #'llm-analysis-hook)
```

#### 2. Server-Side Operations (Specialized)

These should run **on the SPARQL endpoint**, on the server:

- **Inference/reasoning** - OWL/RDFS entailment, rule engines
- **Server-side validation** - SHACL constraints, custom rules
- **Triggers** - Database-level operations on triple changes
- **Indexing** - Full-text search, spatial indexes

**Key insight:** We **cannot** directly execute Elisp code on the remote endpoint. Server-side operations must be configured on the endpoint itself.

### Proposed Solution: Layered Hook System

#### Layer 1: Client-Side Hooks (Implemented in el-rdf)

**All hooks run on the client** by default. For remote graphs:

1. **Pre-operation hooks** run before HTTP request
2. HTTP request sent to endpoint
3. **Post-operation hooks** run after HTTP response

This maintains backward compatibility while providing control over both sides of the remote operation.

#### Layer 2: Server-Side Configuration (Endpoint-Specific)

Server-side behavior (inference, validation) is configured on the SPARQL endpoint itself:

- **GraphDB**: Configure inference rulesets in repository settings
- **Fuseki**: Configure reasoners in server configuration
- **Stardog**: Use stored procedures and triggers

el-rdf can send **parameters** to trigger server-side features via HTTP headers or query parameters.

### Implementation: Enhanced Hook Types

Extend the hook system to support execution phases:

```elisp
(defun make-remote-graph (endpoint &optional name repository auth)
  "Create a remote RDF graph backed by a SPARQL endpoint."
  `((type . remote)
    (endpoint . ,endpoint)
    (repository . ,(or repository "default"))
    (auth . ,auth)
    (cache . ,(make-hash-table :test 'equal))
    (prefixes . ())
    (name . ,name)
    ;; Enhanced hook system with phases
    (hooks . ((pre-add-hooks . ,(list))      ; Run BEFORE remote operation
              (add-hooks . ,(list))          ; Run AFTER remote operation (backward compat)
              (pre-delete-hooks . ,(list))
              (delete-hooks . ,(list))
              (pre-query-hooks . ,(list))
              (query-hooks . ,(list))))
    ;; Server-side parameters (sent to endpoint)
    (server-params . ((inference . nil)      ; Enable inference?
                      (reasoning-level . nil) ; RDFS, OWL, etc.
                      (validate . nil)))))   ; Server-side validation?
```

### Hook Execution Flow for Remote Graphs

```elisp
(defun add-triples--remote (triplist graph)
  "Add triples to remote graph with client-side hooks."

  ;; 1. Run PRE-add hooks (client-side)
  (let ((pre-hooks (cdr (assoc 'pre-add-hooks (cdr (assoc 'hooks graph))))))
    (mapc (lambda (hook)
            (funcall hook graph 'add-triples triplist))
          pre-hooks))

  ;; 2. Prepare SPARQL update with server-side parameters
  (let* ((insert-query (el-rdf--triples-to-sparql-insert triplist))
         (server-params (alist-get 'server-params graph))
         ;; Add inference parameter if enabled
         (headers (if (alist-get 'inference server-params)
                     '(("Content-Type" . "application/sparql-update")
                       ("X-GraphDB-Reasoning" . "true"))
                   '(("Content-Type" . "application/sparql-update")))))

    ;; 3. Send to remote endpoint
    (el-rdf--sparql-update insert-query graph headers)

    ;; 4. Run POST-add hooks (client-side, after operation)
    (let ((post-hooks (cdr (assoc 'add-hooks (cdr (assoc 'hooks graph))))))
      (mapc (lambda (hook)
              (funcall hook graph 'add-triples triplist))
            post-hooks))))
```

### Configuration API

#### Client-Side Hooks (Standard)

```elisp
;; Add pre-operation hook (runs before HTTP request)
(add-hook-to-graph graph 'pre-add-hooks #'my-validation-hook)

;; Add post-operation hook (runs after HTTP response)
(add-hook-to-graph graph 'add-hooks #'my-llm-hook)
```

#### Server-Side Parameters

```elisp
;; Enable server-side inference
(el-rdf-set-server-param graph 'inference t)
(el-rdf-set-server-param graph 'reasoning-level 'rdfs)

;; Implementation:
(defun el-rdf-set-server-param (graph param value)
  "Set a server-side parameter for remote GRAPH.
Parameters are sent to the endpoint to trigger server-side features."
  (let ((params (alist-get 'server-params graph)))
    (setf (alist-get param params) value)))
```

### Example: LLM Hook on Remote Graph

```elisp
;; Create remote graph
(setq my-graph (make-remote-graph "http://localhost:7200"
                                  "knowledge-base"
                                  "test-repo"))

;; Enable server-side RDFS inference
(el-rdf-set-server-param my-graph 'inference t)
(el-rdf-set-server-param my-graph 'reasoning-level 'rdfs)

;; Add client-side LLM hook (runs after triples are stored remotely)
(add-hook-to-graph my-graph 'add-hooks
  (lambda (graph operation data)
    (when (eq operation 'add-triples)
      ;; This runs in Emacs after remote storage succeeds
      (let ((entities (extract-entities-via-llm data)))
        (message "LLM extracted: %S" entities)))))

;; Now when we add triples:
(add-triples '((alice friend bob)
               (bob worksAt acme-corp)) my-graph)

;; Execution flow:
;; 1. Pre-hooks run (none in this example)
;; 2. SPARQL INSERT sent to GraphDB with inference enabled
;; 3. GraphDB stores triples and computes RDFS inferences
;; 4. Post-hooks run: LLM analyzes triples client-side
```

### Backward Compatibility

For **local graphs**, nothing changes:
- Existing hooks work exactly as before
- `add-hooks` run after triples are added to in-memory indexes
- No pre/post distinction needed

For **remote graphs**:
- Existing `add-hooks` behave as post-operation hooks (backward compatible)
- New `pre-add-hooks` provide pre-operation control
- Server-side features are opt-in via `server-params`

### Impact on Implementation

This hook architecture affects:

1. **Phase 1** - Remote graph constructor needs `pre-*-hooks` and `server-params`
2. **Phase 3** - HTTP layer needs to send server parameters as headers
3. **Phase 4** - Dispatch layer runs pre-hooks → operation → post-hooks
4. **Phase 5** - Tests for hook execution order and server params
5. **Phase 6** - Documentation of client vs server-side operations

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
    ;; Enhanced hook system with pre/post phases
    (hooks . ((pre-add-hooks . ,(list))      ; Before HTTP request
              (add-hooks . ,(list))          ; After HTTP response
              (pre-delete-hooks . ,(list))
              (delete-hooks . ,(list))
              (pre-query-hooks . ,(list))
              (query-hooks . ,(list))))
    ;; Server-side parameters (sent to endpoint)
    (server-params . ((inference . nil)      ; Enable inference?
                      (reasoning-level . nil) ; RDFS, OWL, etc.
                      (validate . nil)))))   ; Server-side validation?
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

#### 1.5 Server Parameter Management

```elisp
(defun el-rdf-set-server-param (graph param value)
  "Set a server-side parameter for remote GRAPH.
Parameters are sent to the endpoint to trigger server-side features.

Common parameters:
  inference - Enable inference/reasoning (t/nil)
  reasoning-level - Level of reasoning ('rdfs, 'owl, etc.)
  validate - Enable server-side validation (t/nil)"
  (when (remote-graph-p graph)
    (let* ((params-entry (assoc 'server-params graph))
           (params (cdr params-entry)))
      (setf (alist-get param params) value))))

(defun el-rdf-get-server-param (graph param)
  "Get a server-side parameter from remote GRAPH."
  (when (remote-graph-p graph)
    (alist-get param (alist-get 'server-params graph))))
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
Returns t on success, signals error on failure.
Sends server-params as HTTP headers to trigger server-side features."
  (let* ((endpoint (alist-get 'endpoint graph))
         (repository (alist-get 'repository graph))
         (auth (alist-get 'auth graph))
         (server-params (alist-get 'server-params graph))
         (update-url (format "%s/repositories/%s/statements"
                            endpoint repository))
         (headers `(("Content-Type" . "application/sparql-update"))))

    ;; Add server-side parameter headers
    (when server-params
      ;; GraphDB-specific inference header
      (when (alist-get 'inference server-params)
        (push '("X-GraphDB-Reasoning" . "true") headers))
      ;; Could add more endpoint-specific headers here
      (let ((reasoning-level (alist-get 'reasoning-level server-params)))
        (when reasoning-level
          (push `("X-Reasoning-Level" . ,(symbol-name reasoning-level)) headers))))

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
  "Add multiple triples to remote graph via SPARQL INSERT.
Executes pre-add hooks, sends HTTP request, then executes post-add hooks."

  ;; 1. Run PRE-add hooks (client-side, before HTTP request)
  (let ((pre-hooks (cdr (assoc 'pre-add-hooks (cdr (assoc 'hooks graph))))))
    (mapc (lambda (hook) (funcall hook graph 'add-triples triplist))
          pre-hooks))

  ;; 2. Prepare and send SPARQL UPDATE (batched for efficiency)
  (let ((insert-query (el-rdf--triples-to-sparql-insert triplist)))
    (el-rdf--sparql-update insert-query graph))

  ;; 3. Run POST-add hooks (client-side, after HTTP response)
  (let ((post-hooks (cdr (assoc 'add-hooks (cdr (assoc 'hooks graph))))))
    (mapc (lambda (hook) (funcall hook graph 'add-triples triplist))
          post-hooks)))

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

#### 5.4 Hook Execution Order Tests

```elisp
(ert-deftest test-remote-graph-hook-execution-order ()
  "Test that hooks execute in correct order for remote graphs."
  :tags '(:integration :remote)
  (skip-unless (el-rdf--endpoint-available-p "http://localhost:7200"))

  (let ((execution-log '())
        (remote-graph (make-remote-graph "http://localhost:7200"
                                         "test-graph"
                                         "test-repo")))

    ;; Add pre-hook
    (add-hook-to-graph remote-graph 'pre-add-hooks
      (lambda (graph op data)
        (push 'pre-hook execution-log)))

    ;; Add post-hook
    (add-hook-to-graph remote-graph 'add-hooks
      (lambda (graph op data)
        (push 'post-hook execution-log)))

    ;; Execute operation
    (add-triples '((alice friend bob)) remote-graph)

    ;; Check execution order: should be (post-hook pre-hook) due to push
    (should (equal execution-log '(post-hook pre-hook)))))

(ert-deftest test-client-side-llm-hook ()
  "Test that LLM hooks run client-side, not on server."
  :tags '(:integration :remote)
  (skip-unless (el-rdf--endpoint-available-p "http://localhost:7200"))

  (let ((llm-called nil)
        (remote-graph (make-remote-graph "http://localhost:7200"
                                         "test-graph"
                                         "test-repo")))

    ;; Add client-side LLM hook (simulated)
    (add-hook-to-graph remote-graph 'add-hooks
      (lambda (graph op data)
        (setq llm-called t)
        ;; Simulate LLM call - this should happen in Emacs, not on server
        (message "LLM analyzing: %S" data)))

    ;; Execute operation
    (add-triples '((alice friend bob)) remote-graph)

    ;; Verify hook was called client-side
    (should llm-called)))

(ert-deftest test-server-side-inference-params ()
  "Test that server parameters are sent as HTTP headers."
  :tags '(:integration :remote)
  (skip-unless (el-rdf--endpoint-available-p "http://localhost:7200"))

  (let ((remote-graph (make-remote-graph "http://localhost:7200"
                                         "test-graph"
                                         "test-repo")))

    ;; Enable server-side inference
    (el-rdf-set-server-param remote-graph 'inference t)
    (el-rdf-set-server-param remote-graph 'reasoning-level 'rdfs)

    ;; Verify params are set
    (should (eq (el-rdf-get-server-param remote-graph 'inference) t))
    (should (eq (el-rdf-get-server-param remote-graph 'reasoning-level) 'rdfs))

    ;; Add triples - headers should be sent with inference enabled
    ;; (actual header verification would require mocking or inspection)
    (add-triples '((alice rdf:type foaf:Person)) remote-graph)))
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
- [ ] Implement `make-remote-graph` with enhanced hook system (pre/post hooks)
- [ ] Add `server-params` field to remote graphs
- [ ] Implement `graph-type`, `local-graph-p`, `remote-graph-p`
- [ ] Implement `el-rdf-set-server-param` and `el-rdf-get-server-param`

### Phase 2: SPARQL Translation
- [ ] Implement `el-rdf--term-to-sparql`
- [ ] Implement `el-rdf--triple-to-sparql`
- [ ] Implement `el-rdf--triples-to-sparql-insert`
- [ ] Implement `el-rdf--pattern-term-to-sparql`
- [ ] Implement `el-rdf--pattern-to-sparql`
- [ ] Implement `el-rdf--patterns-to-sparql-select`
- [ ] Implement `el-rdf--extract-variables`

### Phase 3: HTTP Communication
- [ ] Implement `el-rdf--sparql-update` with server-params header support
- [ ] Implement `el-rdf--sparql-query`
- [ ] Implement `el-rdf--parse-sparql-results`
- [ ] Implement `el-rdf--sparql-value-to-term`
- [ ] Add authentication support
- [ ] Add error handling with retries
- [ ] Support GraphDB-specific inference headers (X-GraphDB-Reasoning)

### Phase 4: Dispatch Layer
- [ ] Refactor `add-triple` → `add-triple--local` + `add-triple--remote` + dispatch
- [ ] Refactor `add-triples` → `add-triples--local` + `add-triples--remote` + dispatch
- [ ] Implement pre-hook execution in `add-triples--remote` (before HTTP)
- [ ] Implement post-hook execution in `add-triples--remote` (after HTTP)
- [ ] Refactor `delete-triple` → `delete-triple--local` + `delete-triple--remote` + dispatch
- [ ] Refactor `delete-triples` → `delete-triples--local` + `delete-triples--remote` + dispatch
- [ ] Implement pre/post-hook execution for delete operations
- [ ] Refactor `graph-query` → `graph-query--local` + `graph-query--remote` + dispatch
- [ ] Implement pre/post-hook execution for query operations
- [ ] Ensure backward compatibility: existing hooks work as post-operation hooks

### Phase 5: Testing
- [ ] Unit tests for SPARQL translation functions
- [ ] Unit tests for helper predicates
- [ ] Unit tests for server-param functions
- [ ] Integration tests with real SPARQL endpoint (tagged)
- [ ] Backward compatibility tests
- [ ] Hook execution order tests for remote graphs (pre → operation → post)
- [ ] Test that existing hooks work as post-operation hooks (backward compat)
- [ ] Test server-side inference parameter passing
- [ ] Test client-side hook execution (LLM calls, validation)

### Phase 6: Documentation
- [ ] Update README.org with remote graph examples
- [ ] Add docstrings to all new functions
- [ ] Document hook architecture: client-side vs server-side operations
- [ ] Document pre-hooks vs post-hooks with examples
- [ ] Document server-params (inference, reasoning-level, etc.)
- [ ] Create examples directory with remote graph usage
- [ ] Example: LLM hook on remote graph
- [ ] Example: Server-side inference configuration
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
