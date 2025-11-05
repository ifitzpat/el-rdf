;;;; cl-rdf.lisp --- In-memory RDF triple store for Common Lisp

;;; This is a port of el-rdf.el from Emacs Lisp to Common Lisp.
;;; See CL-PORT-PLAN.md for the implementation plan.

(in-package #:cl-rdf)

;;; Implementation follows Test-Driven Development:
;;; 1. Write test first (in tests/cl-rdf-tests.lisp)
;;; 2. Run test (should fail)
;;; 3. Implement function
;;; 4. Run test (should pass)
;;; 5. Refactor if needed

;;; Functions are implemented in phases according to CL-PORT-PLAN.md

;;;; ============================================================================
;;;; Special Variables
;;;; ============================================================================

(defvar *debug* nil
  "Enable debug logging output. Set to T to enable debug messages.")

;;;; ============================================================================
;;;; Phase 1: Core Data Structures and Utilities
;;;; ============================================================================

;;; -----------------------------------------------------------------------------
;;; Graph Structure (CLOS-based with Generic Function Support)
;;; -----------------------------------------------------------------------------

;;; Abstract Base Class

(defclass graph ()
  ((name
    :initarg :name
    :initform nil
    :accessor graph-name
    :documentation "Optional name for graph identification and checkpointing")

   (add-hooks
    :initform nil
    :accessor graph-add-hooks
    :documentation "List of functions called after add-triples operations")

   (delete-hooks
    :initform nil
    :accessor graph-delete-hooks
    :documentation "List of functions called after delete-triples operations")

   (query-hooks
    :initform nil
    :accessor graph-query-hooks
    :documentation "List of functions called during graph-query operations")

   (prefixes
    :initform nil
    :accessor graph-prefixes
    :documentation "Association list of (prefix-string . namespace-uri) pairs for TTL import"))
  (:documentation "Abstract base class for all graph types.

This class defines the common interface and shared state for all graph
implementations. Concrete graph types inherit from this class and implement
the generic CRUD operations.

Subclasses:
  - LOCAL-GRAPH: In-memory triple-indexed storage
  - (Future) HTTP-GRAPH: Remote graph via HTTP/REST API
  - (Future) WEBSOCKET-GRAPH: Remote graph via WebSocket
  - (Future) REPL-GRAPH: Remote graph via REPL connection

See REMOTE-GRAPHS.md for architecture details."))

;;; Local In-Memory Graph

(defclass local-graph (graph)
  ((spo
    :initform (make-hash-table :test 'eq)
    :accessor graph-spo
    :documentation "Subject-Predicate-Object index: subject -> ((predicate . (obj1 obj2 ...)))")

   (osp
    :initform (make-hash-table :test 'equal)
    :accessor graph-osp
    :documentation "Object-Subject-Predicate index: object -> ((subject . (pred1 pred2 ...)))")

   (pos
    :initform (make-hash-table :test 'eq)
    :accessor graph-pos
    :documentation "Predicate-Object-Subject index: predicate -> ((object . (subj1 subj2 ...)))")

   (lock
    :initform (make-lock "graph-lock")
    :reader graph-lock
    :documentation "Mutex for thread-safe operations on graph indices"))
  (:documentation "Local in-memory RDF graph with triple-indexed storage.

The local-graph uses three hash table indices for efficient querying:
- SPO: Indexed by subject (uses EQ test for symbol keys)
- OSP: Indexed by object (uses EQUAL test for any type of keys)
- POS: Indexed by predicate (uses EQ test for symbol keys)

Supports parallel processing for bulk operations (100+ items threshold).
Thread-safe via per-graph mutex."))

(defun make-graph (&key name)
  "Create a new local in-memory RDF graph with optional NAME.

Creates a LOCAL-GRAPH instance with triple-indexed storage. This is the
standard way to create a graph for local in-memory use.

A graph is implemented as a CLOS object with three hash table indices
for efficient triple storage and retrieval. Each index provides fast
lookups for different query patterns:

- SPO (Subject-Predicate-Object): Primary index, fast subject lookups
- OSP (Object-Subject-Predicate): Fast object/value lookups (reverse queries)
- POS (Predicate-Object-Subject): Fast predicate-based queries

Arguments:
  NAME - Optional string name for graph identification and checkpointing.
         If provided, enables automatic checkpointing via
         REGISTER-GRAPH-FOR-CHECKPOINTING.

Returns:
  A new LOCAL-GRAPH object.

Examples:
  (make-graph)                    ; Anonymous local graph
  (make-graph :name \"my-data\")    ; Named local graph for checkpointing

Note: For remote graphs, directly instantiate the appropriate class:
  (make-instance 'http-graph :endpoint \"https://...\")

See also: LOCAL-GRAPH, ADD-TRIPLE, GRAPH-QUERY, REGISTER-GRAPH-FOR-CHECKPOINTING"
  (make-instance 'local-graph :name name))

;;; -----------------------------------------------------------------------------
;;; Basic Predicates
;;; -----------------------------------------------------------------------------

(defun variablep (x)
  "Return T if X is a SPARQL variable (symbol starting with $).

Variables are used in query patterns to match any value and capture bindings.
A symbol is considered a variable if its name begins with the $ character.

Arguments:
  X - Any Lisp object to test.

Returns:
  T if X is a symbol whose name starts with $, NIL otherwise.

Examples:
  (variablep '$subject)        ; => T
  (variablep '$name)           ; => T
  (variablep '$)               ; => T (just $ is a variable)
  (variablep 'schema.Person)   ; => NIL
  (variablep \"string\")         ; => NIL
  (variablep 42)               ; => NIL

See also: VAR-OR-WILDP, GRAPH-QUERY"
  (and (symbolp x)
       (let ((name (symbol-name x)))
         (and (plusp (length name))
              (char= (char name 0) #\$)))))

(defun var-or-wildp (x)
  "Return T if X is a variable or wildcard (t).

A wildcard (the symbol T) matches any value in query patterns without
binding. Variables (symbols starting with $) match any value and create
bindings. This predicate is used in pattern matching to determine if a
pattern element should match any value.

Arguments:
  X - Any Lisp object to test.

Returns:
  T if X is either the symbol T or a variable (starts with $), NIL otherwise.

Examples:
  (var-or-wildp t)              ; => T (wildcard)
  (var-or-wildp '$subject)      ; => T (variable)
  (var-or-wildp '$name)         ; => T (variable)
  (var-or-wildp 'schema.Person) ; => NIL (concrete value)
  (var-or-wildp \"string\")       ; => NIL (not a symbol)

See also: VARIABLEP, PAT-MATCH, TRIPLES"
  (or (eq x t)
      (variablep x)))

;;; -----------------------------------------------------------------------------
;;; Blank Node Generation
;;; -----------------------------------------------------------------------------

(defun bnode ()
  "Generate a unique blank node identifier.

Blank nodes are anonymous RDF resources that have no external identifier.
They are used to represent intermediate or anonymous entities in RDF graphs.
This function generates a fresh blank node symbol with the format _@G<number>,
where <number> is a unique identifier generated by GENSYM.

Note: cl-rdf uses at-sign (@) as separator instead of colon (:) used in el-rdf.
Blank nodes in cl-rdf use _@ prefix (e.g., _@G1234) instead of _: prefix.

Returns:
  A symbol representing a unique blank node, starting with _@

Examples:
  (bnode)  ; => _@G1234 (exact name varies)
  (bnode)  ; => _@G1235 (different from previous)

  ;; Use in triples
  (let ((person (bnode)))
    (add-triple g person 'a 'schema@Person)
    (add-triple g person 'schema@name \"John Doe\"))

See also: ADD-TRIPLE, IMPORT-TTL"
  (intern (concatenate 'string \"_@\" (symbol-name (gensym)))))

;;; -----------------------------------------------------------------------------
;;; Namespace Extraction
;;; -----------------------------------------------------------------------------

(defun namespace (symbol)
  "Extract the namespace portion from a namespaced symbol.

RDF resources in cl-rdf use the format namespace@resource (e.g., schema@Person).
This function extracts the namespace portion (the part before the @).

Arguments:
  SYMBOL - A symbol potentially containing a namespace.

Returns:
  A string containing the namespace if the symbol contains @, NIL otherwise.

Examples:
  (namespace 'schema@Person)  ; => \"schema\"
  (namespace 'foaf@name)      ; => \"foaf\"
  (namespace 'rdf@type)       ; => \"rdf\"
  (namespace 'Person)         ; => NIL (no namespace)
  (namespace '_@G1234)        ; => NIL (blank node, not a namespace)
  (namespace '$subject)       ; => NIL (variable, not namespaced)

See also: ADD-TRIPLE, IMPORT-TTL"
  (let* ((name (symbol-name symbol))
         (at-pos (position #\@ name)))
    (when (and at-pos (plusp at-pos))
      (subseq name 0 at-pos))))

;;;; ============================================================================
;;;; Phase 2: Triple Storage
;;;; ============================================================================

;;; -----------------------------------------------------------------------------
;;; Alist Manipulation Helpers
;;; -----------------------------------------------------------------------------

(defun update-dual (key val orig)
  "Add VAL to the list of values associated with KEY in alist ORIG.

This function maintains the triple index structure where each key maps to a
list of values. If KEY doesn't exist, a new entry is created. If KEY exists,
VAL is added to its list (unless already present). The function avoids
duplicate values.

Arguments:
  KEY  - The key to update (typically a symbol).
  VAL  - The value to add to the key's list (can be any Lisp object).
  ORIG - The original alist structure.

Returns:
  Updated alist with VAL added to KEY's list.

Structure:
  Input/Output format: ((key1 . (val1 val2 ...)) (key2 . (val3 val4 ...)) ...)

Examples:
  (update-dual 'subject '(pred . obj) nil)
  ; => ((subject . ((pred . obj))))

  (update-dual 'subject '(pred2 . obj2) '((subject . ((pred1 . obj1)))))
  ; => ((subject . ((pred2 . obj2) (pred1 . obj1))))

See also: REMOVE-DUAL, ADD-TRIPLE"
  (let* ((entry (assoc key orig))
         (oldval (cdr entry)))
    (if oldval
        ;; Key exists - add val if not already present
        (progn
          (setf (cdr entry)
                (if (member val oldval :test #'equal)
                    oldval
                    (cons val oldval)))
          orig)
        ;; Key doesn't exist - add new entry
        (append `((,key . ,(list val))) orig))))

(defun remove-dual (key val orig)
  "Remove VAL from the list of values associated with KEY in alist ORIG.

This function is the inverse of UPDATE-DUAL. It removes a specific value from
the list associated with a key. If removing the value leaves the list empty,
the entire key entry is removed from the alist.

Arguments:
  KEY  - The key to update (typically a symbol).
  VAL  - The value to remove from the key's list (can be any Lisp object).
  ORIG - The original alist structure.

Returns:
  Updated alist with VAL removed from KEY's list. If the list becomes empty,
  the KEY entry is removed entirely.

Structure:
  Input/Output format: ((key1 . (val1 val2 ...)) (key2 . (val3 val4 ...)) ...)

Examples:
  (remove-dual 'subject '(pred . obj) '((subject . ((pred . obj)))))
  ; => NIL (empty - last value removed)

  (remove-dual 'subject '(pred1 . obj1)
               '((subject . ((pred1 . obj1) (pred2 . obj2)))))
  ; => ((subject . ((pred2 . obj2))))

  (remove-dual 'nonexistent 'val '((key . (val1 val2))))
  ; => ((key . (val1 val2))) (unchanged - key not found)

See also: UPDATE-DUAL, DELETE-TRIPLE"
  (let* ((entry (assoc key orig))
         (oldvals (cdr entry)))
    (if entry
        ;; Key exists - remove the value
        (let ((newvals (remove val oldvals :test #'equal)))
          (if newvals
              ;; Still have values left - update the entry
              (progn
                (setf (cdr entry) newvals)
                orig)
              ;; No values left - remove entire key entry
              (remove entry orig :test #'equal)))
        ;; Key not found - return original unchanged
        orig)))

;;; -----------------------------------------------------------------------------
;;; Triple Operations (Generic Functions)
;;; -----------------------------------------------------------------------------

(defgeneric add-triple (triple graph)
  (:documentation "Add a single RDF triple to GRAPH.

This is the core function for adding data to the graph. Behavior depends on
the graph type:
  - LOCAL-GRAPH: Updates three hash table indices (SPO, OSP, POS)
  - HTTP-GRAPH: Sends triple to remote HTTP endpoint
  - WEBSOCKET-GRAPH: Sends triple over WebSocket connection

Arguments:
  TRIPLE - A list of three elements: (subject predicate object)
  GRAPH  - A graph object

Returns:
  NIL

Examples:
  (add-triple '(John schema@name \"John Doe\") g)
  (add-triple '(John a schema@Person) g)

See also: ADD-TRIPLES, DELETE-TRIPLE"))

(defmethod add-triple (triple (graph local-graph))
  "Add a single RDF triple to a local in-memory graph.

Updates three hash table indices (SPO, OSP, POS) to enable efficient querying
from different access patterns. The function automatically normalizes rdf@type
to 'a for storage efficiency. Thread-safe via per-graph mutex.

Side Effects:
  - Updates graph-spo hash table (subject -> ((predicate . (objects...))))
  - Updates graph-osp hash table (object -> ((subject . (predicates...))))
  - Updates graph-pos hash table (predicate -> ((object . (subjects...))))

Normalization:
  - rdf@type is automatically converted to 'a during storage"
  (let* ((subject (first triple))
         ;; Normalize rdf@type to 'a for storage efficiency
         (predicate (if (eq (second triple) 'rdf@type) 'a (second triple)))
         (object (third triple))
         (spo (graph-spo graph))
         (osp (graph-osp graph))
         (pos (graph-pos graph)))

    ;; Thread-safe update of all three indices
    (with-lock-held ((graph-lock graph))
      ;; Update SPO index: subject -> ((predicate . (objects...)))
      (let ((po (gethash subject spo)))
        (if po
            (setf (gethash subject spo) (update-dual predicate object po))
            (setf (gethash subject spo) `((,predicate . ,(list object))))))

      ;; Update OSP index: object -> ((subject . (predicates...)))
      (let ((sp (gethash object osp)))
        (if sp
            (setf (gethash object osp) (update-dual subject predicate sp))
            (setf (gethash object osp) `((,subject . ,(list predicate))))))

      ;; Update POS index: predicate -> ((object . (subjects...)))
      (let ((os (gethash predicate pos)))
        (if os
            (setf (gethash predicate pos) (update-dual object subject os))
            (setf (gethash predicate pos) `((,object . ,(list subject))))))))

  nil)

(defgeneric delete-triple (triple graph)
  (:documentation "Remove a single RDF triple from GRAPH.

Behavior depends on graph type:
  - LOCAL-GRAPH: Removes from hash table indices with cleanup
  - HTTP-GRAPH: Sends DELETE request to remote endpoint
  - WEBSOCKET-GRAPH: Sends delete message over WebSocket

Arguments:
  TRIPLE - A list of three elements: (subject predicate object)
  GRAPH  - A graph object

Returns:
  NIL

Examples:
  (delete-triple '(John schema@name \"John Doe\") g)

See also: DELETE-TRIPLES, ADD-TRIPLE"))

(defmethod delete-triple (triple (graph local-graph))
  "Remove a single RDF triple from a local in-memory graph.

This is the inverse of ADD-TRIPLE. It removes a triple from all three indices
(SPO, OSP, POS) and automatically cleans up empty entries using REMHASH when
no triples remain for a given key. Thread-safe via per-graph mutex.

Side Effects:
  - Updates graph-spo hash table (removes or updates entry)
  - Updates graph-osp hash table (removes or updates entry)
  - Updates graph-pos hash table (removes or updates entry)
  - Uses REMHASH to completely remove keys when they become empty

Normalization:
  - rdf@type is automatically converted to 'a for lookup"
  (let* ((subject (first triple))
         ;; Normalize rdf@type to 'a to match storage format
         (predicate (if (eq (second triple) 'rdf@type) 'a (second triple)))
         (object (third triple))
         (spo (graph-spo graph))
         (osp (graph-osp graph))
         (pos (graph-pos graph)))

    ;; Thread-safe update of all three indices
    (with-lock-held ((graph-lock graph))
      ;; Remove from SPO index: subject -> ((predicate . (objects...)))
      (let ((po (gethash subject spo)))
        (when po
          (let ((updated-po (remove-dual predicate object po)))
            (if updated-po
                (setf (gethash subject spo) updated-po)
                ;; No predicates left for this subject - remove entirely
                (remhash subject spo)))))

      ;; Remove from OSP index: object -> ((subject . (predicates...)))
      (let ((sp (gethash object osp)))
        (when sp
          (let ((updated-sp (remove-dual subject predicate sp)))
            (if updated-sp
                (setf (gethash object osp) updated-sp)
                ;; No subjects left for this object - remove entirely
                (remhash object osp)))))

      ;; Remove from POS index: predicate -> ((object . (subjects...)))
      (let ((os (gethash predicate pos)))
        (when os
          (let ((updated-os (remove-dual object subject os)))
            (if updated-os
                (setf (gethash predicate pos) updated-os)
                ;; No objects left for this predicate - remove entirely
                (remhash predicate pos)))))))

  nil)

;;; -----------------------------------------------------------------------------
;;; Duals Expansion
;;; -----------------------------------------------------------------------------

(defun expand-duals (duals element &optional (reorder nil))
  "Expand alist structure into list of triples.

This function converts the internal alist representation used in the triple
indices into a flat list of triples. The REORDER parameter determines the
order of elements in each triple.

For large datasets (100+ entries), this function uses parallel processing
across multiple threads to improve performance.

Arguments:
  DUALS   - Alist structure: ((key . (val1 val2 ...)) ...)
  ELEMENT - The element to include in each expanded triple
  REORDER - Optional keyword to control triple ordering:
            NIL (default) - SPO order: (element key value)
            :OSP          - OSP order: (key value element)
            :POS          - POS order: (value element key)

Returns:
  List of triples (each triple is a list of 3 elements)

Structure Transformation:
  Input:  ((key1 . (val1 val2)) (key2 . (val3)))
  Output: ((element key1 val1) (element key1 val2) (element key2 val3))

Examples:
  ;; SPO order (default)
  (expand-duals '((schema@name . (\"John\")) (schema@age . (30))) 'Person1)
  ; => ((Person1 schema@name \"John\") (Person1 schema@age 30))

  ;; OSP order
  (expand-duals '((John . (schema@name schema@age))) \"John Doe\" :osp)
  ; => ((John schema@name \"John Doe\") (John schema@age \"John Doe\"))

  ;; POS order
  (expand-duals '((schema@Person . (John Jane))) 'a :pos)
  ; => ((John a schema@Person) (Jane a schema@Person))

See also: TRIPLES, RAW-TRIPLES"
  ;; Use threading for large datasets (threshold: 100+ entries)
  (if (< (length duals) 100)
      ;; Small dataset - sequential processing
      (loop for (key . values) in duals
            nconc (loop for value in values
                        collect (ecase reorder
                                  ((nil) (list element key value))      ; SPO
                                  (:osp  (list key value element))      ; OSP
                                  (:pos  (list value element key)))))   ; POS
      ;; Large dataset - parallel processing
      (let* ((num-threads 4)  ; Use 4 threads for parallel processing
             (chunk-size (ceiling (/ (length duals) num-threads)))
             (chunks (loop for i from 0 below (length duals) by chunk-size
                           collect (subseq duals i (min (+ i chunk-size) (length duals)))))
             (results nil)
             (threads nil))
        ;; Spawn threads to process chunks in parallel
        (dolist (chunk chunks)
          (let ((c chunk)  ; Capture chunk by value
                (elem element)
                (reord reorder))
            (push (make-thread
                   (lambda ()
                     (loop for (key . values) in c
                           nconc (loop for value in values
                                       collect (ecase reord
                                                 ((nil) (list elem key value))
                                                 (:osp  (list key value elem))
                                                 (:pos  (list value elem key))))))
                   :name "expand-duals-worker")
                  threads)))
        ;; Join threads and collect results
        (dolist (thread (reverse threads))
          (push (join-thread thread) results))
        ;; Flatten results
        (apply #'append (reverse results)))))

;;; -----------------------------------------------------------------------------
;;; Bulk Triple Operations (with hooks)
;;; -----------------------------------------------------------------------------

(defgeneric add-triples (triplist graph)
  (:documentation "Add multiple RDF triples to GRAPH at once.

This is a bulk operation that triggers add-hooks after completion. Behavior
depends on graph type:
  - LOCAL-GRAPH: Parallel processing for 100+ triples, calls add-hooks
  - HTTP-GRAPH: Batch POST request to remote endpoint
  - WEBSOCKET-GRAPH: Batch send over WebSocket

Arguments:
  TRIPLIST - List of triples, where each triple is (subject predicate object)
  GRAPH    - A graph object

Returns:
  NIL

Hook Protocol:
  Each hook function receives (graph 'add-triples triplist)

Examples:
  (add-triples '((John schema@name \"John Doe\")
                 (John schema@age 30))
               g)

See also: ADD-TRIPLE, DELETE-TRIPLES"))

(defmethod add-triples (triplist (graph local-graph))
  "Add multiple RDF triples to a local in-memory graph.

Bulk operation that adds multiple triples and then triggers all registered
add-hooks. Unlike ADD-TRIPLE (which does NOT trigger hooks), ADD-TRIPLES is
the primary way to add data when hooks need to be notified.

For large datasets (100+ triples), uses parallel processing across multiple
threads to improve performance. Each ADD-TRIPLE call is thread-safe via the
graph's mutex.

Side Effects:
  - Calls ADD-TRIPLE for each triple (in parallel for 100+ triples)
  - Calls all registered add-hooks with (graph 'add-triples triplist)"
  ;; Add all triples (with threading for large datasets)
  (if (< (length triplist) 100)
      ;; Small dataset - sequential processing
      (mapc (lambda (triple) (add-triple triple graph)) triplist)
      ;; Large dataset - parallel processing
      (let* ((num-threads 4)  ; Use 4 threads for parallel processing
             (chunk-size (ceiling (/ (length triplist) num-threads)))
             (chunks (loop for i from 0 below (length triplist) by chunk-size
                           collect (subseq triplist i (min (+ i chunk-size) (length triplist)))))
             (threads nil))
        ;; Spawn threads to add triples in parallel
        (dolist (chunk chunks)
          (let ((c chunk)  ; Capture chunk by value
                (g graph))
            (push (make-thread
                   (lambda ()
                     (mapc (lambda (triple) (add-triple triple g)) c))
                   :name "add-triples-worker")
                  threads)))
        ;; Wait for all additions to complete before calling hooks
        (mapc #'join-thread threads)))

  ;; Call all add-hooks AFTER all triples are added
  (mapc (lambda (hook)
          (funcall hook graph 'add-triples triplist))
        (graph-add-hooks graph))

  nil)

(defgeneric delete-triples (triplist graph)
  (:documentation "Delete multiple RDF triples from GRAPH at once.

This is a bulk operation that triggers delete-hooks after completion. Behavior
depends on graph type:
  - LOCAL-GRAPH: Parallel processing for 100+ triples, calls delete-hooks
  - HTTP-GRAPH: Batch DELETE request to remote endpoint
  - WEBSOCKET-GRAPH: Batch delete over WebSocket

Arguments:
  TRIPLIST - List of triples, where each triple is (subject predicate object)
  GRAPH    - A graph object

Returns:
  NIL

Hook Protocol:
  Each hook function receives (graph 'delete-triples triplist)

Examples:
  (delete-triples '((John schema@name \"John Doe\")
                    (John schema@age 30))
                  g)

See also: DELETE-TRIPLE, ADD-TRIPLES"))

(defmethod delete-triples (triplist (graph local-graph))
  "Delete multiple RDF triples from a local in-memory graph.

Bulk operation that deletes multiple triples and then triggers all registered
delete-hooks. Unlike DELETE-TRIPLE (which does NOT trigger hooks), DELETE-TRIPLES
is the primary way to remove data when hooks need to be notified.

For large datasets (100+ triples), uses parallel processing across multiple
threads to improve performance. Each DELETE-TRIPLE call is thread-safe via the
graph's mutex.

Side Effects:
  - Calls DELETE-TRIPLE for each triple (in parallel for 100+ triples)
  - Calls all registered delete-hooks with (graph 'delete-triples triplist)"
  ;; Delete all triples (with threading for large datasets)
  (if (< (length triplist) 100)
      ;; Small dataset - sequential processing
      (mapc (lambda (triple) (delete-triple triple graph)) triplist)
      ;; Large dataset - parallel processing
      (let* ((num-threads 4)  ; Use 4 threads for parallel processing
             (chunk-size (ceiling (/ (length triplist) num-threads)))
             (chunks (loop for i from 0 below (length triplist) by chunk-size
                           collect (subseq triplist i (min (+ i chunk-size) (length triplist)))))
             (threads nil))
        ;; Spawn threads to delete triples in parallel
        (dolist (chunk chunks)
          (let ((c chunk)  ; Capture chunk by value
                (g graph))
            (push (make-thread
                   (lambda ()
                     (mapc (lambda (triple) (delete-triple triple g)) c))
                   :name "delete-triples-worker")
                  threads)))
        ;; Wait for all deletions to complete before calling hooks
        (mapc #'join-thread threads)))

  ;; Call all delete-hooks AFTER all triples are deleted
  (mapc (lambda (hook)
          (funcall hook graph 'delete-triples triplist))
        (graph-delete-hooks graph))

  nil)

;;; ============================================================================
;;;; Phase 3: Hook System
;;; ============================================================================

(defgeneric add-hook-to-graph (graph hook-type hook-function)
  (:documentation "Add HOOK-FUNCTION to GRAPH's hooks of HOOK-TYPE.

Works on all graph types (local and remote) since hooks are stored in the
abstract GRAPH base class.

Arguments:
  GRAPH         - A graph object
  HOOK-TYPE     - Type of hook: :add, :delete, or :query
  HOOK-FUNCTION - A function taking (graph operation data) as arguments

Returns:
  NIL

Examples:
  (add-hook-to-graph g :add
    (lambda (graph op data)
      (format t \"Added ~A triples~%\" (length data))))

See also: REMOVE-HOOK-FROM-GRAPH, GET-GRAPH-HOOKS"))

(defmethod add-hook-to-graph ((graph graph) hook-type hook-function)
  "Add HOOK-FUNCTION to GRAPH's hooks of HOOK-TYPE.

Hooks are callback functions that are triggered when certain operations occur
on the graph. This function adds a hook to the appropriate hook list, avoiding
duplicates.

Hook Types:
  :add    - Called after ADD-TRIPLES operations
  :delete - Called after DELETE-TRIPLES operations
  :query  - Called during GRAPH-QUERY operations

Hook Function Signature:
  (lambda (graph operation data) ...)

Side Effects:
  Modifies the graph's hook list for the specified type"
  (let ((hooks (ecase hook-type
                 (:add (graph-add-hooks graph))
                 (:delete (graph-delete-hooks graph))
                 (:query (graph-query-hooks graph)))))
    ;; Only add if not already present
    (unless (member hook-function hooks)
      (ecase hook-type
        (:add (setf (graph-add-hooks graph)
                    (cons hook-function (graph-add-hooks graph))))
        (:delete (setf (graph-delete-hooks graph)
                       (cons hook-function (graph-delete-hooks graph))))
        (:query (setf (graph-query-hooks graph)
                      (cons hook-function (graph-query-hooks graph)))))))
  nil)

(defgeneric remove-hook-from-graph (graph hook-type hook-function)
  (:documentation "Remove HOOK-FUNCTION from GRAPH's hooks of HOOK-TYPE.

Works on all graph types. Safe to call even if hook doesn't exist.

Arguments:
  GRAPH         - A graph object
  HOOK-TYPE     - Type of hook: :add, :delete, or :query
  HOOK-FUNCTION - The function to remove

Returns:
  NIL

See also: ADD-HOOK-TO-GRAPH, GET-GRAPH-HOOKS"))

(defmethod remove-hook-from-graph ((graph graph) hook-type hook-function)
  "Remove HOOK-FUNCTION from GRAPH's hooks of HOOK-TYPE.

This is the inverse of ADD-HOOK-TO-GRAPH. It removes a specific hook function
from the graph's hook list. If the hook is not present, this is a no-op (does
not signal an error).

Side Effects:
  Modifies the graph's hook list for the specified type"
  (ecase hook-type
    (:add (setf (graph-add-hooks graph)
                (remove hook-function (graph-add-hooks graph))))
    (:delete (setf (graph-delete-hooks graph)
                   (remove hook-function (graph-delete-hooks graph))))
    (:query (setf (graph-query-hooks graph)
                  (remove hook-function (graph-query-hooks graph)))))
  nil)

(defgeneric get-graph-hooks (graph hook-type)
  (:documentation "Get all hooks of HOOK-TYPE from GRAPH.

Works on all graph types.

Arguments:
  GRAPH     - A graph object
  HOOK-TYPE - Type of hook: :add, :delete, or :query

Returns:
  List of hook functions (may be NIL if no hooks registered)

See also: ADD-HOOK-TO-GRAPH, REMOVE-HOOK-FROM-GRAPH"))

(defmethod get-graph-hooks ((graph graph) hook-type)
  "Get all hooks of HOOK-TYPE from GRAPH.

Returns the list of hook functions registered for the specified hook type.
The returned list can be empty if no hooks are registered."
  (ecase hook-type
    (:add (graph-add-hooks graph))
    (:delete (graph-delete-hooks graph))
    (:query (graph-query-hooks graph))))

;;; ============================================================================
;;;; Phase 4: Triple Retrieval
;;; ============================================================================

(defun transform-a-results-to-rdf-type (triples)
  "Transform triples containing predicate 'a' to use 'rdf@type' instead.

This function handles the equivalence between 'a' (stored form) and 'rdf@type'
(query form) for RDF type declarations."
  (mapcar (lambda (triple)
            (if (eq (second triple) 'a)
                (list (first triple) 'rdf@type (third triple))
                triple))
          triples))

(defgeneric triples (pattern graph)
  (:documentation "Retrieve triples from GRAPH matching PATTERN.

PATTERN is a list of three elements (subject predicate object) where each
element can be:
  - A concrete value (symbol, string, number) to match exactly
  - T (wildcard) to match any value
  - A variable symbol (starts with $) to match any value

The function selects the most efficient index based on which pattern elements
are concrete:
  - Concrete subject: Use SPO index
  - Concrete predicate: Use POS index
  - Concrete object: Use OSP index
  - All wildcards: Scan all triples

Handles rdf@type/a equivalence: queries for rdf@type will match triples stored
with predicate 'a', and results will show rdf@type.

Returns: List of matching triples as (subject predicate object) lists.

Examples:
  (triples '(alice@person t t) g)              ; All triples about alice@person
  (triples '(t foaf@name t) g)                 ; All name triples
  (triples '(t t \"Alice\") g)                   ; All triples with object \"Alice\"
  (triples '(t rdf@type foaf@Person) g)        ; All instances of foaf@Person
  (triples '($subject foaf@name $name) g)      ; Variables work like wildcards"))

(defmethod triples (pattern (graph local-graph))
  "Retrieve triples from a local in-memory graph matching PATTERN.

Selects the appropriate index based on the pattern to optimize query performance."
  (let ((s (first pattern))
        (p (second pattern))
        (o (third pattern)))
    (let ((raw-results
           (cond
             ;; Subject is concrete - use SPO index
             ((not (var-or-wildp s))
              (let ((results (expand-duals (gethash s (graph-spo graph)) s)))
                (if (eq p 'rdf@type)
                    (transform-a-results-to-rdf-type results)
                    results)))
             ;; Predicate is concrete - use POS index
             ((not (var-or-wildp p))
              (if (eq p 'rdf@type)
                  ;; Query for rdf@type but 'a' is stored, so look up 'a' and transform
                  (let ((a-results (expand-duals (gethash 'a (graph-pos graph)) 'a 'pos)))
                    (transform-a-results-to-rdf-type a-results))
                  ;; Normal predicate lookup
                  (expand-duals (gethash p (graph-pos graph)) p 'pos)))
             ;; Object is concrete - use OSP index
             ((not (var-or-wildp o))
              (let ((results (expand-duals (gethash o (graph-osp graph)) o 'osp)))
                (if (eq p 'rdf@type)
                    (transform-a-results-to-rdf-type results)
                    results)))
             ;; Universal pattern - all triples
             (t
              (let ((result nil)
                    (spo-table (graph-spo graph)))
                ;; Collect all keys and process them
                (maphash (lambda (key value)
                           (setf result (append (expand-duals value key) result)))
                         spo-table)
                result)))))
      ;; TODO Phase 8: Add content reference resolution here
      ;; For now, just return raw results (no content refs implemented yet)
      raw-results)))

(defgeneric raw-triples (pattern graph)
  (:documentation "Retrieve triples from GRAPH matching PATTERN without resolving content references.

Like TRIPLES, but returns raw data without resolving content references.
Used for checkpointing to preserve file references.

Currently identical to TRIPLES since content references are not yet implemented
(Phase 8).

See TRIPLES for detailed documentation of pattern matching."))

(defmethod raw-triples (pattern (graph local-graph))
  "Retrieve triples from local graph without resolving content references.

Currently identical to TRIPLES implementation since content reference system
is not yet implemented. Will differ in Phase 8 when content references are added."
  (let ((s (first pattern))
        (p (second pattern))
        (o (third pattern)))
    (cond
      ;; Subject is concrete - use SPO index
      ((not (var-or-wildp s))
       (let ((results (expand-duals (gethash s (graph-spo graph)) s)))
         (if (eq p 'rdf@type)
             (transform-a-results-to-rdf-type results)
             results)))
      ;; Predicate is concrete - use POS index
      ((not (var-or-wildp p))
       (if (eq p 'rdf@type)
           ;; Query for rdf@type but 'a' is stored, so look up 'a' and transform
           (let ((a-results (expand-duals (gethash 'a (graph-pos graph)) 'a 'pos)))
             (transform-a-results-to-rdf-type a-results))
           ;; Normal predicate lookup
           (expand-duals (gethash p (graph-pos graph)) p 'pos)))
      ;; Object is concrete - use OSP index
      ((not (var-or-wildp o))
       (let ((results (expand-duals (gethash o (graph-osp graph)) o 'osp)))
         (if (eq p 'rdf@type)
             (transform-a-results-to-rdf-type results)
             results)))
      ;; Universal pattern - all triples
      (t
       (let ((result nil)
             (spo-table (graph-spo graph)))
         ;; Collect all keys and process them
         (maphash (lambda (key value)
                    (setf result (append (expand-duals value key) result)))
                  spo-table)
         result)))))

;;; ============================================================================
;;;; Phase 5: Pattern Matching
;;; ============================================================================

(defun augmented-eq (pattern input)
  "Type-aware equality comparison for pattern matching.

Uses the most appropriate equality test based on the type of PATTERN:
  - Symbols: EQ (fast pointer comparison)
  - Strings: STRING= (content comparison)
  - Numbers: EQL (handles floats correctly)
  - Other types: EQUAL (deep comparison)

Arguments:
  PATTERN - Value from the pattern (determines comparison type)
  INPUT   - Value from input data to compare against

Returns:
  T if values are equal according to type-appropriate test, NIL otherwise

Examples:
  (augmented-eq 'alice 'alice)     => T (symbol EQ)
  (augmented-eq \"Alice\" \"Alice\")   => T (string STRING=)
  (augmented-eq 42 42)             => T (number EQL)
  (augmented-eq 'alice \"alice\")   => NIL (different types)"
  (cond
    ((symbolp pattern) (eq pattern input))
    ((stringp pattern) (and (stringp input) (string= pattern input)))
    ((numberp pattern) (and (numberp input) (eql pattern input)))
    (t (equal pattern input))))

(defun pat-match (pattern input)
  "Match PATTERN against INPUT, returning variable bindings.

Performs recursive pattern matching on list structures, binding variables
(symbols starting with $) to their matched values. Returns a flat list of
bindings where each binding is a cons cell (variable . value).

Special bindings:
  - ($var . value) - Variable binding
  - (t . value)    - Wildcard match marker
  - (nil . nil)    - Match failure marker

Arguments:
  PATTERN - Pattern to match (may contain variables like $subject)
  INPUT   - Input data to match against

Returns:
  List of bindings (cons cells), including success/failure markers

Examples:
  (pat-match '$subject 'alice)
  => (($subject . alice))

  (pat-match '($s foaf@name $n) '(alice foaf@name \"Alice\"))
  => (($s . alice) (t . foaf@name) ($n . \"Alice\"))

  (pat-match 'alice 'bob)
  => ((nil . nil))  ; Failed match

Implementation note: Uses NCONC for performance (destructive but faster
than APPEND). Not tail-recursive, but RDF patterns are shallow (max ~10 deep)."
  (cond
    ;; Base case: nil pattern
    ((null pattern) nil)

    ;; Variable: bind to input
    ((variablep pattern)
     (list (cons pattern input)))

    ;; Both atoms: check equality
    ((and (atom pattern) (atom input))
     (if (augmented-eq pattern input)
         (list (cons t input))      ; Success marker
       (list (cons nil nil))))      ; Failure marker

    ;; Lists: recurse on CAR and CDR
    (t
     (nconc (pat-match (car pattern) (car input))
            (pat-match (cdr pattern) (cdr input))))))

(defun ensure-lparallel-kernel ()
  "Ensure lparallel kernel is initialized for parallel operations.

Creates a kernel with 4 workers if not already initialized. This is called
lazily by parallel functions (traverse-graph, filter-triples) before using
pmap or premove-if.

The kernel is stored in lparallel:*kernel* special variable."
  (unless (and (boundp '*kernel*) *kernel*)
    (setf *kernel* (make-kernel 4))))

(defun traverse-graph (pattern triples)
  "Apply PATTERN to TRIPLES, returning variable bindings for each match.

Maps pat-match over all triples, filters out non-matching results, and returns
a list of binding alists. For large datasets (100+ triples), uses parallel
processing via lparallel:pmap.

Arguments:
  PATTERN - Pattern to match (e.g., '($subject foaf@name $name))
  TRIPLES - List of triples to match against

Returns:
  List of binding alists, one for each matching triple

Examples:
  (traverse-graph '($s foaf@name $n)
                  '((alice foaf@name \"Alice\")
                    (bob foaf@name \"Bob\")
                    (alice foaf@age 30)))
  => ((($s . alice) ($n . \"Alice\"))
      (($s . bob) ($n . \"Bob\")))

Performance:
  - Sequential for < 100 triples
  - Parallel (4 workers) for >= 100 triples

See also: PAT-MATCH, FILTER-TRIPLES"
  (if (< (length triples) 100)
      ;; Small dataset - sequential processing
      (remove-if (lambda (bindings)
                   (member '(nil . nil) bindings :test #'equal))
                 (mapcar (lambda (triple)
                           (remove '(t) (pat-match pattern triple) :test #'equal))
                         triples))
      ;; Large dataset - parallel processing
      (progn
        (ensure-lparallel-kernel)
        (remove-if (lambda (bindings)
                     (member '(nil . nil) bindings :test #'equal))
                   (pmap 'list
                         (lambda (triple)
                           (remove '(t) (pat-match pattern triple) :test #'equal))
                         triples)))))

(defun filter-triples (pattern triples)
  "Filter TRIPLES, returning only those that match PATTERN.

Unlike TRAVERSE-GRAPH which returns bindings, this function returns the
actual triples that match. For large datasets (100+ triples), uses parallel
processing via lparallel:premove-if.

Arguments:
  PATTERN - Pattern to match (e.g., '($subject foaf@name $name))
  TRIPLES - List of triples to filter

Returns:
  List of matching triples

Examples:
  (filter-triples '($s foaf@name $n)
                  '((alice foaf@name \"Alice\")
                    (bob foaf@name \"Bob\")
                    (alice foaf@age 30)))
  => ((alice foaf@name \"Alice\")
      (bob foaf@name \"Bob\"))

Performance:
  - Sequential for < 100 triples
  - Parallel (4 workers) for >= 100 triples

See also: TRAVERSE-GRAPH, PAT-MATCH"
  (if (< (length triples) 100)
      ;; Small dataset - sequential processing
      (remove-if (lambda (triple)
                   (member '(nil . nil) (pat-match pattern triple) :test #'equal))
                 triples)
      ;; Large dataset - parallel processing
      (progn
        (ensure-lparallel-kernel)
        (premove-if (lambda (triple)
                      (member '(nil . nil) (pat-match pattern triple) :test #'equal))
                    triples))))

;;;; ============================================================================
;;;; Phase 6: Query Execution Engine
;;;; ============================================================================

;;; -----------------------------------------------------------------------------
;;; Condition System
;;; -----------------------------------------------------------------------------

(define-condition query-error (error)
  ((message
    :initarg :message
    :reader query-error-message
    :documentation "Descriptive error message"))
  (:documentation "Base condition for all query-related errors"))

(define-condition pattern-match-failure (query-error)
  ((pattern
    :initarg :pattern
    :reader pattern-match-failure-pattern
    :documentation "The pattern that failed to match")
   (graph
    :initarg :graph
    :reader pattern-match-failure-graph
    :documentation "The graph that was queried"))
  (:documentation "Signaled when a non-optional pattern matches no triples")
  (:report (lambda (condition stream)
             (format stream "Pattern ~A matched no triples in graph"
                     (pattern-match-failure-pattern condition)))))

(define-condition binding-conflict (query-error)
  ((new-bindings
    :initarg :new-bindings
    :reader binding-conflict-new
    :documentation "New bindings that conflict")
   (old-bindings
    :initarg :old-bindings
    :reader binding-conflict-old
    :documentation "Existing bindings"))
  (:documentation "Signaled when variable bindings conflict")
  (:report (lambda (condition stream)
             (format stream "Binding conflict: new ~A incompatible with old ~A"
                     (binding-conflict-new condition)
                     (binding-conflict-old condition)))))

;;; -----------------------------------------------------------------------------
;;; Binding Utilities
;;; -----------------------------------------------------------------------------

(defun clean-bindings (bindings)
  "Remove success markers (T . value) from variable bindings.

BINDINGS is a list of binding sets, each containing (var . value) pairs.

Returns a new list with all (T . value) pairs removed.

Examples:
  (clean-bindings '((($s . alice) (t . alice) ($p . foaf@name))))
  => ((($s . alice) ($p . foaf@name)))

See also: PAT-MATCH, UPDATE-BINDINGS"
  (mapcar (lambda (binding-set)
            (remove-if (lambda (pair) (eq t (car pair)))
                       binding-set))
          bindings))

(defun compatible-bindings-p (newbindings oldbindings)
  "Check if NEWBINDINGS are compatible with OLDBINDINGS.

Two bindings are compatible if:
  - They bind the same variable to the same value, OR
  - They bind different variables, OR
  - The variable is unbound in one of them

Returns T if compatible, NIL if any variable has conflicting values.

Arguments:
  NEWBINDINGS - List of (var . value) pairs to check
  OLDBINDINGS - List of existing binding sets (nested structure)

Examples:
  (compatible-bindings-p '(($s . alice)) '((($s . alice))))  => T
  (compatible-bindings-p '(($s . alice)) '((($s . bob))))    => NIL
  (compatible-bindings-p '(($p . foaf@name)) '((($s . alice)))) => T

See also: UPDATE-BINDINGS"
  (when *debug*
    (log:debug "Comparing ~A with ~A" newbindings oldbindings))
  (every #'identity
         (mapcar (lambda (new-pair)
                   (let ((oldval (cdr (assoc (car new-pair) (car oldbindings))))
                         (newval (cdr new-pair)))
                     (when *debug*
                       (log:debug "  Variable ~A: old=~A new=~A" (car new-pair) oldval newval))
                     (or (not oldval) (equal oldval newval))))
                 newbindings)))

(defun update-bindings (newbindings oldbindings)
  "Merge NEWBINDINGS with OLDBINDINGS if compatible.

Returns a list of merged binding sets, or NIL if bindings conflict.
Removes duplicate bindings and success markers.

Arguments:
  NEWBINDINGS - List of new binding sets to merge
  OLDBINDINGS - Existing binding sets

Examples:
  (update-bindings '((($p . foaf@name))) '((($s . alice))))
  => ((($s . alice) ($p . foaf@name)))

  (update-bindings '((($s . alice))) '((($s . bob))))
  => NIL  ; Conflict

See also: CLEAN-BINDINGS, COMPATIBLE-BINDINGS-P"
  (cond
    ((not newbindings)
     (clean-bindings oldbindings))
    (t
     (mapcan (lambda (new-binding-set)
               (if (not (compatible-bindings-p new-binding-set oldbindings))
                   (progn
                     (when *debug*
                       (log:warn "Conflicting bindings: ~A and ~A"
                                 new-binding-set oldbindings))
                     nil)
                 (clean-bindings
                  (list (remove-duplicates
                         (append new-binding-set (car oldbindings))
                         :test #'equal)))))
             newbindings))))

;;; -----------------------------------------------------------------------------
;;; Pattern Normalization
;;; -----------------------------------------------------------------------------

(defun normalize-pattern (pattern)
  "Normalize rdf@type to 'a' in PATTERN for consistent matching.

Only normalizes if the pattern contains NO variables, since the triples()
function already handles equivalence by transforming results.

Examples:
  (normalize-pattern '(alice rdf@type schema@Person))
  => (alice a schema@Person)

  (normalize-pattern '($s rdf@type schema@Person))
  => ($s rdf@type schema@Person)  ; Not normalized - has variable

See also: TRIPLES"
  (if (and (listp pattern)
           (>= (length pattern) 3)
           (eq (nth 1 pattern) 'rdf@type)
           (not (var-or-wildp (nth 0 pattern)))
           (not (var-or-wildp (nth 2 pattern))))
      (list (nth 0 pattern) 'a (nth 2 pattern))
    pattern))

;;; -----------------------------------------------------------------------------
;;; Optional Clause Handling
;;; -----------------------------------------------------------------------------

(defun optional-clause-p (clause)
  "Return T if CLAUSE is an OPTIONAL clause, NIL otherwise.

OPTIONAL clauses have the form: (optional PATTERN)

Examples:
  (optional-clause-p '(optional ($s foaf@name $name)))  => T
  (optional-clause-p '($s foaf@name $name))             => NIL

See also: UNWRAP-OPTIONAL"
  (and (listp clause)
       (eq (car clause) 'optional)))

(defun unwrap-optional (clause)
  "Extract the pattern from an OPTIONAL CLAUSE.

If CLAUSE is not optional, returns it unchanged.

Examples:
  (unwrap-optional '(optional ($s foaf@name $name)))
  => ($s foaf@name $name)

  (unwrap-optional '($s foaf@name $name))
  => ($s foaf@name $name)

See also: OPTIONAL-CLAUSE-P"
  (if (optional-clause-p clause)
      (second clause)
    clause))

;;; -----------------------------------------------------------------------------
;;; Binding Result Normalization
;;; -----------------------------------------------------------------------------

(defun normalize-binding-results (results)
  "Ensure RESULTS have consistent triple-nested structure.

The query engine maintains a standard structure:
  (((bindings1)) ((bindings2)))

This function normalizes any variations to match this structure.

Arguments:
  RESULTS - Query results that may need normalization

Returns:
  Results in canonical triple-nested form

See also: GRAPH-QUERY"
  ;; For now, just return results as-is
  ;; More sophisticated normalization may be added later
  results)

;;; -----------------------------------------------------------------------------
;;; Query Execution Helpers
;;; -----------------------------------------------------------------------------

(defun %process-first-clause (clauses graph pattern is-optional)
  "Process first query clause with no existing bindings.

This handles the initial pattern match in a query execution.

Arguments:
  CLAUSES - Full clause list (including current)
  GRAPH - The RDF graph to query
  PATTERN - Unwrapped pattern to match
  IS-OPTIONAL - T if this is an optional clause

Returns:
  Binding results, wrapped appropriately for recursion
  :NO-MATCH if pattern doesn't match and isn't optional

Signals:
  PATTERN-MATCH-FAILURE if pattern doesn't match (unless optional)

See also: %GRAPH-QUERY-INTERNAL"
  (let ((bindings (traverse-graph pattern (triples pattern graph))))
    (when *debug*
      (log:debug "First clause: pattern=~A bindings=~A" pattern bindings))
    (cond
      ;; Pattern didn't match - signal error unless optional
      ((and (null bindings) (not is-optional))
       (restart-case
           (error 'pattern-match-failure
                  :pattern pattern
                  :graph graph
                  :message (format nil "Pattern ~A matched no triples" pattern))
         (use-empty-bindings ()
           :report "Continue with empty bindings"
           '())
         (return-no-match ()
           :report "Return :no-match keyword"
           (return-from %process-first-clause :no-match))))
      ;; More clauses to process
      ((cdr clauses)
       (%graph-query-internal (cdr clauses) graph
                              (update-bindings nil (or bindings '()))))
      ;; Single clause - wrap result for consistency
      (t (if bindings (mapcar #'list bindings) '())))))

(defun %process-multiple-branches (clauses bindings graph pattern is-optional)
  "Process query when multiple binding branches exist.

Each branch represents an independent solution path that needs to be
followed through the remaining clauses.

Arguments:
  CLAUSES - Remaining clauses to process
  BINDINGS - Current binding branches (multiple)
  GRAPH - The RDF graph to query
  PATTERN - Current pattern to match (unwrapped)
  IS-OPTIONAL - T if current clause is optional

Returns:
  Combined results from all successful branches

See also: %GRAPH-QUERY-INTERNAL"
  (remove-if
   #'null
   (mapcar
    (lambda (binding-branch)
      (let* ((substituted-pattern (sublis binding-branch pattern))
             (newbindings (traverse-graph substituted-pattern
                                          (triples pattern graph)))
             (updated-bindings (update-bindings newbindings
                                                (list binding-branch))))
        (when *debug*
          (log:debug "Branch: pattern=~A new=~A updated=~A"
                     substituted-pattern newbindings updated-bindings))
        (if (or (not newbindings) (not updated-bindings))
            (if is-optional
                ;; Optional clause failed - continue with existing bindings
                (%graph-query-internal (cdr clauses) graph (list binding-branch))
              nil)
          ;; Successful match - recurse with updated bindings
          (%graph-query-internal (sublis updated-bindings (cdr clauses))
                                 graph
                                 updated-bindings))))
    bindings)))

(defun %process-single-branch (clauses bindings graph pattern is-optional)
  "Process query when single binding branch exists.

Arguments:
  CLAUSES - Remaining clauses to process
  BINDINGS - Current single binding branch
  GRAPH - The RDF graph to query  
  PATTERN - Current pattern to match (unwrapped)
  IS-OPTIONAL - T if current clause is optional

Returns:
  Updated bindings after processing this clause

See also: %GRAPH-QUERY-INTERNAL"
  (let* ((substituted-pattern (sublis bindings pattern))
         (newbindings (traverse-graph substituted-pattern
                                      (triples pattern graph)))
         (updated-bindings (update-bindings newbindings bindings)))
    (when *debug*
      (log:debug "Single branch: pattern=~A new=~A updated=~A"
                 substituted-pattern newbindings updated-bindings))
    (if (or (not newbindings) (not updated-bindings))
        (if is-optional
            ;; Optional clause failed - continue with existing bindings
            (%graph-query-internal (cdr clauses) graph bindings)
          nil)
      ;; Successful match - recurse with updated bindings
      (%graph-query-internal (sublis updated-bindings (cdr clauses))
                             graph
                             updated-bindings))))

(defun %graph-query-internal (clauses graph &optional bindings)
  "Core query execution engine with pattern matching and OPTIONAL support.

This is the internal implementation of graph-query, handling:
  - Pattern matching against the graph
  - Variable binding accumulation
  - OPTIONAL clause semantics (left-join)
  - Multiple solution branches

Arguments:
  CLAUSES - List of patterns or (optional PATTERN) clauses
  GRAPH - The RDF graph to query
  BINDINGS - Current variable bindings (used in recursion)

Returns:
  Triple-nested binding structure: (((var . val) ...))
  Or :NO-MATCH if a required pattern fails

Execution Paths:
  1. No clauses left → return current bindings (base case)
  2. No existing bindings → process first clause
  3. Multiple binding branches → split and process each
  4. Single binding branch → apply pattern and recurse

Examples:
  (%graph-query-internal '(($s foaf@name $name)) graph)
  => (((($s . alice) ($name . \"Alice\")))
      ((($s . bob) ($name . \"Bob\"))))

See also: GRAPH-QUERY, TRAVERSE-GRAPH, UPDATE-BINDINGS

TODO: Nested OPTIONAL clauses not yet supported (see CL-PORT-PLAN.md)"
  (let* ((bindings (or bindings '()))
         (pattern (car clauses))
         (is-optional (optional-clause-p pattern))
         (unwrapped-pattern (if is-optional (unwrap-optional pattern) pattern)))
    (when *debug*
      (log:debug "Query: clauses=~A bindings-count=~A"
                 (length clauses) (length bindings)))
    (cond
      ;; Base case: no more clauses or malformed pattern
      ((or (not clauses) (< (length unwrapped-pattern) 3))
       bindings)
      ;; First call: no existing bindings
      ((not bindings)
       (%process-first-clause clauses graph unwrapped-pattern is-optional))
      ;; Multiple binding branches: process each independently
      ((> (length bindings) 1)
       (%process-multiple-branches clauses bindings graph unwrapped-pattern is-optional))
      ;; Single binding branch: apply pattern and recurse
      (t
       (%process-single-branch clauses bindings graph unwrapped-pattern is-optional)))))

(defun graph-query (clauses graph &optional bindings)
  "Execute a SPARQL-like query against GRAPH.

Supports pattern matching with variables, multiple clauses,
and OPTIONAL clause semantics.

Arguments:
  CLAUSES - List of triple patterns, e.g., '(($s rdf@type foaf@Person) ...)
  GRAPH - The RDF graph to query
  BINDINGS - Optional initial variable bindings

Returns:
  List of binding sets (triple-nested structure), or
  :NO-MATCH if a required pattern matches no triples

Signals:
  PATTERN-MATCH-FAILURE if pattern doesn't match (caught by default handler)

Default Behavior:
  The default handler returns :NO-MATCH on pattern-match-failure.
  Callers can override by establishing their own handler.

Variable Syntax:
  Variables start with $ (e.g., $subject, $name)

Examples:
  ;; Single clause
  (graph-query '(($s foaf@name $name)) graph)
  => (((($s . alice) ($name . \"Alice\")))
      ((($s . bob) ($name . \"Bob\"))))

  ;; Multiple clauses (join)
  (graph-query '(($s foaf@name $name)
                 ($s foaf@age $age))
               graph)
  => (((($s . alice) ($name . \"Alice\") ($age . 30))))

  ;; OPTIONAL clause (left-join)
  (graph-query '(($s foaf@name $name)
                 (optional ($s foaf@age $age)))
               graph)
  => Results include entries without age if not present

Hooks:
  Calls all registered query-hooks before processing

See also: WHERE (alias), ASK, SELECT, CONSTRUCT, FILTER"
  ;; Call query hooks before processing
  (let ((query-hooks (graph-query-hooks graph)))
    (mapc (lambda (hook) (funcall hook graph 'graph-query clauses))
          query-hooks))
  ;; Execute with default error handler
  (handler-bind ((pattern-match-failure
                   (lambda (condition)
                     (when *debug*
                       (log:warn "Pattern match failure: ~A" condition))
                     ;; Default behavior: return :no-match
                     (invoke-restart 'return-no-match))))
    (let ((raw-results (%graph-query-internal clauses graph bindings)))
      (if (and raw-results (not (eq raw-results :no-match)))
          (normalize-binding-results raw-results)
        raw-results))))

;; Alias for compatibility
(setf (fdefinition 'where) #'graph-query)

;;;; ============================================================================
;;;; Phase 7: Query Operations (ASK, CONSTRUCT, DELETE-DATA)
;;;; ============================================================================

;;; -----------------------------------------------------------------------------
;;; Boolean Queries
;;; -----------------------------------------------------------------------------

(defun ask (clauses graph)
  "Execute a boolean ASK query against GRAPH.

Returns T if the pattern matches at least one result, NIL otherwise.
Handles pattern-match-failure gracefully by returning NIL.

Arguments:
  CLAUSES - List of triple patterns (same as graph-query)
  GRAPH - The RDF graph to query

Returns:
  T if pattern matches, NIL otherwise

Examples:
  (ask '(($s foaf@name \"Alice\")) graph)  => T or NIL
  (ask '(($s rdf@type foaf@Person)) graph) => T or NIL

Note: Unlike graph-query, ASK never signals errors. It returns NIL
for both pattern-match-failure and empty results.

See also: GRAPH-QUERY, SELECT"
  (handler-case
      (let ((result (graph-query clauses graph)))
        ;; Result is :no-match or a binding list
        (and result
             (not (eq result :no-match))
             (>= (length (remove nil result)) 1)))
    (error () nil)))

;;; -----------------------------------------------------------------------------
;;; Triple Construction
;;; -----------------------------------------------------------------------------

(defun expand-list-bindings (triples)
  "Expand triples containing list values into multiple triples.

If a triple's object is a list, expands it into multiple triples,
one for each list element.

Arguments:
  TRIPLES - List of triples (each triple is (subject predicate object))

Returns:
  List of expanded triples

Examples:
  (expand-list-bindings '((alice foaf@knows (bob charlie))))
  => ((alice foaf@knows bob) (alice foaf@knows charlie))

  (expand-list-bindings '((alice foaf@name \"Alice\")))
  => ((alice foaf@name \"Alice\"))

See also: CONSTRUCT"
  (mapcan (lambda (triple)
            (let ((subject (nth 0 triple))
                  (predicate (nth 1 triple))
                  (object (nth 2 triple)))
              ;; Check if object is a list
              (if (and (listp object) (not (null object)))
                  ;; Expand list into multiple triples
                  (mapcar (lambda (obj) (list subject predicate obj)) object)
                ;; Single triple
                (list triple))))
          triples))

(defun construct (clauses bindings)
  "Construct new triples from CLAUSES template using BINDINGS.

CLAUSES is a template (list of triple patterns with variables).
BINDINGS is the result from graph-query (triple-nested structure).

For each binding set, substitutes variables in the template and
expands any list objects into multiple triples.

Arguments:
  CLAUSES - Template triples with variables (e.g., '(($s rdf@type foaf@Person)))
  BINDINGS - Query results from graph-query

Returns:
  List of constructed triples

Examples:
  (let ((bindings (graph-query '(($s foaf@name $n)) graph)))
    (construct '(($s rdf@type foaf@Person)) bindings))
  => ((alice rdf@type foaf@Person) (bob rdf@type foaf@Person))

See also: GRAPH-QUERY, DELETE-DATA, EXPAND-LIST-BINDINGS"
  (mapcan (lambda (binding-set)
            (mapcan (lambda (binding-branch)
                      (expand-list-bindings (sublis binding-branch clauses)))
                    binding-set))
          bindings))

;;; -----------------------------------------------------------------------------
;;; Pattern-Based Deletion
;;; -----------------------------------------------------------------------------

(defun delete-data (clauses graph)
  "Delete all triples matching CLAUSES pattern from GRAPH.

Uses graph-query to find matches, construct to build triples to delete,
then delete-triples to remove them. Handles errors gracefully.

Arguments:
  CLAUSES - List of triple patterns (may include variables)
  GRAPH - The RDF graph to modify

Returns:
  T if deletion succeeded (at least one triple deleted)
  NIL if no matches found or query failed

Examples:
  ;; Delete specific triple
  (delete-data '((alice foaf@age 30)) graph)

  ;; Delete all matching pattern
  (delete-data '(($s rdf@type foaf@Person)) graph)

  ;; Delete with join
  (delete-data '(($s foaf@name \"Alice\")
                 ($s foaf@age $age))
               graph)

Note: Triggers delete-hooks after deletion.

See also: DELETE-TRIPLE, DELETE-TRIPLES, CONSTRUCT, GRAPH-QUERY"
  (handler-case
      (let* ((bindings (graph-query clauses graph))
             (triples-to-delete (when (and bindings (not (eq bindings :no-match)))
                                  (construct clauses bindings))))
        (when triples-to-delete
          (delete-triples triples-to-delete graph)
          t))
    (error () nil)))
