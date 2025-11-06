# el-rdf Remote Graph Architecture

## Overview

This document describes the architecture for el-rdf remote graph support, connecting to **cl-rdf HTTP servers** (not generic SPARQL endpoints).

## Key Discovery: cl-rdf Already Exists

The cl-rdf Common Lisp port already implements:

1. **CLOS Generic Functions** - All graph operations use methods:
   - `(defmethod add-triples (triples (graph local-graph)) ...)`
   - `(defmethod add-triples (triples (graph remote-graph)) ...)`

2. **HTTP Server** (Hunchentoot-based) with endpoints:
   - `POST /health` - Health check
   - `POST /triples` - Query triples by pattern
   - `POST /add` - Add triples
   - `POST /delete` - Delete triples
   - `POST /query` - Execute graph-query
   - **Uses S-expressions** (not JSON/SPARQL)

3. **Hook System** - Hooks run **on the cl-rdf server**:
   - `add-hooks` - Called after add-triples on server
   - `delete-hooks` - Called after delete-triples on server
   - `query-hooks` - Called during queries on server
   - Example: `checkpoint-hook` saves graph to **server disk**

## Two-System Architecture

```
┌─────────────────────────────────────┐
│  Emacs (el-rdf)                     │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ el-rdf-local-graph (EIEIO)    │ │
│  │  - In-memory hash tables      │ │
│  │  - Client-side hooks          │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ el-rdf-remote-graph (EIEIO)   │ │
│  │  - HTTP client                │ │
│  │  - Client-side hooks (LLM)    │ │
│  │  - Manages server-side hooks  │ │
│  └───────────────────────────────┘ │
│             │                       │
└─────────────┼───────────────────────┘
              │ HTTP (S-expressions)
              ▼
┌─────────────────────────────────────┐
│  Common Lisp (cl-rdf)               │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ local-graph (CLOS)            │ │
│  │  - In-memory hash tables      │ │
│  │  - Server-side hooks          │ │
│  │  - Checkpointing to disk      │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ HTTP Server (Hunchentoot)     │ │
│  │  - /add, /delete, /query      │ │
│  │  - /hooks (TO BE ADDED)       │ │
│  └───────────────────────────────┘ │
└─────────────────────────────────────┘
```

## Hook Architecture: Client vs Server

### Client-Side Hooks (el-rdf, Emacs)

Run **in Emacs** when el-rdf operations occur:

```elisp
;; el-rdf-remote-graph has its own hooks
(defclass el-rdf-remote-graph (el-rdf-graph)
  ((endpoint :initarg :endpoint)
   (hooks :initform '((add-hooks . nil)    ; Run in Emacs
                      (delete-hooks . nil)
                      (query-hooks . nil)))))

;; Example: LLM analysis hook runs in Emacs
(add-hook-to-graph my-remote-graph 'add-hooks
  (lambda (graph operation data)
    ;; This code executes in Emacs
    (let ((entities (call-llm-api data)))
      (message "LLM extracted: %S" entities))))
```

### Server-Side Hooks (cl-rdf, Common Lisp)

Run **on the cl-rdf server** when the server's local-graph receives operations:

```lisp
;; cl-rdf local-graph has its own hooks
(defclass local-graph (graph)
  ((add-hooks :initform nil)       ; Run on server
   (delete-hooks :initform nil)
   (query-hooks :initform nil)))

;; Example: Checkpointing hook runs on server
(add-hook-to-graph server-graph 'add-hooks #'checkpoint-hook)

(defun checkpoint-hook (graph operation data)
  ;; This code executes on cl-rdf server
  (save-graph graph (checkpoint-file-path graph-name)))
```

**Key Insight:** When el-rdf sends triples to cl-rdf:
1. el-rdf client-side hooks run **in Emacs**
2. HTTP request sent to cl-rdf server
3. cl-rdf server-side hooks run **on the server** (automatically)

## Required Changes

