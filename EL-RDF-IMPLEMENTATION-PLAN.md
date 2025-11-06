# el-rdf EIEIO Refactor Implementation Plan

## Goal

Convert el-rdf to use EIEIO classes and generic methods to support both local and remote graphs with a uniform API.

## Constraints

- **Backward compatibility required** - `(make-graph)` must continue to work
- **All existing tests must pass** unchanged
- **No cl-rdf changes** - We're only modifying el-rdf
- **Use plz library** for HTTP (replacing request dependency)

## Current Structure (Alist-based)

```elisp
;; Graph is an alist
(defun make-graph (&optional name)
  `((type . local)
    (spo . ,(make-hash-table ...))
    (osp . ,(make-hash-table ...))
    (pos . ,(make-hash-table ...))
    (hooks . ...)
    (prefixes . ())
    (name . ,name)))

;; Functions operate on alist
(defun add-triples (triplist graph)
  (mapc (lambda (x) (add-triple x graph)) triplist)
  ;; trigger hooks
  ...)
```

## Target Structure (EIEIO-based)

```elisp
;; Base class
(defclass el-rdf-graph ()
  ((hooks :initform ...)
   (name :initarg :name :accessor graph-name)))

;; Local graph
(defclass el-rdf-local-graph (el-rdf-graph)
  ((spo :initform (make-hash-table ...))
   (osp :initform ...)
   (pos :initform ...)
   (prefixes :initform nil)))

;; Remote graph
(defclass el-rdf-remote-graph (el-rdf-graph)
  ((endpoint :initarg :endpoint)
   (graph-name :initarg :graph-name)
   (token :initarg :token)
   (timeout :initarg :timeout)))

;; Generic methods dispatch automatically
(cl-defmethod add-triples (triplist (graph el-rdf-local-graph))
  ...)

(cl-defmethod add-triples (triplist (graph el-rdf-remote-graph))
  ...)
```

## Implementation Strategy

### Phase 1: Infrastructure (No Breaking Changes)

Add EIEIO classes alongside existing code:

1. Add `el-rdf-graph` base class
2. Add `el-rdf-local-graph` class
3. Add helper to convert alist → object (for transition)
4. Keep existing functions working

### Phase 2: Refactor Local Graph

Convert existing functions to methods for local graphs:

1. Rename existing functions: `add-triple` → `add-triple--internal`
2. Create generic functions and methods
3. Update `make-graph` to return EIEIO object
4. All tests should still pass

### Phase 3: Add Remote Graph

Add remote graph support:

1. Add `el-rdf-remote-graph` class
2. Add HTTP client (S-expression based)
3. Implement remote methods
4. Add remote hook management API

### Phase 4: Testing & Documentation

1. Run existing tests
2. Add remote graph tests
3. Update documentation

## Detailed Steps

### Step 1: Add Base Class

```elisp
(require 'eieio)

(defclass el-rdf-graph ()
  ((name
    :initarg :name
    :initform nil
    :accessor graph-name
    :documentation "Optional name for graph identification")
   (hooks
    :initform '((add-hooks . nil)
                (delete-hooks . nil)
                (query-hooks . nil))
    :accessor graph-hooks
    :documentation "Hook system for graph operations"))
  (:documentation "Abstract base class for all graph types"))
