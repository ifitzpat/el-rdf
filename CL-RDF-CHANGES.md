# Required Changes to cl-rdf for Remote Hook Management

## Summary

Besides the new HTTP endpoints, cl-rdf needs **infrastructure for hook management by name**.

## Current Situation

**What cl-rdf has:**
- Hook system: `add-hooks`, `delete-hooks`, `query-hooks` (lists of functions)
- Functions: `add-hook-to-graph`, `remove-hook-from-graph`, `get-graph-hooks`
- One predefined hook: `checkpoint-hook`
- Hooks are **function objects** in lists

**The problem:**
- HTTP API needs to reference hooks **by name** (e.g., `'checkpointing`)
- Currently no mapping: name ↔ function
- Can't identify which hook is which from a list of function objects

## Required Changes

### 1. Hook Registry (Whitelist)

**Add to cl-rdf.lisp:**

```lisp
(defvar *available-hooks* (make-hash-table :test 'eq)
  "Registry of available hooks that can be enabled via HTTP API.
Maps hook name (symbol) to hook function.

Security: Only hooks in this registry can be enabled remotely.")

(defun register-hook (name function &optional description)
  "Register a hook function with a symbolic NAME.

Arguments:
  NAME - Symbolic name for the hook (e.g., 'checkpointing)
  FUNCTION - The actual hook function
  DESCRIPTION - Optional documentation string

Examples:
  (register-hook 'checkpointing #'checkpoint-hook
                 \"Automatically save graph snapshots\")"
  (setf (gethash name *available-hooks*)
        (list :function function :description description)))

(defun get-hook-function (name)
  "Get hook function by NAME from registry.

Returns:
  Hook function or NIL if not found"
  (let ((entry (gethash name *available-hooks*)))
    (when entry
      (getf entry :function))))

(defun list-available-hooks ()
  "List all hooks available for remote enablement.

Returns:
  Alist of (name . description)"
  (let ((hooks '()))
    (maphash (lambda (name entry)
               (push (cons name (getf entry :description))
                     hooks))
             *available-hooks*)
    (nreverse hooks)))

;; Register predefined hooks
(register-hook 'checkpointing #'checkpoint-hook
               "Automatically save graph snapshots to disk")
```

**Why needed:** HTTP API must reference hooks by name (`'checkpointing`), not by function object reference.

### 2. Hook Identification in Graphs

**Problem:** When listing active hooks on a graph, we get a list of function objects:
```lisp
(graph-add-hooks graph) => (#<FUNCTION CHECKPOINT-HOOK> #<FUNCTION MY-HOOK>)
```

We need to return **names** via HTTP API.

**Solution: Reverse lookup**

```lisp
(defun find-hook-name (function)
  "Find the name of a hook FUNCTION in the registry.

Arguments:
  FUNCTION - Hook function to look up

Returns:
  Hook name (symbol) or NIL if not found

Examples:
  (find-hook-name #'checkpoint-hook) => checkpointing"
  (block find-name
    (maphash (lambda (name entry)
               (when (eq function (getf entry :function))
                 (return-from find-name name)))
             *available-hooks*)
    nil))

(defun get-graph-hook-names (graph hook-type)
  "Get names of active hooks on GRAPH for HOOK-TYPE.

Arguments:
  GRAPH - Graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks

Returns:
  List of hook names (symbols)

Examples:
  (get-graph-hook-names graph 'add-hooks) => (checkpointing audit-logging)"
  (let ((hooks (get-graph-hooks graph hook-type)))
    (mapcar #'find-hook-name hooks)))
```

**Why needed:** HTTP `/hooks` endpoint needs to return names, not function objects.

### 3. Hook Enable/Disable by Name

**Add to cl-rdf.lisp:**

