# Remote Graph Architecture Design

## Overview

This document outlines the design for supporting remote graph operations (HTTP API, WebSocket, REPL) while maintaining the same CRUD interface as local graphs.

## Design Decision: CLOS Generic Functions

**Chosen approach:** Use CLOS (Common Lisp Object System) generic functions with method specialization.

### Why Generics?

1. **Idiomatic Common Lisp** - CLOS multiple dispatch is the standard way to achieve polymorphism
2. **Open/Closed Principle** - Add new backends without modifying existing code
3. **Method Combination** - Use `:before`, `:after`, `:around` methods for cross-cutting concerns
4. **Natural Extension** - Follows CL's object-oriented design patterns
5. **Multiple Dispatch** - Can specialize on multiple arguments if needed

## Architecture

### Class Hierarchy

```lisp
(defclass graph ()
  ((name
    :initarg :name
    :initform nil
    :accessor graph-name
    :documentation "Optional name for graph identification")
   (add-hooks
    :initform nil
    :accessor graph-add-hooks)
   (delete-hooks
    :initform nil
    :accessor graph-delete-hooks)
   (query-hooks
    :initform nil
    :accessor graph-query-hooks))
  (:documentation "Abstract base class for all graph types"))

(defclass local-graph (graph)
  ((spo
    :initform (make-hash-table :test 'eq)
    :accessor graph-spo)
   (osp
    :initform (make-hash-table :test 'equal)
    :accessor graph-osp)
   (pos
    :initform (make-hash-table :test 'eq)
    :accessor graph-pos)
   (lock
    :initform (make-lock "graph-lock")
    :reader graph-lock))
  (:documentation "Local in-memory graph with triple indices"))

(defclass remote-graph (graph)
  ((endpoint
    :initarg :endpoint
    :accessor graph-endpoint
    :documentation "Remote endpoint URL or connection spec")
   (auth
    :initarg :auth
    :initform nil
    :accessor graph-auth
    :documentation "Authentication credentials"))
  (:documentation "Abstract base for remote graph connections"))

(defclass http-graph (remote-graph)
  ((timeout
    :initarg :timeout
    :initform 30
    :accessor graph-timeout))
  (:documentation "HTTP/REST API backed graph"))

(defclass websocket-graph (remote-graph)
  ((connection
    :accessor graph-connection
    :documentation "Active WebSocket connection"))
  (:documentation "WebSocket backed graph with persistent connection"))

(defclass repl-graph (remote-graph)
  ((swank-connection
    :accessor graph-swank-connection
    :documentation "Swank/SLIME connection"))
  (:documentation "Remote REPL backed graph via Swank protocol"))
```

### Generic Function Definitions

```lisp
;;; Core CRUD operations

(defgeneric add-triple (triple graph)
  (:documentation "Add a single triple to GRAPH"))

(defgeneric add-triples (triplist graph)
  (:documentation "Add multiple triples to GRAPH"))

(defgeneric delete-triple (triple graph)
  (:documentation "Delete a single triple from GRAPH"))

(defgeneric delete-triples (triplist graph)
  (:documentation "Delete multiple triples from GRAPH"))

(defgeneric triples (pattern graph &key resolve-content)
  (:documentation "Query triples matching PATTERN from GRAPH"))

(defgeneric raw-triples (pattern graph)
  (:documentation "Query triples without resolving content references"))

;;; Hook management

(defgeneric add-hook-to-graph (graph hook-type hook-function)
  (:documentation "Add hook to GRAPH"))

(defgeneric remove-hook-from-graph (graph hook-type hook-function)
  (:documentation "Remove hook from GRAPH"))

(defgeneric get-graph-hooks (graph hook-type)
  (:documentation "Get hooks from GRAPH"))
```

### Method Implementations

#### Local Graph (Current Implementation)

