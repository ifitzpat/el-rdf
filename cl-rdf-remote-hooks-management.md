# cl-rdf Remote Hook Management Implementation Specification

## Overview

This document specifies all changes required to cl-rdf to support remote hook management via HTTP API.

## Current State

**What cl-rdf already has:**
- Hook system: `add-hooks`, `delete-hooks`, `query-hooks` (lists of functions)
- Hook management: `add-hook-to-graph`, `remove-hook-from-graph`, `get-graph-hooks`
- One predefined hook: `checkpoint-hook` (saves to server disk)
- HTTP server with S-expression API: `/add`, `/delete`, `/query`, `/triples`

**What's missing:**
- Hooks are function objects with no symbolic names
- No registry of available hooks
- No way to enable/disable hooks by name over HTTP
- No HTTP endpoints for hook management

## Required Changes

### 1. Hook Registry (cl-rdf.lisp)

Add a registry that maps symbolic names to hook functions:

```lisp
;;;; Hook Registry for Remote Management

(defvar *available-hooks* (make-hash-table :test 'eq)
  "Registry of hooks available for remote enablement via HTTP API.

Maps hook name (symbol) to a plist containing:
  :function - The hook function
  :description - Human-readable description

Security:
  Only hooks explicitly registered here can be enabled remotely.
  This prevents arbitrary code execution via HTTP API.")

(defun register-hook (name function &optional description)
  "Register a hook function with a symbolic NAME.

Arguments:
  NAME - Symbolic name for the hook (e.g., 'checkpointing)
  FUNCTION - The actual hook function (must accept 3 args: graph operation data)
  DESCRIPTION - Optional human-readable description

Side Effects:
  Adds hook to *available-hooks* registry

Security:
  Only registered hooks can be enabled via HTTP API

Examples:
  (register-hook 'checkpointing #'checkpoint-hook
                 \"Automatically save graph snapshots to disk\")

  (register-hook 'audit-logging #'audit-log-hook
                 \"Log all operations to audit.log\")"
  (setf (gethash name *available-hooks*)
        (list :function function
              :description (or description ""))))

(defun get-hook-function (name)
  "Retrieve hook function by NAME from registry.

Arguments:
  NAME - Symbolic hook name

Returns:
  Hook function or NIL if not registered

Examples:
  (get-hook-function 'checkpointing) => #<FUNCTION CHECKPOINT-HOOK>"
  (let ((entry (gethash name *available-hooks*)))
    (when entry
      (getf entry :function))))

(defun list-available-hooks ()
  "List all hooks available for remote enablement.

Returns:
  Alist of (name . description) pairs

Examples:
  (list-available-hooks)
  => ((checkpointing . \"Automatically save graph snapshots\")
      (audit-logging . \"Log all operations to file\"))"
  (let ((hooks '()))
    (maphash (lambda (name entry)
               (push (cons name (getf entry :description))
                     hooks))
             *available-hooks*)
    (nreverse hooks)))

(defun find-hook-name (function)
  "Find the symbolic name of a hook FUNCTION.

Arguments:
  FUNCTION - Hook function to look up

Returns:
  Hook name (symbol) or NIL if not in registry

Note:
  This is a reverse lookup: function → name

Examples:
  (find-hook-name #'checkpoint-hook) => checkpointing
  (find-hook-name #'some-unknown-function) => NIL"
  (block find-name
    (maphash (lambda (name entry)
               (when (eq function (getf entry :function))
                 (return-from find-name name)))
             *available-hooks*)
    nil))
```

### 2. Hook Management by Name (cl-rdf.lisp)

Add functions to enable/disable hooks by symbolic name:

```lisp
;;;; Hook Management by Name

(defun enable-hook-by-name (graph hook-type hook-name)
  "Enable hook HOOK-NAME on GRAPH for HOOK-TYPE.

Arguments:
  GRAPH - Graph instance (local-graph or remote-graph)
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-NAME - Symbolic name from *available-hooks* registry

Returns:
  T if hook was enabled, NIL if hook not found in registry

Side Effects:
  Adds hook function to graph's hook list

Security:
  Only hooks registered in *available-hooks* can be enabled.
  This prevents arbitrary code execution.

Examples:
  (enable-hook-by-name my-graph 'add-hooks 'checkpointing)
  => T

  (enable-hook-by-name my-graph 'add-hooks 'unknown-hook)
  => NIL"
  (let ((hook-function (get-hook-function hook-name)))
    (if hook-function
        (progn
          (add-hook-to-graph graph hook-type hook-function)
          t)
        nil)))

(defun disable-hook-by-name (graph hook-type hook-name)
  "Disable hook HOOK-NAME on GRAPH for HOOK-TYPE.

Arguments:
  GRAPH - Graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-NAME - Symbolic hook name

Returns:
  T if hook was removed, NIL if hook not found or not active

Side Effects:
  Removes hook function from graph's hook list

Examples:
  (disable-hook-by-name my-graph 'add-hooks 'checkpointing)
  => T

  (disable-hook-by-name my-graph 'add-hooks 'not-active-hook)
  => NIL"
  (let ((hook-function (get-hook-function hook-name)))
    (if hook-function
        (progn
          (remove-hook-from-graph graph hook-type hook-function)
          t)
        nil)))

(defun get-graph-hook-names (graph hook-type)
  "Get symbolic names of active hooks on GRAPH.

Arguments:
  GRAPH - Graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks

Returns:
  List of hook names (symbols)

Note:
  Only returns names for hooks in *available-hooks* registry.
  Anonymous or unregistered hooks will not appear.

Examples:
  (get-graph-hook-names my-graph 'add-hooks)
  => (checkpointing audit-logging)

  (get-graph-hook-names my-graph 'query-hooks)
  => NIL"
  (let* ((hooks (get-graph-hooks graph hook-type))
         (names '()))
    (dolist (hook-fn hooks)
      (let ((name (find-hook-name hook-fn)))
        (when name
          (push name names))))
    (nreverse names)))

(defun hook-active-p (graph hook-type hook-name)
  "Check if hook HOOK-NAME is active on GRAPH.

Arguments:
  GRAPH - Graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-NAME - Symbolic hook name

Returns:
  T if hook is active, NIL otherwise

Examples:
  (hook-active-p my-graph 'add-hooks 'checkpointing) => T"
  (let ((hook-function (get-hook-function hook-name)))
    (when hook-function
      (member hook-function (get-graph-hooks graph hook-type)))))
```

### 3. Register Existing Hooks (cl-rdf.lisp)

Add registration calls for predefined hooks:

```lisp
;;;; Register Predefined Hooks

;; Register checkpoint hook
(register-hook 'checkpointing #'checkpoint-hook
               "Automatically save graph snapshots to disk after operations")

;; Note: Additional hooks can be registered here as they're added
```

### 4. Optional: Additional Predefined Hooks (cl-rdf.lisp)

Suggested additional hooks that could be useful:

```lisp
;;;; Additional Predefined Hooks (Optional)

(defun audit-log-hook (graph operation data)
  "Log all graph operations to audit.log file.

Arguments:
  GRAPH - Graph instance
  OPERATION - Operation symbol (e.g., 'add-triples, 'delete-triples)
  DATA - Operation data (list of triples)

Side Effects:
  Appends log entry to audit.log in checkpoint directory

Log Format:
  [timestamp] operation: N triples on graph-name"
  (let ((log-file (merge-pathnames "audit.log" (get-checkpoint-dir)))
        (graph-name (graph-name graph))
        (timestamp (get-universal-time)))
    (with-open-file (out log-file :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
      (format out "[~A] ~A: ~A triple~:P on ~A~%"
              timestamp
              operation
              (length data)
              (or graph-name "unnamed")))))

(defun validation-hook (graph operation data)
  "Validate triples before adding to graph.

Arguments:
  GRAPH - Graph instance
  OPERATION - Operation symbol
  DATA - Operation data (list of triples)

Side Effects:
  Signals error if validation fails

Validation Rules:
  - Each triple must have exactly 3 elements
  - Subject must be a symbol
  - Predicate must be a symbol
  - Object can be symbol, string, or number

Note:
  This is a simple example. Extend with your own validation rules."
  (when (eq operation 'add-triples)
    (dolist (triple data)
      (unless (= (length triple) 3)
        (error "Invalid triple length: ~A (expected 3 elements)" triple))
      (destructuring-bind (s p o) triple
        (unless (symbolp s)
          (error "Invalid subject (must be symbol): ~A" s))
        (unless (symbolp p)
          (error "Invalid predicate (must be symbol): ~A" p))))))

;; Register additional hooks
(register-hook 'audit-logging #'audit-log-hook
               "Log all operations to audit.log file")

(register-hook 'validation #'validation-hook
               "Validate triples before operations (basic checks)")
```