```lisp
(defun enable-hook-by-name (graph hook-type hook-name)
  "Enable hook HOOK-NAME on GRAPH.

Arguments:
  GRAPH - Graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-NAME - Symbolic name from *available-hooks*

Returns:
  T if enabled, NIL if hook not found

Side Effects:
  Adds hook function to graph

Security:
  Only allows hooks registered in *available-hooks*

Examples:
  (enable-hook-by-name graph 'add-hooks 'checkpointing)"
  (let ((hook-function (get-hook-function hook-name)))
    (if hook-function
        (progn
          (add-hook-to-graph graph hook-type hook-function)
          t)
        nil)))

(defun disable-hook-by-name (graph hook-type hook-name)
  "Disable hook HOOK-NAME on GRAPH.

Arguments:
  GRAPH - Graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-NAME - Symbolic name

Returns:
  T if disabled, NIL if hook not found or not active

Examples:
  (disable-hook-by-name graph 'add-hooks 'checkpointing)"
  (let ((hook-function (get-hook-function hook-name)))
    (if hook-function
        (progn
          (remove-hook-from-graph graph hook-type hook-function)
          t)
        nil)))
```

**Why needed:** HTTP endpoints need these functions to enable/disable hooks by name.

### 4. HTTP Endpoints

**Add to http-server.lisp:**

```lisp
;;;; Hook Management Endpoints

(hunchentoot:define-easy-handler (api-list-available-hooks :uri "/hooks/available") ()
  "List all hooks available for remote enablement.

Response (S-exp):
  (:ok ((checkpointing . \"Automatically save graph snapshots\")
        (audit-logging . \"Log all operations to file\")))"
  (unless (require-authentication)
    (return-from api-list-available-hooks
      (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (%send-success (list-available-hooks)))

(hunchentoot:define-easy-handler (api-list-hooks :uri "/hooks") ()
  "List active hooks on a graph.

Request body (S-exp):
  (:graph \"graph-name\")

Response (S-exp):
  (:ok (:add-hooks (checkpointing)
        :delete-hooks (checkpointing audit-logging)
        :query-hooks ()))"
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
  (:ok (:enabled checkpointing :on add-hooks))"
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
       (%send-error (format nil "Invalid hook-type: ~A" hook-type)
                    hunchentoot:+http-bad-request+))
      (t
       (if (enable-hook-by-name graph hook-type hook-name)
           (%send-success `(:enabled ,hook-name :on ,hook-type))
           (%send-error (format nil "Hook not available: ~A" hook-name)
                        hunchentoot:+http-bad-request+))))))

