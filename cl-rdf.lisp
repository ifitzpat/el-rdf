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