### 5. HTTP Endpoints (http-server.lisp)

Add four new HTTP endpoints for hook management:

```lisp
;;;; ============================================================================
;;;; Hook Management HTTP Endpoints
;;;; ============================================================================

(hunchentoot:define-easy-handler (api-list-available-hooks :uri "/hooks/available") ()
  "List all hooks available for remote enablement.

This endpoint returns the registry of hooks that can be enabled on graphs.

Request:
  POST /hooks/available
  Authorization: Bearer <token>
  (No body required)

Response (S-exp):
  (:ok ((checkpointing . \"Save graph snapshots to disk\")
        (audit-logging . \"Log operations to file\")
        (validation . \"Validate triples\")))

Errors:
  401 - Missing or invalid authentication token

Example:
  curl -X POST http://localhost:8080/hooks/available \\
       -H \"Authorization: Bearer secret-token\"

Security:
  Requires authentication
  Read-only operation (safe)"
  (unless (require-authentication)
    (return-from api-list-available-hooks
      (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (%send-success (list-available-hooks)))

(hunchentoot:define-easy-handler (api-list-hooks :uri "/hooks") ()
  "List active hooks on a specific graph.

Request body (S-exp):
  (:graph \"graph-name\")

Response (S-exp):
  (:ok (:add-hooks (checkpointing)
        :delete-hooks (checkpointing audit-logging)
        :query-hooks ()))

Errors:
  400 - Missing :graph parameter
  401 - Missing or invalid authentication
  404 - Graph not found

Example:
  curl -X POST http://localhost:8080/hooks \\
       -H \"Authorization: Bearer secret-token\" \\
       -H \"Content-Type: application/sexp\" \\
       -d '(:graph \"my-knowledge-base\")'

Security:
  Requires authentication
  Read-only operation (safe)"
  (unless (require-authentication)
    (return-from api-list-hooks
      (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let* ((request (%parse-request-body))
         (graph-name (getf request :graph))
         (graph (%get-graph-from-registry graph-name)))

    (cond
      ((null graph-name)
       (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
      ((null graph)
       (%send-error (format nil "Graph '~A' not found" graph-name)
                    hunchentoot:+http-not-found+))
      (t
       (%send-success `(:add-hooks ,(get-graph-hook-names graph 'add-hooks)
                        :delete-hooks ,(get-graph-hook-names graph 'delete-hooks)
                        :query-hooks ,(get-graph-hook-names graph 'query-hooks)))))))

(hunchentoot:define-easy-handler (api-enable-hook :uri "/hooks/enable") ()
  "Enable a hook on a graph.

Request body (S-exp):
  (:graph \"graph-name\"
   :hook-type add-hooks
   :hook-name checkpointing)

Response (S-exp):
  (:ok (:enabled checkpointing :on add-hooks))

Errors:
  400 - Missing required parameters or invalid hook-type
  401 - Missing or invalid authentication
  404 - Graph not found

Note:
  If hook is already enabled, this is idempotent (succeeds silently)

Example:
  curl -X POST http://localhost:8080/hooks/enable \\
       -H \"Authorization: Bearer secret-token\" \\
       -H \"Content-Type: application/sexp\" \\
       -d '(:graph \"my-graph\" :hook-type add-hooks :hook-name checkpointing)'

Security:
  Requires authentication
  Only whitelisted hooks (from *available-hooks*) can be enabled
  Cannot execute arbitrary code"
  (unless (require-authentication)
    (return-from api-enable-hook
      (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let* ((request (%parse-request-body))
         (graph-name (getf request :graph))
         (hook-type (getf request :hook-type))
         (hook-name (getf request :hook-name))
         (graph (%get-graph-from-registry graph-name)))

    (cond
      ((null graph-name)
       (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
      ((null hook-type)
       (%send-error "Missing :hook-type parameter" hunchentoot:+http-bad-request+))
      ((null hook-name)
       (%send-error "Missing :hook-name parameter" hunchentoot:+http-bad-request+))
      ((null graph)
       (%send-error (format nil "Graph '~A' not found" graph-name)
                    hunchentoot:+http-not-found+))
      ((not (member hook-type '(add-hooks delete-hooks query-hooks)))
       (%send-error (format nil "Invalid hook-type: ~A (must be add-hooks, delete-hooks, or query-hooks)" hook-type)
                    hunchentoot:+http-bad-request+))
      (t
       (if (enable-hook-by-name graph hook-type hook-name)
           (%send-success `(:enabled ,hook-name :on ,hook-type))
           (%send-error (format nil "Hook '~A' not available (not in registry)" hook-name)
                        hunchentoot:+http-bad-request+))))))

(hunchentoot:define-easy-handler (api-disable-hook :uri "/hooks/disable") ()
  "Disable a hook on a graph.

Request body (S-exp):
  (:graph \"graph-name\"
   :hook-type add-hooks
   :hook-name checkpointing)

Response (S-exp):
  (:ok (:disabled checkpointing :from add-hooks))

Errors:
  400 - Missing required parameters or invalid hook-type
  401 - Missing or invalid authentication
  404 - Graph not found

Note:
  If hook is already disabled, this is idempotent (succeeds silently)

Example:
  curl -X POST http://localhost:8080/hooks/disable \\
       -H \"Authorization: Bearer secret-token\" \\
       -H \"Content-Type: application/sexp\" \\
       -d '(:graph \"my-graph\" :hook-type add-hooks :hook-name checkpointing)'

Security:
  Requires authentication"
  (unless (require-authentication)
    (return-from api-disable-hook
      (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let* ((request (%parse-request-body))
         (graph-name (getf request :graph))
         (hook-type (getf request :hook-type))
         (hook-name (getf request :hook-name))
         (graph (%get-graph-from-registry graph-name)))

    (cond
      ((null graph-name)
       (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
      ((null hook-type)
       (%send-error "Missing :hook-type parameter" hunchentoot:+http-bad-request+))
      ((null hook-name)
       (%send-error "Missing :hook-name parameter" hunchentoot:+http-bad-request+))
      ((null graph)
       (%send-error (format nil "Graph '~A' not found" graph-name)
                    hunchentoot:+http-not-found+))
      ((not (member hook-type '(add-hooks delete-hooks query-hooks)))
       (%send-error (format nil "Invalid hook-type: ~A (must be add-hooks, delete-hooks, or query-hooks)" hook-type)
                    hunchentoot:+http-bad-request+))
      (t
       (if (disable-hook-by-name graph hook-type hook-name)
           (%send-success `(:disabled ,hook-name :from ,hook-type))
           (%send-error (format nil "Hook '~A' not found or not active" hook-name)
                        hunchentoot:+http-bad-request+))))))
```

## API Reference

### S-expression Protocol

All endpoints use S-expressions for request/response bodies.

**Content-Type:** `application/sexp`

### Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/hooks/available` | POST | List all registered hooks | Yes |
| `/hooks` | POST | List active hooks on graph | Yes |
| `/hooks/enable` | POST | Enable hook on graph | Yes |
| `/hooks/disable` | POST | Disable hook on graph | Yes |

### Examples

#### 1. List Available Hooks

**Request:**
```lisp
POST /hooks/available HTTP/1.1
Authorization: Bearer my-secret-token
```

**Response:**
```lisp
(:ok ((checkpointing . "Automatically save graph snapshots to disk")
      (audit-logging . "Log all operations to audit.log file")
      (validation . "Validate triples before operations")))
```

#### 2. Enable Checkpointing Hook

**Request:**
```lisp
POST /hooks/enable HTTP/1.1
Authorization: Bearer my-secret-token
Content-Type: application/sexp

(:graph "knowledge-base"
 :hook-type add-hooks
 :hook-name checkpointing)
```

**Response:**
```lisp
(:ok (:enabled checkpointing :on add-hooks))
```

#### 3. List Active Hooks

**Request:**
```lisp
POST /hooks HTTP/1.1
Authorization: Bearer my-secret-token
Content-Type: application/sexp

(:graph "knowledge-base")
```

**Response:**
```lisp
(:ok (:add-hooks (checkpointing audit-logging)
      :delete-hooks (checkpointing)
      :query-hooks ()))
```

#### 4. Disable Hook

**Request:**
```lisp
POST /hooks/disable HTTP/1.1
Authorization: Bearer my-secret-token
Content-Type: application/sexp

(:graph "knowledge-base"
 :hook-type add-hooks
 :hook-name audit-logging)
```

**Response:**
```lisp
(:ok (:disabled audit-logging :from add-hooks))
```

## Security Considerations

### Whitelist-Only Hook Enablement

**Critical:** The `*available-hooks*` registry acts as a security whitelist.

**Safe:**
```lisp
;; Hook must be registered first
(register-hook 'checkpointing #'checkpoint-hook)

;; Can now be enabled remotely
(enable-hook-by-name graph 'add-hooks 'checkpointing) ; ✓ Works
```

**Prevented:**
```lisp
;; Unregistered hooks cannot be enabled
(enable-hook-by-name graph 'add-hooks 'malicious-hook) ; ✗ Returns NIL
```

### Never Accept Arbitrary Code

**DO NOT DO THIS:**
```lisp
;; DANGEROUS! Never allow arbitrary function execution from HTTP
(let ((hook-fn (read-from-string request-body)))
  (add-hook-to-graph graph 'add-hooks hook-fn))  ; ❌ Security hole!
```

**Safe approach (what we implement):**
```lisp
;; Only allow registered symbolic names
(let ((hook-name (getf request :hook-name)))
  (enable-hook-by-name graph 'add-hooks hook-name))  ; ✓ Safe
```

## Testing

### Unit Tests (cl-rdf-tests.lisp)

```lisp
(deftest test-hook-registry ()
  "Test hook registry functions."
  ;; Register a test hook
  (register-hook 'test-hook #'checkpoint-hook "Test hook")

  ;; Should find by name
  (is (eq (get-hook-function 'test-hook) #'checkpoint-hook))

  ;; Should find by function
  (is (eq (find-hook-name #'checkpoint-hook) 'test-hook))

  ;; Should list available hooks
  (is (member '(test-hook . "Test hook") (list-available-hooks) :test #'equal)))

(deftest test-enable-disable-by-name ()
  "Test enabling and disabling hooks by name."
  (let ((g (make-graph "test")))
    ;; Enable hook
    (is (enable-hook-by-name g 'add-hooks 'checkpointing))
    (is (member 'checkpointing (get-graph-hook-names g 'add-hooks)))

    ;; Disable hook
    (is (disable-hook-by-name g 'add-hooks 'checkpointing))
    (is (null (get-graph-hook-names g 'add-hooks)))

    ;; Try to enable non-existent hook
    (is (null (enable-hook-by-name g 'add-hooks 'non-existent)))))

(deftest test-hook-active-p ()
  "Test hook-active-p predicate."
  (let ((g (make-graph "test")))
    (is (null (hook-active-p g 'add-hooks 'checkpointing)))

    (enable-hook-by-name g 'add-hooks 'checkpointing)
    (is (hook-active-p g 'add-hooks 'checkpointing))

    (disable-hook-by-name g 'add-hooks 'checkpointing)
    (is (null (hook-active-p g 'add-hooks 'checkpointing)))))
```

### Integration Tests

```bash
# Start cl-rdf server
sbcl --eval "(ql:quickload :cl-rdf)" \
     --eval "(cl-rdf:start-server :port 8080 :token \"test-token\")" \
     --eval "(cl-rdf:register-graph-for-http \"test\" (cl-rdf:make-graph \"test\"))"

# Test available hooks
curl -X POST http://localhost:8080/hooks/available \
  -H "Authorization: Bearer test-token"

# Expected: (:ok ((checkpointing . "...") ...))

# Enable checkpointing
curl -X POST http://localhost:8080/hooks/enable \
  -H "Authorization: Bearer test-token" \
  -H "Content-Type: application/sexp" \
  -d '(:graph "test" :hook-type add-hooks :hook-name checkpointing)'

# Expected: (:ok (:enabled checkpointing :on add-hooks))

# List active hooks
curl -X POST http://localhost:8080/hooks \
  -H "Authorization: Bearer test-token" \
  -H "Content-Type: application/sexp" \
  -d '(:graph "test")'

# Expected: (:ok (:add-hooks (checkpointing) :delete-hooks () :query-hooks ()))

# Disable hook
curl -X POST http://localhost:8080/hooks/disable \
  -H "Authorization: Bearer test-token" \
  -H "Content-Type: application/sexp" \
  -d '(:graph "test" :hook-type add-hooks :hook-name checkpointing)'

# Expected: (:ok (:disabled checkpointing :from add-hooks))
```

## Implementation Checklist

### Phase 1: Hook Registry (cl-rdf.lisp)
- [ ] Add `*available-hooks*` hash table
- [ ] Implement `register-hook`
- [ ] Implement `get-hook-function`
- [ ] Implement `list-available-hooks`
- [ ] Implement `find-hook-name`
- [ ] Register existing `checkpoint-hook`

### Phase 2: Hook Management (cl-rdf.lisp)
- [ ] Implement `enable-hook-by-name`
- [ ] Implement `disable-hook-by-name`
- [ ] Implement `get-graph-hook-names`
- [ ] Implement `hook-active-p`

### Phase 3: HTTP Endpoints (http-server.lisp)
- [ ] Implement `POST /hooks/available`
- [ ] Implement `POST /hooks`
- [ ] Implement `POST /hooks/enable`
- [ ] Implement `POST /hooks/disable`

### Phase 4: Additional Hooks (Optional)
- [ ] Implement `audit-log-hook`
- [ ] Implement `validation-hook`
- [ ] Register additional hooks

### Phase 5: Testing
- [ ] Unit tests for hook registry
- [ ] Unit tests for enable/disable by name
- [ ] Integration tests for HTTP endpoints
- [ ] Security tests (whitelist enforcement)

### Phase 6: Documentation
- [ ] Update cl-rdf README with hook management examples
- [ ] Document available hooks
- [ ] Add API reference to documentation

## Future Enhancements

### Hook Configuration

Add support for hook-specific configuration:

```lisp
(defvar *hook-configs* (make-hash-table :test 'equal)
  "Configuration storage for hooks.")

(defun enable-hook-by-name (graph hook-type hook-name &optional config)
  "Enable hook with optional CONFIG alist."
  (when config
    (setf (gethash (cons graph hook-name) *hook-configs*) config))
  ...)

;; Example usage:
(:graph "my-graph"
 :hook-type add-hooks
 :hook-name checkpointing
 :config ((:interval . 300)           ; Checkpoint every 5 minutes
          (:keep-count . 10)           ; Keep 10 snapshots
          (:compression . t)))         ; Compress checkpoint files
```

### Hook Status and Metrics

Add endpoint to view hook execution statistics:

```lisp
POST /hooks/stats
Body: (:graph "my-graph")

Response:
(:ok (:checkpointing (:executions 42
                      :last-execution 3825811200
                      :total-time-ms 1234)))
```

### Custom Hook Upload (Advanced)

For development environments, allow uploading custom hooks:

```lisp
POST /hooks/upload
Body: (:name my-custom-hook
       :code "(defun my-custom-hook (graph op data) ...)")

Note: This would require sandboxing and should NEVER be enabled in production.
```

## Summary

This specification adds complete remote hook management to cl-rdf:

1. **Hook Registry** - Maps names to functions, provides whitelist security
2. **Name-based Management** - Enable/disable hooks by symbolic name
3. **HTTP API** - Four endpoints for complete hook CRUD operations
4. **Security** - Whitelist prevents arbitrary code execution
5. **Extensibility** - Easy to add new predefined hooks

All changes are backward compatible. Existing hook usage continues to work unchanged.