```lisp
(defmethod add-triple (triple (graph local-graph))
  "Local implementation - updates hash tables with mutex protection"
  (with-lock-held ((graph-lock graph))
    ;; Current implementation
    ...))

(defmethod add-triples (triplist (graph local-graph))
  "Local implementation with threading for 100+ triples"
  ;; Current implementation with threading
  ...)
```

#### HTTP Graph

```lisp
(defmethod add-triple (triple (graph http-graph))
  "Send triple to remote HTTP endpoint"
  (dex:post (format nil "~A/triples" (graph-endpoint graph))
            :content (encode-triple-json triple)
            :headers (auth-headers graph)))

(defmethod add-triples (triplist (graph http-graph))
  "Batch send triples to remote HTTP endpoint"
  (dex:post (format nil "~A/triples/batch" (graph-endpoint graph))
            :content (encode-triples-json triplist)
            :headers (auth-headers graph)))

(defmethod triples (pattern (graph http-graph) &key (resolve-content t))
  "Query remote HTTP endpoint"
  (let ((response (dex:get (format nil "~A/query" (graph-endpoint graph))
                           :params `(("pattern" . ,(encode-pattern pattern))
                                    ("resolve" . ,(if resolve-content "true" "false")))
                           :headers (auth-headers graph))))
    (decode-triples-json response)))
```

#### WebSocket Graph

```lisp
(defmethod add-triple (triple (graph websocket-graph))
  "Send triple over WebSocket connection"
  (websocket-send (graph-connection graph)
                  (encode-message :add-triple triple)))

(defmethod triples (pattern (graph websocket-graph) &key (resolve-content t))
  "Query via WebSocket with async response"
  (let ((request-id (generate-uuid)))
    (websocket-send (graph-connection graph)
                    (encode-message :query pattern
                                  :request-id request-id
                                  :resolve resolve-content))
    (await-response request-id)))
