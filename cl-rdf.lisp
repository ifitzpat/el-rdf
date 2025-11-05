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
;;;; Phase 1: Core Data Structures and Utilities
;;;; ============================================================================

;;; -----------------------------------------------------------------------------
;;; Graph Structure (CLOS-based)
;;; -----------------------------------------------------------------------------

(defclass graph ()
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
    :documentation "Association list of (prefix-string . namespace-uri) pairs for TTL import")

   (name
    :initarg :name
    :initform nil
    :accessor graph-name
    :documentation "Optional name for checkpointing and identification"))
  (:documentation "RDF graph with triple-indexed storage (SPO, OSP, POS).

The graph uses three hash table indices for efficient querying:
- SPO: Indexed by subject (uses EQ test for symbol keys)
- OSP: Indexed by object (uses EQUAL test for any type of keys)
- POS: Indexed by predicate (uses EQ test for symbol keys)

Hooks allow observing CRUD operations.
Prefixes store namespace mappings for TTL import.
Name enables checkpointing and recovery of named graphs."))

(defun make-graph (&key name)
  "Create a new RDF graph with optional NAME for checkpointing.

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
  A new GRAPH object.

Examples:
  (make-graph)                    ; Anonymous graph
  (make-graph :name \"my-data\")    ; Named graph for checkpointing

See also: ADD-TRIPLE, GRAPH-QUERY, REGISTER-GRAPH-FOR-CHECKPOINTING"
  (make-instance 'graph :name name))

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
;;; Triple Operations
;;; -----------------------------------------------------------------------------

(defun add-triple (triple graph)
  "Add a single RDF triple to the graph, maintaining all three indices.

This is the core function for adding data to the graph. It updates three hash
table indices (SPO, OSP, POS) to enable efficient querying from different
access patterns. The function automatically normalizes rdf@type to 'a for
storage efficiency.

Arguments:
  TRIPLE - A list of three elements: (subject predicate object)
  GRAPH  - A graph object (CLOS instance)

Returns:
  NIL (modifies graph in place)

Side Effects:
  - Updates graph-spo hash table (subject -> ((predicate . (objects...))))
  - Updates graph-osp hash table (object -> ((subject . (predicates...))))
  - Updates graph-pos hash table (predicate -> ((object . (subjects...))))

Normalization:
  - rdf@type is automatically converted to 'a during storage
  - This saves space and simplifies queries

Examples:
  (add-triple '(John schema@name \"John Doe\") g)
  (add-triple '(John a schema@Person) g)
  (add-triple '(John rdf@type schema@Person) g)  ; Stored as 'a

See also: ADD-TRIPLES, DELETE-TRIPLE, TRIPLES"
  (let* ((subject (first triple))
         ;; Normalize rdf@type to 'a for storage efficiency
         (predicate (if (eq (second triple) 'rdf@type) 'a (second triple)))
         (object (third triple))
         (spo (graph-spo graph))
         (osp (graph-osp graph))
         (pos (graph-pos graph)))

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
          (setf (gethash predicate pos) `((,object . ,(list subject)))))))

  nil)

(defun delete-triple (triple graph)
  "Remove a single RDF triple from the graph, maintaining all three indices.

This function is the inverse of ADD-TRIPLE. It removes a triple from all three
indices (SPO, OSP, POS) and automatically cleans up empty entries using REMHASH
when no triples remain for a given key.

Arguments:
  TRIPLE - A list of three elements: (subject predicate object)
  GRAPH  - A graph object (CLOS instance)

Returns:
  NIL (modifies graph in place)

Side Effects:
  - Updates graph-spo hash table (removes or updates entry)
  - Updates graph-osp hash table (removes or updates entry)
  - Updates graph-pos hash table (removes or updates entry)
  - Uses REMHASH to completely remove keys when they become empty

Normalization:
  - rdf@type is automatically converted to 'a for lookup
  - This matches the normalization done in ADD-TRIPLE

Examples:
  (delete-triple '(John schema@name \"John Doe\") g)
  (delete-triple '(John rdf@type schema@Person) g)  ; Looks up as 'a

See also: ADD-TRIPLE, DELETE-TRIPLES, TRIPLES"
  (let* ((subject (first triple))
         ;; Normalize rdf@type to 'a to match storage format
         (predicate (if (eq (second triple) 'rdf@type) 'a (second triple)))
         (object (third triple))
         (spo (graph-spo graph))
         (osp (graph-osp graph))
         (pos (graph-pos graph)))

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
              (remhash predicate pos))))))

  nil)

;;; -----------------------------------------------------------------------------
;;; Duals Expansion
;;; -----------------------------------------------------------------------------

(defun expand-duals (duals element &optional (reorder nil))
  "Expand alist structure into list of triples.

This function converts the internal alist representation used in the triple
indices into a flat list of triples. The REORDER parameter determines the
order of elements in each triple.

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
  (loop for (key . values) in duals
        nconc (loop for value in values
                    collect (ecase reorder
                              ((nil) (list element key value))      ; SPO
                              (:osp  (list key value element))      ; OSP
                              (:pos  (list value element key))))))  ; POS