```

### Step 2: Add Local Graph Class

```elisp
(defclass el-rdf-local-graph (el-rdf-graph)
  ((spo
    :initform (make-hash-table :test 'eq)
    :accessor graph-spo
    :documentation "Subject-Predicate-Object index")
   (osp
    :initform (make-hash-table :test 'equal)
    :accessor graph-osp
    :documentation "Object-Subject-Predicate index")
   (pos
    :initform (make-hash-table :test 'eq)
    :accessor graph-pos
    :documentation "Predicate-Object-Subject index")
   (prefixes
    :initform nil
    :accessor graph-prefixes
    :documentation "Namespace prefix alist"))
  (:documentation "Local in-memory RDF graph"))
```

### Step 3: Update make-graph

```elisp
(defun make-graph (&optional name)
  "Create a new RDF graph.
Returns an el-rdf-local-graph instance for backward compatibility."
  (make-instance 'el-rdf-local-graph :name name))
```

### Step 4: Convert add-triple to Method

```elisp
;; Generic function
(cl-defgeneric add-triple (triple graph)
  "Add TRIPLE to GRAPH.")

;; Local implementation
(cl-defmethod add-triple (triple (graph el-rdf-local-graph))
  "Add a single triple to local graph."
  (let* ((newsub (nth 0 triple))
         (newpred (if (eq (nth 1 triple) 'rdf:type) 'a (nth 1 triple)))
         (newobj (el-rdf--process-triple-object (nth 2 triple)))
         (spo (graph-spo graph))
         (osp (graph-osp graph))
         (pos (graph-pos graph))
         (po (gethash newsub spo))
         (sp (gethash newobj osp))
         (os (gethash newpred pos)))
    ;; ... existing implementation
    ))
```

### Step 5: Convert Other Core Functions

Apply same pattern to:
- `add-triples`
- `delete-triple`
- `delete-triples`
- `graph-query`
- `triples` / `raw-triples`
- `ask`
- Hook management functions

### Step 6: Add Remote Graph Class

```elisp
(defclass el-rdf-remote-graph (el-rdf-graph)
  ((endpoint
    :initarg :endpoint
    :accessor graph-endpoint
    :documentation "Base URL of cl-rdf server")
   (graph-name
    :initarg :graph-name
    :accessor remote-graph-name
    :documentation "Name of graph on remote server")
   (token
    :initarg :token
    :initform nil
    :accessor graph-token
    :documentation "Bearer token for authentication")
   (timeout
    :initarg :timeout
    :initform 60
    :accessor graph-timeout
    :documentation "Request timeout in seconds")
   (cache
    :initform (make-hash-table :test 'equal)
    :accessor graph-cache
    :documentation "Query result cache"))
  (:documentation "Remote RDF graph accessed via HTTP"))

(defun make-remote-graph (endpoint graph-name &rest args)
  "Create a remote graph client.
ENDPOINT: Base URL of cl-rdf server
GRAPH-NAME: Name of graph on server
ARGS: :token, :timeout, :name"
  (apply #'make-instance 'el-rdf-remote-graph
         :endpoint endpoint
         :graph-name graph-name
         args))
```

### Step 7: Implement HTTP Client

```elisp
(require 'plz)

(defun el-rdf--http-request (graph endpoint-path data)
  "Make HTTP request to cl-rdf server using S-expressions.
GRAPH: el-rdf-remote-graph instance
ENDPOINT-PATH: API path (e.g., \"/add\")
DATA: Lisp data structure to send"
  (let* ((url (format "%s%s" (graph-endpoint graph) endpoint-path))
         (body (prin1-to-string data))
         (headers `(("Content-Type" . "application/sexp")
                   ("Accept" . "application/sexp")))
         (token (graph-token graph)))

    ;; Add auth header if token present
    (when token
      (push `("Authorization" . ,(format "Bearer %s" token)) headers))

    ;; Make request with plz
    (let ((response (plz 'post url
                      :headers headers
                      :body body
                      :as 'string
                      :timeout (graph-timeout graph))))

      ;; Parse S-expression response
      (let ((data (car (read-from-string response))))
        (pcase (car data)
          (:ok (cadr data))
          (:error (error "Server error: %S" (cadr data)))
          (_ (error "Invalid response: %S" data)))))))
```

### Step 8: Implement Remote Methods

```elisp
(cl-defmethod add-triples (triples (graph el-rdf-remote-graph))
  "Add triples to remote graph via HTTP."
  ;; Run local hooks
  (el-rdf--run-hooks graph 'add-hooks triples)

  ;; Send to server
  (el-rdf--http-request graph "/add"
                        `(:graph ,(remote-graph-name graph)
                          :triples ,triples)))

(cl-defmethod delete-triples (triples (graph el-rdf-remote-graph))
  "Delete triples from remote graph via HTTP."
  (el-rdf--run-hooks graph 'delete-hooks triples)

  (el-rdf--http-request graph "/delete"
                        `(:graph ,(remote-graph-name graph)
                          :triples ,triples)))

(cl-defmethod graph-query (clauses (graph el-rdf-remote-graph))
  "Query remote graph via HTTP."
  (el-rdf--run-hooks graph 'query-hooks clauses)

  (el-rdf--http-request graph "/query"
                        `(:graph ,(remote-graph-name graph)
                          :clauses ,clauses)))
```

### Step 9: Add Remote Hook Management

```elisp
(cl-defgeneric el-rdf-list-available-remote-hooks (graph)
  "List all hooks available on remote server.")

(cl-defmethod el-rdf-list-available-remote-hooks ((graph el-rdf-remote-graph))
  "List available hooks on cl-rdf server."
  (el-rdf--http-request graph "/hooks/available" nil))

(cl-defgeneric el-rdf-list-remote-hooks (graph)
  "List active hooks on remote graph.")

(cl-defmethod el-rdf-list-remote-hooks ((graph el-rdf-remote-graph))
  "List active hooks on remote cl-rdf graph."
  (el-rdf--http-request graph "/hooks"
                        `(:graph ,(remote-graph-name graph))))

(cl-defgeneric el-rdf-enable-remote-hook (graph hook-type hook-name)
  "Enable a hook on remote server.")

(cl-defmethod el-rdf-enable-remote-hook ((graph el-rdf-remote-graph) hook-type hook-name)
  "Enable HOOK-NAME on remote cl-rdf server."
  (el-rdf--http-request graph "/hooks/enable"
                        `(:graph ,(remote-graph-name graph)
                          :hook-type ,hook-type
                          :hook-name ,hook-name)))

(cl-defgeneric el-rdf-disable-remote-hook (graph hook-type hook-name)
  "Disable a hook on remote server.")

(cl-defmethod el-rdf-disable-remote-hook ((graph el-rdf-remote-graph) hook-type hook-name)
  "Disable HOOK-NAME on remote cl-rdf server."
  (el-rdf--http-request graph "/hooks/disable"
                        `(:graph ,(remote-graph-name graph)
                          :hook-type ,hook-type
                          :hook-name ,hook-name)))
```

## Backward Compatibility Guarantees

1. **`(make-graph)`** - Returns EIEIO object but behaves identically
2. **All existing functions** - Work as before via generic dispatch
3. **Hook system** - Compatible, stored in EIEIO slots
4. **Checkpointing** - Works with EIEIO objects
5. **All tests** - Pass without modification

## Functions to Convert

### Core Operations
- ✓ `add-triple` → generic method
- ✓ `add-triples` → generic method
- ✓ `delete-triple` → generic method
- ✓ `delete-triples` → generic method
- ✓ `graph-query` → generic method
- ✓ `triples` → generic method
- ✓ `raw-triples` → generic method

### Query Functions
- ✓ `ask` → use generic graph-query
- ✓ `select` → use generic graph-query
- ✓ `construct` → use generic graph-query

### Hook Management
- ✓ `add-hook-to-graph` → generic method
- ✓ `remove-hook-from-graph` → generic method
- ✓ `get-graph-hooks` → generic method

### Utility Functions
- Keep as regular functions (no dispatch needed)

## Testing Strategy

### Phase 1: Ensure Existing Tests Pass
```bash
emacs -batch -l ert -l test-el-rdf.el -f ert-run-tests-batch-and-exit
```

### Phase 2: Add Remote Graph Tests
```elisp
(ert-deftest test-remote-graph-creation ()
  (let ((g (make-remote-graph "http://localhost:8080" "test")))
    (should (el-rdf-remote-graph-p g))
    (should (equal (graph-endpoint g) "http://localhost:8080"))))

(ert-deftest test-remote-add-triples ()
  :tags '(:integration :remote)
  (skip-unless (el-rdf--server-available-p "http://localhost:8080"))
  (let ((g (make-remote-graph "http://localhost:8080" "test")))
    (add-triples '((alice friend bob)) g)
    (should (ask '((alice friend bob)) g))))
```

## Dependencies Update

Update Package-Requires in el-rdf.el:

```elisp
;; Before:
;; Package-Requires: ((emacs "27.1")(request)(dash "20250312.1307"))

;; After:
;; Package-Requires: ((emacs "27.1")(plz "0.7")(dash "20250312.1307"))
```

## Implementation Order

1. ✓ Create EIEIO classes (no breaking changes)
2. ✓ Update make-graph to return EIEIO
3. ✓ Convert core functions to methods one-by-one
4. ✓ Test after each conversion
5. ✓ Add remote graph class
6. ✓ Add HTTP client
7. ✓ Add remote methods
8. ✓ Add hook management API
9. ✓ Integration testing
10. ✓ Documentation

## Risk Mitigation

- **Incremental changes** - One function at a time
- **Test after each step** - Catch regressions early
- **Keep old code** - Comment out, don't delete immediately
- **Git commits** - Small, atomic commits for easy rollback

## Success Criteria

- [ ] All existing tests pass
- [ ] `(make-graph)` returns EIEIO object
- [ ] Local graph operations work identically
- [ ] Remote graph can connect to cl-rdf server
- [ ] Remote hook management works
- [ ] No performance regression
- [ ] Documentation updated