```

#### REPL Graph

```lisp
(defmethod add-triple (triple (graph repl-graph))
  "Execute add-triple on remote REPL"
  (swank:eval-in-emacs
    `(add-triple ',triple ,(graph-name graph))
    (graph-swank-connection graph)))
```

## Migration Strategy

### Phase 1: Refactor Current Code to Use Generics

1. **Change function definitions to generic functions**
   ```lisp
   ;; Before
   (defun add-triple (triple graph) ...)

   ;; After
   (defgeneric add-triple (triple graph))
   (defmethod add-triple (triple (graph local-graph)) ...)
   ```

2. **Rename current `graph` class to `local-graph`**
   ```lisp
   ;; Update class definition
   (defclass local-graph (graph) ...)

   ;; Update make-graph to return local-graph
   (defun make-graph (&key name)
     (make-instance 'local-graph :name name))
   ```

3. **Add abstract `graph` base class** with common slots (hooks, name)

4. **All existing tests continue to work** (backwards compatible)

### Phase 2: Add Remote Graph Support

1. **Implement `http-graph` class and methods**
   - Dependency: `dexador` (HTTP client)
   - Server implementation: Hunchentoot or Clack

2. **Implement `websocket-graph` class and methods**
   - Dependency: `websocket-driver`
   - Async message handling

3. **Implement `repl-graph` class and methods**
   - Dependency: `swank` (already used by SLIME/SLY)
   - Remote evaluation protocol

### Phase 3: Add Remote-Specific Features

1. **Caching layer for remote graphs**
   ```lisp
   (defclass cached-remote-graph (remote-graph)
     ((cache
       :initform (make-hash-table :test 'equal)
       :accessor graph-cache)))

   (defmethod triples :around (pattern (graph cached-remote-graph) &key resolve-content)
     (or (gethash pattern (graph-cache graph))
         (setf (gethash pattern (graph-cache graph))
               (call-next-method))))
   ```

2. **Connection pooling for HTTP**

3. **Retry logic and error handling**
   ```lisp
   (defmethod add-triple :around (triple (graph remote-graph))
     (with-retry (3)
       (call-next-method)))
   ```

4. **Batch optimization**
   - Automatically batch small operations for remote graphs
   - Use `:around` methods to collect and batch

## Usage Examples

### Local Graph (Current)

```lisp
(defvar *g* (make-graph :name "my-data"))
(add-triple '(John schema@name "John Doe") *g*)
(triples '(John t t) *g*)
```

### HTTP Graph

```lisp
(defvar *remote* (make-instance 'http-graph
                                :endpoint "https://api.example.com/graph"
                                :auth '(:bearer "token123")))
(add-triple '(John schema@name "John Doe") *remote*)
(triples '(John t t) *remote*)
```

### WebSocket Graph

```lisp
(defvar *ws* (make-instance 'websocket-graph
                           :endpoint "wss://example.com/graph"
                           :auth '(:bearer "token123")))
(websocket-connect *ws*)  ; Establish connection
(add-triple '(John schema@name "John Doe") *ws*)
(triples '(John t t) *ws*)
```

### REPL Graph

```lisp
(defvar *repl* (make-instance 'repl-graph
                             :endpoint "localhost:4005"
                             :name '*server-graph*))
(add-triple '(John schema@name "John Doe") *repl*)
(triples '(John t t) *repl*)
```

## Benefits of This Approach

1. **Same API** - User code doesn't change, just instantiate different graph type
2. **Composable** - Can wrap graphs in caching, logging, etc. using `:around` methods
3. **Testable** - Can create mock graph classes for testing
4. **Extensible** - New backend types don't require changes to existing code
5. **Performance** - Can optimize per-backend (e.g., batch HTTP, streaming WebSocket)

## Threading Considerations

- **Local graphs**: Need mutex for thread safety (current implementation)
- **Remote graphs**: No local mutex needed (server handles concurrency)
- **Caching layer**: Would need its own cache mutex if enabled

## Error Handling

```lisp
(define-condition graph-error (error) ())
(define-condition remote-graph-error (graph-error) ())
(define-condition connection-error (remote-graph-error) ())
(define-condition timeout-error (remote-graph-error) ())

(defmethod add-triple :around (triple (graph remote-graph))
  (handler-case (call-next-method)
    (dex:http-request-failed (e)
      (error 'connection-error :message (format nil "Failed to add triple: ~A" e)))))
```

## Server-Side Implementation

For HTTP backend, example Hunchentoot server:

```lisp
(defvar *server-graph* (make-graph :name "server"))

(hunchentoot:define-easy-handler (add-triple-endpoint :uri "/triples")
    ()
  (setf (hunchentoot:content-type*) "application/json")
  (let ((triple (decode-triple-json (hunchentoot:raw-post-data :force-text t))))
    (add-triple triple *server-graph*)
    (encode-json '(:status "ok"))))

(hunchentoot:define-easy-handler (query-endpoint :uri "/query")
    (pattern resolve)
  (setf (hunchentoot:content-type*) "application/json")
  (let ((triples (triples (decode-pattern pattern) *server-graph*
                         :resolve-content (string= resolve "true"))))
    (encode-triples-json triples)))
```

## Future Extensions

1. **GraphQL interface** - Add `graphql-graph` class
2. **SPARQL endpoint** - Add `sparql-graph` class
3. **Federated queries** - Query across multiple graphs
4. **Pub/Sub** - Use hooks to publish changes to subscribers
5. **Conflict resolution** - For distributed graphs

## Dependencies

- **dexador** - HTTP client (HTTP graphs)
- **websocket-driver** - WebSocket support
- **hunchentoot** or **clack** - HTTP server
- **cl-json** or **jonathan** - JSON encoding/decoding
- **swank** - REPL connections (already available with SLIME)

## Implementation Priority

1. ✅ Phase 1: Refactor to generics (can be done now)
2. Phase 2: HTTP graph (most common use case)
3. Phase 3: WebSocket graph (for real-time updates)
4. Phase 4: REPL graph (for development/debugging)

---

**Note**: This design maintains 100% backward compatibility. Existing code continues to work unchanged. New remote graph types are opt-in by instantiating different graph classes.