### 1. el-rdf: Convert to EIEIO (Option A)

**Why:** To match cl-rdf's CLOS generic function architecture.

```elisp
;; Base class
(defclass el-rdf-graph ()
  ((hooks :initform '((add-hooks . nil)
                      (delete-hooks . nil)
                      (query-hooks . nil)))
   (name :initarg :name :accessor graph-name)))

;; Local graph (current implementation)
(defclass el-rdf-local-graph (el-rdf-graph)
  ((spo :initform (make-hash-table :test 'eq))
   (osp :initform (make-hash-table :test 'eq))
   (pos :initform (make-hash-table :test 'eq))
   (prefixes :initform nil)))

;; Remote graph (connects to cl-rdf)
(defclass el-rdf-remote-graph (el-rdf-graph)
  ((endpoint :initarg :endpoint)
   (graph-name :initarg :graph-name)  ; Name of graph on server
   (token :initarg :token :initform nil)
   (timeout :initarg :timeout :initform 60)
   (cache :initform (make-hash-table :test 'equal))))

;; Generic methods dispatch automatically
(cl-defmethod add-triples (triples (graph el-rdf-local-graph))
  "Add to local in-memory graph."
  ;; Current implementation
  ...)

(cl-defmethod add-triples (triples (graph el-rdf-remote-graph))
  "Send to cl-rdf server via HTTP."
  ;; 1. Run local hooks
  (run-hooks-on-graph graph 'add-hooks triples)

  ;; 2. HTTP request (triggers server-side hooks automatically)
  (el-rdf--http-request graph "/add"
                        `(:graph ,(oref graph graph-name)
                          :triples ,triples))

  ;; Server-side hooks run automatically on cl-rdf server
  )
```

### 2. cl-rdf: Add Hook Management HTTP API

**Missing endpoints** (need to be added to cl-rdf http-server.lisp):

```lisp
;; GET /hooks?graph=my-graph
;; List hooks registered on a server-side graph
(hunchentoot:define-easy-handler (api-list-hooks :uri "/hooks") (graph)
  (unless (require-authentication)
    (return-from api-list-hooks (%send-error "Unauthorized")))

  (let ((g (%get-graph-from-registry graph)))
    (if g
        (%send-success `(:add-hooks ,(graph-add-hooks g)
                         :delete-hooks ,(graph-delete-hooks g)
                         :query-hooks ,(graph-query-hooks g)))
        (%send-error (format nil "Graph '~A' not found" graph)
                     hunchentoot:+http-not-found+))))

;; POST /hooks/enable
;; Body: (:graph "my-graph" :hook-type add-hooks :hook-name checkpointing)
;; Enable a predefined server-side hook
(hunchentoot:define-easy-handler (api-enable-hook :uri "/hooks/enable") ()
  (unless (require-authentication)
    (return-from api-enable-hook (%send-error "Unauthorized")))

  (let ((request (%parse-request-body)))
    (let* ((graph-name (getf request :graph))
           (hook-type (getf request :hook-type))
           (hook-name (getf request :hook-name))
           (graph (%get-graph-from-registry graph-name)))

      (cond
        ((null graph)
         (%send-error (format nil "Graph '~A' not found" graph-name)
                      hunchentoot:+http-not-found+))
        (t
         ;; Map hook names to actual functions
         (let ((hook-fn (cond
                          ((eq hook-name 'checkpointing) #'checkpoint-hook)
                          ;; Add more predefined hooks here
                          (t nil))))
           (if hook-fn
               (progn
                 (add-hook-to-graph graph hook-type hook-fn)
                 (%send-success `(:enabled ,hook-name :on ,hook-type)))
               (%send-error (format nil "Unknown hook: ~A" hook-name)))))))))

;; POST /hooks/disable
;; Body: (:graph "my-graph" :hook-type add-hooks :hook-name checkpointing)
;; Disable a server-side hook
(hunchentoot:define-easy-handler (api-disable-hook :uri "/hooks/disable") ()
  ;; Similar to enable, but calls remove-hook-from-graph
  ...)