(hunchentoot:define-easy-handler (api-disable-hook :uri "/hooks/disable") ()
  "Disable a hook on a graph.

Request body (S-exp):
  (:graph \"graph-name\"
   :hook-type add-hooks
   :hook-name checkpointing)

Response (S-exp):
  (:ok (:disabled checkpointing :from add-hooks))"
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
       (%send-error (format nil "Invalid hook-type: ~A" hook-type)
                    hunchentoot:+http-bad-request+))
      (t
       (if (disable-hook-by-name graph hook-type hook-name)
           (%send-success `(:disabled ,hook-name :from ,hook-type))
           (%send-error (format nil "Hook not found or not active: ~A" hook-name)
                        hunchentoot:+http-bad-request+))))))
```

### 5. Additional Predefined Hooks (Optional)

Currently only `checkpoint-hook` exists. Consider adding:

```lisp
(defun audit-log-hook (graph operation data)
  "Log all operations to audit file."
  (let ((log-file (merge-pathnames "audit.log" (get-checkpoint-dir))))
    (with-open-file (out log-file :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
      (format out "[~A] ~A: ~A triples~%"
              (get-universal-time)
              operation
              (length data)))))

(register-hook 'audit-logging #'audit-log-hook
               "Log all operations to audit.log file")

(defun validation-hook (graph operation data)
  "Validate triples before adding (example)."
  (when (eq operation 'add-triples)
    (dolist (triple data)
      (unless (= (length triple) 3)
        (error "Invalid triple: ~A" triple)))))

(register-hook 'validation #'validation-hook
               "Validate triples before operations")
```

## Summary of Changes

### cl-rdf.lisp additions:
1. `*available-hooks*` hash table
2. `register-hook` function
3. `get-hook-function` function
4. `list-available-hooks` function
5. `find-hook-name` function
6. `get-graph-hook-names` function
7. `enable-hook-by-name` function
8. `disable-hook-by-name` function
9. Call `(register-hook 'checkpointing #'checkpoint-hook ...)` on startup
10. (Optional) Additional predefined hooks

### http-server.lisp additions:
1. `POST /hooks/available` endpoint
2. `POST /hooks` endpoint
3. `POST /hooks/enable` endpoint
4. `POST /hooks/disable` endpoint

## Security Considerations

**Critical:** Only whitelisted hooks can be enabled remotely.

The `*available-hooks*` registry acts as a whitelist. Hooks must be explicitly registered with `register-hook` before they can be enabled via HTTP API.

**Safe:**
```lisp
;; Only registered hooks work
(register-hook 'checkpointing #'checkpoint-hook)
(enable-hook-by-name graph 'add-hooks 'checkpointing) ; ✓ Works
(enable-hook-by-name graph 'add-hooks 'malicious) ; ✗ Fails
```

**Do NOT:**
```lisp
;; NEVER allow arbitrary function names from HTTP requests
(let ((hook-fn (read-from-string request-body)))  ; DANGEROUS!
  (add-hook-to-graph graph 'add-hooks hook-fn))
```

## Testing

**Test hook registry:**
```lisp
(register-hook 'checkpointing #'checkpoint-hook "Test hook")
(get-hook-function 'checkpointing) ; => #<FUNCTION CHECKPOINT-HOOK>
(find-hook-name #'checkpoint-hook) ; => CHECKPOINTING
(list-available-hooks) ; => ((CHECKPOINTING . "Test hook"))
```

**Test enable/disable:**
```lisp
(let ((g (make-graph "test")))
  (enable-hook-by-name g 'add-hooks 'checkpointing)
  (get-graph-hook-names g 'add-hooks) ; => (CHECKPOINTING)
  (disable-hook-by-name g 'add-hooks 'checkpointing)
  (get-graph-hook-names g 'add-hooks)) ; => NIL
```

**Test HTTP endpoints:**
```bash
# List available hooks
curl -X POST http://localhost:8080/hooks/available \
  -H "Authorization: Bearer token"

# Enable checkpointing
curl -X POST http://localhost:8080/hooks/enable \
  -H "Authorization: Bearer token" \
  -H "Content-Type: application/sexp" \
  -d '(:graph "my-graph" :hook-type add-hooks :hook-name checkpointing)'

# List active hooks
curl -X POST http://localhost:8080/hooks \
  -H "Authorization: Bearer token" \
  -H "Content-Type: application/sexp" \
  -d '(:graph "my-graph")'
```

## Hook Configuration (Future Enhancement)

Currently hooks have no configuration parameters. Future enhancement:

```lisp
(defvar *hook-configs* (make-hash-table :test 'eq)
  "Hook configuration storage")

(defun enable-hook-by-name (graph hook-type hook-name &optional config)
  "Enable hook with optional CONFIG alist."
  (when config
    (setf (gethash (cons graph hook-name) *hook-configs*) config))
  ...)

;; Then hooks could read their config:
(defun checkpoint-hook (graph operation data)
  (let* ((config (gethash (cons graph 'checkpointing) *hook-configs*))
         (interval (cdr (assoc :interval config))))
    ;; Use interval to decide whether to checkpoint
    ...))
```

This would allow:
```lisp
(:graph "my-graph"
 :hook-type add-hooks
 :hook-name checkpointing
 :config ((:interval . 300) (:keep-count . 10)))
```

But this can be added later. Start with simple enable/disable.