```

### 3. el-rdf: Remote Hook Management API

Client-side API for managing server-side hooks:

```elisp
(cl-defmethod el-rdf-enable-remote-hook ((graph el-rdf-remote-graph) hook-type hook-name)
  "Enable HOOK-NAME on the cl-rdf server.

HOOK-NAME must be a predefined hook on the server:
  'checkpointing - Save graph snapshots to server disk
  'audit-logging - Detailed operation logs on server

These hooks run ON THE SERVER, not in Emacs."
  (el-rdf--http-request graph "/hooks/enable"
                        `(:graph ,(oref graph graph-name)
                          :hook-type ,hook-type
                          :hook-name ,hook-name)))

(cl-defmethod el-rdf-disable-remote-hook ((graph el-rdf-remote-graph) hook-type hook-name)
  "Disable HOOK-NAME on the cl-rdf server."
  (el-rdf--http-request graph "/hooks/disable"
                        `(:graph ,(oref graph graph-name)
                          :hook-type ,hook-type
                          :hook-name ,hook-name)))

(cl-defmethod el-rdf-list-remote-hooks ((graph el-rdf-remote-graph))
  "List all active hooks on the cl-rdf server."
  (el-rdf--http-request graph "/hooks"
                        `(:graph ,(oref graph graph-name))))
```

## Communication Protocol

### S-expression Format (not JSON!)

cl-rdf uses S-expressions for HTTP bodies, not JSON:

**Request:**
```lisp
POST /add HTTP/1.1
Content-Type: application/sexp

(:graph "knowledge-base"
 :triples ((alice foaf@name "Alice")
           (bob foaf@name "Bob")))
```

**Response:**
```lisp
HTTP/1.1 200 OK
Content-Type: application/sexp

(:ok (:added 2))
```

### el-rdf HTTP Client

```elisp
(defun el-rdf--http-request (graph endpoint data)
  "Make HTTP request to cl-rdf server using S-expressions."
  (let* ((url (format "%s%s" (oref graph endpoint) endpoint))
         (body (prin1-to-string data))  ; Convert to S-exp string
         (headers (when (oref graph token)
                    `(("Authorization" . ,(format "Bearer %s" (oref graph token)))))))

    (let ((response (plz 'post url
                      :headers (cons '("Content-Type" . "application/sexp") headers)
                      :body body
                      :as 'string)))

      ;; Parse S-exp response
      (let ((data (car (read-from-string response))))
        (if (eq (car data) :ok)
            (cadr data)
          (error "Server error: %S" (cadr data)))))))
```

## Usage Example

```elisp
;; Start cl-rdf server (in Common Lisp)
;; (start-server :port 8080 :token "secret")
;; (register-graph-for-http "kb" *my-graph*)

;; Create remote graph (in Emacs)
(setq remote-kb (make-instance 'el-rdf-remote-graph
                               :endpoint "http://localhost:8080"
                               :graph-name "kb"
                               :token "secret"))

;; Enable server-side checkpointing (runs on cl-rdf server)
(el-rdf-enable-remote-hook remote-kb 'add-hooks 'checkpointing)

;; Add client-side LLM hook (runs in Emacs)
(add-hook-to-graph remote-kb 'add-hooks
  (lambda (graph operation data)
    (message "Client: Analyzing %d triples with LLM" (length data))))

;; Now when we add triples:
(add-triples '((alice friend bob)
               (bob friend charlie)) remote-kb)

;; Execution flow:
;; 1. Client-side hook runs in Emacs: "Client: Analyzing 2 triples..."
;; 2. HTTP POST to cl-rdf server
;; 3. cl-rdf adds triples to its local-graph
;; 4. Server-side checkpoint-hook runs on server (saves to server disk)
;; 5. HTTP response returns to Emacs
```

## Predefined Server-Side Hooks

Hooks that can be enabled/disabled on cl-rdf server:

| Hook Name | Type | Description | Runs On |
|-----------|------|-------------|---------|
| `checkpointing` | add-hooks, delete-hooks | Save graph snapshots | Server disk |
| `audit-logging` | all | Log operations to file | Server disk |
| `validation` | add-hooks | Validate triples before adding | Server memory |
| *custom* | any | User-defined hooks | Server |

## Migration Path

### Phase 1: Refactor el-rdf to EIEIO

1. Create `el-rdf-graph` base class
2. Rename current graph to `el-rdf-local-graph`
3. Convert functions to generic methods
4. **Maintain backward compatibility:** `(make-graph)` still works

### Phase 2: Add el-rdf-remote-graph

1. Implement `el-rdf-remote-graph` class
2. Implement HTTP client methods
3. S-expression serialization/deserialization

### Phase 3: Add Hook Management to cl-rdf

1. Add `/hooks`, `/hooks/enable`, `/hooks/disable` endpoints to cl-rdf
2. Map hook names to actual functions
3. Security: Only allow predefined hooks (no arbitrary code execution)

### Phase 4: Add el-rdf Remote Hook API

1. Implement `el-rdf-enable-remote-hook`
2. Implement `el-rdf-disable-remote-hook`
3. Implement `el-rdf-list-remote-hooks`

## Security Considerations

### Server-Side Hook Safety

**DO NOT** allow arbitrary Lisp code execution via HTTP API!

**Safe approach:**
```lisp
;; Registry of allowed hooks
(defvar *allowed-hooks*
  '((checkpointing . checkpoint-hook)
    (audit-logging . audit-log-hook)))

(defun enable-hook-by-name (graph hook-type hook-name)
  (let ((hook-fn (cdr (assoc hook-name *allowed-hooks*))))
    (if hook-fn
        (add-hook-to-graph graph hook-type hook-fn)
        (error "Hook not in whitelist: ~A" hook-name))))
```

**Unsafe approach (DO NOT DO THIS):**
```lisp
;; DANGEROUS: Allows arbitrary code execution!
(let ((hook-fn (read-from-string request-body)))
  (add-hook-to-graph graph 'add-hooks hook-fn))
```

## Benefits of This Architecture

1. **Same Code** - Both el-rdf and cl-rdf use generic functions
2. **Transparent** - Client code doesn't know if graph is local or remote
3. **Flexible Hooks** - Client-side (Emacs) AND server-side (cl-rdf) hooks
4. **Type Safety** - EIEIO/CLOS method dispatch
5. **Extensible** - Can add more hook types without API changes

## Performance Considerations

| Operation | Local Graph | Remote Graph | Notes |
|-----------|-------------|--------------|-------|
| add-triple | O(1) | O(network) | HTTP round-trip |
| add-triples (bulk) | O(n) | O(network) | Single HTTP request |
| graph-query | O(index lookup) | O(network + server CPU) | Consider caching |
| Hooks (client) | Instant | Instant | Run in Emacs |
| Hooks (server) | N/A | Automatic | Run on cl-rdf |

## Differences from SPARQL Approach

This architecture **differs** from the initial SPARQL-based plan:

| Aspect | Initial Plan (SPARQL) | Actual (cl-rdf) |
|--------|----------------------|-----------------|
| Protocol | SPARQL 1.1 | Custom S-expression HTTP API |
| Endpoints | Generic SPARQL servers | cl-rdf specific |
| Query Language | SPARQL SELECT | cl-rdf graph-query |
| Data Format | JSON/XML | S-expressions |
| Server-Side Hooks | N/A | Built-in CLOS hook system |

The cl-rdf approach is **better** because:
1. Hooks are first-class (not bolted on via headers)
2. S-expressions are native (no impedance mismatch)
3. Full control over server behavior
4. Can extend both client and server

