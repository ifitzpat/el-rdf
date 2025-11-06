;;;; cl-rdf.lisp --- In-memory RDF triple store for Common Lisp

(in-package #:cl-rdf)

;;;; Core Data Structures

(defclass local-graph ()
  ((spo :initform (make-hash-table :test 'eq)
        :accessor graph-spo
        :documentation "Subject-Predicate-Object index")
   (osp :initform (make-hash-table :test 'eq)
        :accessor graph-osp
        :documentation "Object-Subject-Predicate index")
   (pos :initform (make-hash-table :test 'eq)
        :accessor graph-pos
        :documentation "Predicate-Object-Subject index")
   (add-hooks :initform nil
              :accessor graph-add-hooks
              :documentation "List of functions called after add-triples")
   (delete-hooks :initform nil
                 :accessor graph-delete-hooks
                 :documentation "List of functions called after delete-triples")
   (query-hooks :initform nil
                :accessor graph-query-hooks
                :documentation "List of functions called during queries")
   (name :initform nil
         :accessor graph-name
         :documentation "Optional name for the graph")
   (prefixes :initform nil
             :accessor graph-prefixes
             :documentation "Alist of (prefix . namespace-uri) for TTL import")
   #+sbcl
   (lock :initform (make-lock "graph-lock")
         :reader graph-lock
         :documentation "Mutex for thread-safe operations (SBCL only)"))
  (:documentation "In-memory RDF graph with triple indices and hooks"))

(defmethod print-object ((graph local-graph) stream)
  "Print representation of a graph"
  (print-unreadable-object (graph stream :type t :identity t)
    (format stream "~:[unnamed~;~:*~A~]" (graph-name graph))))

;;;; Phase 1: Core Utilities

(defun make-graph (&optional name)
  "Create a new empty RDF graph.

Arguments:
  NAME - Optional name for the graph (enables checkpointing)

Returns:
  New local-graph instance

Examples:
  (make-graph) => #<LOCAL-GRAPH {10052F3B63}>
  (make-graph \"my-graph\") => #<LOCAL-GRAPH my-graph {10052F3B63}>"
  (let ((graph (make-instance 'local-graph)))
    (when name
      (setf (graph-name graph) name))
    graph))

(defun variablep (symbol)
  "Return T if SYMBOL is a SPARQL variable (starts with $).

Variables are identified by a leading $ character in the symbol name.

Arguments:
  SYMBOL - Symbol to test

Returns:
  T if symbol is a variable, NIL otherwise

Examples:
  (variablep '$subject) => T
  (variablep '$name) => T
  (variablep 'regular-symbol) => NIL"
  (and (symbolp symbol)
       (let ((name (symbol-name symbol)))
         (and (> (length name) 0)
              (char= (char name 0) #\$)))))

(defun wildcardp (value)
  "Return T if VALUE is the wildcard symbol T.

The symbol T matches any value in patterns.

Arguments:
  VALUE - Value to test

Returns:
  T if value is wildcard, NIL otherwise

Examples:
  (wildcardp t) => T
  (wildcardp 'foo) => NIL
  (wildcardp \"bar\") => NIL"
  (eq value t))

(defun var-or-wildp (value)
  "Return T if VALUE is either a variable or wildcard.

Arguments:
  VALUE - Value to test

Returns:
  T if value is variable or wildcard, NIL otherwise

Examples:
  (var-or-wildp '$x) => T
  (var-or-wildp t) => T
  (var-or-wildp 'foo) => NIL"
  (or (variablep value)
      (wildcardp value)))

(defvar *bnode-counter* 0
  "Counter for generating unique blank node identifiers")

(defun bnode ()
  "Generate a unique blank node identifier.

Returns:
  Symbol of form _:G<number>

Examples:
  (bnode) => _:G0
  (bnode) => _:G1"
  (alexandria:symbolicate "_:G" (incf *bnode-counter*)))

;;;; Phase 2: Triple Storage Operations

(defun %ensure-nested-alist (key hash-table)
  "Helper: Ensure KEY exists in HASH-TABLE with empty alist value."
  (unless (gethash key hash-table)
    (setf (gethash key hash-table) nil)))

(defun %add-to-nested-alist (key1 key2 hash-table)
  "Helper: Add KEY2 to alist stored at KEY1 in HASH-TABLE."
  (%ensure-nested-alist key1 hash-table)
  (let ((alist (gethash key1 hash-table)))
    (let ((entry (assoc key2 alist :test #'eq)))
      (unless entry
        (setf (gethash key1 hash-table)
              (acons key2 nil alist))))))

(defun %add-to-nested-list (key1 key2 value hash-table)
  "Helper: Add VALUE to list at KEY1->KEY2 in HASH-TABLE."
  (%add-to-nested-alist key1 key2 hash-table)
  (let* ((alist (gethash key1 hash-table))
         (entry (assoc key2 alist :test #'eq))
         (current-list (cdr entry)))
    (unless (member value current-list :test #'equal)
      (setf (cdr entry) (cons value current-list)))))

(defgeneric add-triple (triple graph)
  (:documentation "Add a single triple to GRAPH.

Arguments:
  TRIPLE - List of (subject predicate object)
  GRAPH - Graph instance

Side Effects:
  Updates graph storage
  Normalizes 'a' and rdf@type to 'a'

Examples:
  (add-triple '(alice foaf@name \"Alice\") graph)
  (add-triple '(bob rdf@type foaf@Person) graph)"))

#+sbcl
(defmethod add-triple (triple (graph local-graph))
  "Add triple to local graph with thread-safe locking (SBCL)."
  (destructuring-bind (s p o) triple
    (let ((normalized-p (if (eq p 'rdf@type) 'a p)))
      ;; Thread-safe update with mutex
      (with-lock-held ((graph-lock graph))
        (%add-to-nested-list s normalized-p o (graph-spo graph))
        (%add-to-nested-list o s normalized-p (graph-osp graph))
        (%add-to-nested-list normalized-p o s (graph-pos graph))))))

#+ecl
(defmethod add-triple (triple (graph local-graph))
  "Add triple to local graph (ECL - no threading)."
  (destructuring-bind (s p o) triple
    (let ((normalized-p (if (eq p 'rdf@type) 'a p)))
      ;; Direct updates, no locking overhead
      (%add-to-nested-list s normalized-p o (graph-spo graph))
      (%add-to-nested-list o s normalized-p (graph-osp graph))
      (%add-to-nested-list normalized-p o s (graph-pos graph)))))

(defgeneric add-triples (triples graph)
  (:documentation "Add multiple triples to GRAPH and trigger add-hooks.

Arguments:
  TRIPLES - List of triples to add
  GRAPH - Graph instance

Side Effects:
  Adds all triples via add-triple
  Calls all registered add-hooks

Examples:
  (add-triples '((alice foaf@name \"Alice\")
                 (bob foaf@name \"Bob\")) graph)"))

#+sbcl
(defmethod add-triples (triples (graph local-graph))
  "Add multiple triples with parallel processing for large datasets (SBCL)."
  ;; Use parallel processing for 100+ triples
  (if (< (length triples) 100)
      ;; Small dataset - sequential
      (dolist (triple triples)
        (add-triple triple graph))
      ;; Large dataset - parallel processing
      (let* ((num-threads 4)  ; Hardcoded: 4 threads for parallel processing
             (chunk-size (ceiling (/ (length triples) num-threads)))
             (chunks (loop for i from 0 below (length triples) by chunk-size
                           collect (subseq triples i (min (+ i chunk-size)
                                                          (length triples)))))
             (threads nil))
        ;; Spawn threads to add triples in parallel
        (dolist (chunk chunks)
          (push (make-thread
                 (lambda (c)
                   (dolist (triple c)
                     (add-triple triple graph)))
                 :arguments (list chunk)
                 :name "add-triples-worker")
                threads))
        ;; Wait for all additions to complete
        (mapc #'join-thread threads)))
  ;; Call hooks after all triples added
  (dolist (hook (graph-add-hooks graph))
    (funcall hook graph 'add-triples triples)))

#+ecl
(defmethod add-triples (triples (graph local-graph))
  "Add multiple triples sequentially (ECL - no threading)."
  (dolist (triple triples)
    (add-triple triple graph))
  ;; Call hooks
  (dolist (hook (graph-add-hooks graph))
    (funcall hook graph 'add-triples triples)))

(defun %remove-from-nested-list (key1 key2 value hash-table)
  "Helper: Remove VALUE from list at KEY1->KEY2 in HASH-TABLE."
  (let* ((alist (gethash key1 hash-table))
         (entry (assoc key2 alist :test #'eq)))
    (when entry
      (setf (cdr entry) (remove value (cdr entry) :test #'equal))
      ;; Clean up empty entries
      (when (null (cdr entry))
        (setf (gethash key1 hash-table)
              (remove key2 alist :key #'car :test #'eq))))))

(defgeneric delete-triple (triple graph)
  (:documentation "Delete a single triple from GRAPH.

Arguments:
  TRIPLE - List of (subject predicate object)
  GRAPH - Graph instance

Side Effects:
  Removes from graph storage
  Normalizes 'a' and rdf@type to 'a'

Examples:
  (delete-triple '(alice foaf@name \"Alice\") graph)"))

#+sbcl
(defmethod delete-triple (triple (graph local-graph))
  "Delete triple from local graph with thread-safe locking (SBCL)."
  (destructuring-bind (s p o) triple
    (let ((normalized-p (if (eq p 'rdf@type) 'a p)))
      ;; Thread-safe update with mutex
      (with-lock-held ((graph-lock graph))
        (%remove-from-nested-list s normalized-p o (graph-spo graph))
        (%remove-from-nested-list o s normalized-p (graph-osp graph))
        (%remove-from-nested-list normalized-p o s (graph-pos graph))))))

#+ecl
(defmethod delete-triple (triple (graph local-graph))
  "Delete triple from local graph (ECL - no threading)."
  (destructuring-bind (s p o) triple
    (let ((normalized-p (if (eq p 'rdf@type) 'a p)))
      ;; Direct updates, no locking overhead
      (%remove-from-nested-list s normalized-p o (graph-spo graph))
      (%remove-from-nested-list o s normalized-p (graph-osp graph))
      (%remove-from-nested-list normalized-p o s (graph-pos graph)))))

(defgeneric delete-triples (triples graph)
  (:documentation "Delete multiple triples from GRAPH and trigger delete-hooks.

Arguments:
  TRIPLES - List of triples to delete
  GRAPH - Graph instance

Side Effects:
  Deletes all triples via delete-triple
  Calls all registered delete-hooks

Examples:
  (delete-triples '((alice foaf@name \"Alice\")
                    (bob foaf@name \"Bob\")) graph)"))

#+sbcl
(defmethod delete-triples (triples (graph local-graph))
  "Delete multiple triples with parallel processing for large datasets (SBCL)."
  ;; Use parallel processing for 100+ triples
  (if (< (length triples) 100)
      ;; Small dataset - sequential
      (dolist (triple triples)
        (delete-triple triple graph))
      ;; Large dataset - parallel processing
      (let* ((num-threads 4)  ; Hardcoded: 4 threads for parallel processing
             (chunk-size (ceiling (/ (length triples) num-threads)))
             (chunks (loop for i from 0 below (length triples) by chunk-size
                           collect (subseq triples i (min (+ i chunk-size)
                                                          (length triples)))))
             (threads nil))
        ;; Spawn threads to delete triples in parallel
        (dolist (chunk chunks)
          (push (make-thread
                 (lambda (c)
                   (dolist (triple c)
                     (delete-triple triple graph)))
                 :arguments (list chunk)
                 :name "delete-triples-worker")
                threads))
        ;; Wait for all deletions to complete
        (mapc #'join-thread threads)))
  ;; Call hooks after all triples deleted
  (dolist (hook (graph-delete-hooks graph))
    (funcall hook graph 'delete-triples triples)))

#+ecl
(defmethod delete-triples (triples (graph local-graph))
  "Delete multiple triples sequentially (ECL - no threading)."
  (dolist (triple triples)
    (delete-triple triple graph))
  ;; Call hooks
  (dolist (hook (graph-delete-hooks graph))
    (funcall hook graph 'delete-triples triples)))

;;;; Phase 3: Hook System

(defun add-hook-to-graph (graph hook-type hook-function)
  "Add HOOK-FUNCTION to GRAPH's hook list for HOOK-TYPE.

Arguments:
  GRAPH - local-graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-FUNCTION - Function accepting (graph operation data)

Side Effects:
  Adds hook-function to appropriate hook list

Examples:
  (add-hook-to-graph graph 'add-hooks #'my-logger)"
  (ecase hook-type
    (add-hooks
     (pushnew hook-function (graph-add-hooks graph)))
    (delete-hooks
     (pushnew hook-function (graph-delete-hooks graph)))
    (query-hooks
     (pushnew hook-function (graph-query-hooks graph)))))

(defun remove-hook-from-graph (graph hook-type hook-function)
  "Remove HOOK-FUNCTION from GRAPH's hook list for HOOK-TYPE.

Arguments:
  GRAPH - local-graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks
  HOOK-FUNCTION - Function to remove

Side Effects:
  Removes hook-function from appropriate hook list

Examples:
  (remove-hook-from-graph graph 'add-hooks #'my-logger)"
  (ecase hook-type
    (add-hooks
     (setf (graph-add-hooks graph)
           (remove hook-function (graph-add-hooks graph))))
    (delete-hooks
     (setf (graph-delete-hooks graph)
           (remove hook-function (graph-delete-hooks graph))))
    (query-hooks
     (setf (graph-query-hooks graph)
           (remove hook-function (graph-query-hooks graph))))))

(defun get-graph-hooks (graph hook-type)
  "Get list of hook functions for HOOK-TYPE from GRAPH.

Arguments:
  GRAPH - local-graph instance
  HOOK-TYPE - One of 'add-hooks, 'delete-hooks, 'query-hooks

Returns:
  List of hook functions

Examples:
  (get-graph-hooks graph 'add-hooks) => (#<FUNCTION MY-LOGGER>)"
  (ecase hook-type
    (add-hooks (graph-add-hooks graph))
    (delete-hooks (graph-delete-hooks graph))
    (query-hooks (graph-query-hooks graph))))

;;;; Phase 4: Triple Retrieval

(defun %expand-dual-entry (key pair index-type)
  "Helper: Expand a (key . values) pair into triples based on index type."
  (let ((dual-key (car pair))
        (values (cdr pair)))
    (mapcar (lambda (value)
              (ecase index-type
                (spo (list key dual-key value))
                (osp (list dual-key key value))
                (pos (list value key dual-key))))
            values)))

#+sbcl
(defun expand-duals (alist key &optional (index-type 'spo))
  "Expand nested alist structure into flat list of triples with parallel processing (SBCL).

Arguments:
  ALIST - Nested alist from hash table
  KEY - Primary key for the index
  INDEX-TYPE - One of 'spo, 'osp, 'pos (default 'spo)

Returns:
  List of triples

For large datasets (100+ entries), uses parallel processing for performance.

Examples:
  (expand-duals '((foaf@name . (\"Alice\" \"Bob\"))) 'alice 'spo)
  => ((alice foaf@name \"Alice\") (alice foaf@name \"Bob\"))"
  ;; Use parallel processing for 100+ entries
  (if (< (length alist) 100)
      ;; Small dataset - sequential
      (alexandria:mappend
       (lambda (pair) (%expand-dual-entry key pair index-type))
       alist)
      ;; Large dataset - parallel processing
      (let* ((num-threads 4)  ; Hardcoded: 4 threads for parallel processing
             (chunk-size (ceiling (/ (length alist) num-threads)))
             (chunks (loop for i from 0 below (length alist) by chunk-size
                           collect (subseq alist i (min (+ i chunk-size)
                                                        (length alist)))))
             (threads nil)
             (results nil))
        ;; Spawn threads to process chunks in parallel
        (dolist (chunk chunks)
          (push (make-thread
                 (lambda (c k idx)
                   (alexandria:mappend
                    (lambda (pair) (%expand-dual-entry k pair idx))
                    c))
                 :arguments (list chunk key index-type)
                 :name "expand-duals-worker")
                threads))
        ;; Join threads and collect results
        (dolist (thread (reverse threads))
          (push (join-thread thread) results))
        ;; Flatten results
        (apply #'append (reverse results)))))

#+ecl
(defun expand-duals (alist key &optional (index-type 'spo))
  "Expand nested alist structure into flat list of triples (ECL - sequential).

Arguments:
  ALIST - Nested alist from hash table
  KEY - Primary key for the index
  INDEX-TYPE - One of 'spo, 'osp, 'pos (default 'spo)

Returns:
  List of triples

Examples:
  (expand-duals '((foaf@name . (\"Alice\" \"Bob\"))) 'alice 'spo)
  => ((alice foaf@name \"Alice\") (alice foaf@name \"Bob\"))"
  (alexandria:mappend
   (lambda (pair) (%expand-dual-entry key pair index-type))
   alist))

(defun %transform-a-to-rdf-type (triple)
  "Helper: Transform 'a' predicate to rdf@type in triple."
  (if (eq (second triple) 'a)
      (list (first triple) 'rdf@type (third triple))
      triple))

(defun transform-a-results-to-rdf-type (triples)
  "Transform triples with 'a' predicate to use rdf@type.

Arguments:
  TRIPLES - List of triples

Returns:
  List of triples with 'a' replaced by rdf@type

Examples:
  (transform-a-results-to-rdf-type '((alice a foaf@Person)))
  => ((alice rdf@type foaf@Person))"
  (mapcar #'%transform-a-to-rdf-type triples))

(defun %collect-spo-keys (graph)
  "Helper: Collect all subject keys from SPO index."
  (let ((keys nil))
    (maphash (lambda (k v)
               (declare (ignore v))
               (push k keys))
             (graph-spo graph))
    keys))

(defun %query-universal (graph)
  "Helper: Query for all triples (t t t pattern)."
  (let ((all-triples nil))
    (dolist (subject (%collect-spo-keys graph))
      (let ((subject-triples (expand-duals
                              (gethash subject (graph-spo graph))
                              subject
                              'spo)))
        (setf all-triples (nconc all-triples subject-triples))))
    ;; Transform 'a' to rdf@type
    (transform-a-results-to-rdf-type all-triples)))

(defun %query-by-subject (s p graph)
  "Helper: Query SPO index by subject."
  (let ((results (expand-duals (gethash s (graph-spo graph)) s 'spo)))
    (if (eq p 'rdf@type)
        (transform-a-results-to-rdf-type results)
        results)))

(defun %query-by-predicate (p graph)
  "Helper: Query POS index by predicate."
  (let ((normalized-p (if (eq p 'rdf@type) 'a p)))
    (let ((results (expand-duals (gethash normalized-p (graph-pos graph))
                                  normalized-p
                                  'pos)))
      (if (eq p 'rdf@type)
          (transform-a-results-to-rdf-type results)
          results))))

(defun %query-by-object (o p graph)
  "Helper: Query OSP index by object."
  (let ((results (expand-duals (gethash o (graph-osp graph)) o 'osp)))
    (if (eq p 'rdf@type)
        (transform-a-results-to-rdf-type results)
        results)))

(defgeneric triples (pattern graph)
  (:documentation "Retrieve triples matching PATTERN from GRAPH.

Arguments:
  PATTERN - List of (subject predicate object), use T as wildcard
  GRAPH - local-graph instance

Returns:
  List of matching triples with content references resolved

Examples:
  (triples '(alice t t) graph)
  (triples '(t foaf@name t) graph)
  (triples '(t t foaf@Person) graph)"))

(defmethod triples (pattern (graph local-graph))
  (let ((s (first pattern))
        (p (second pattern))
        (o (third pattern)))
    (cond
      ((not (var-or-wildp s)) (%query-by-subject s p graph))
      ((not (var-or-wildp p)) (%query-by-predicate p graph))
      ((not (var-or-wildp o)) (%query-by-object o p graph))
      (t (%query-universal graph)))))

(defgeneric raw-triples (pattern graph)
  (:documentation "Retrieve triples without resolving content references.

Arguments:
  PATTERN - List of (subject predicate object), use T as wildcard
  GRAPH - local-graph instance

Returns:
  List of matching triples with content references preserved

Examples:
  (raw-triples '(t t t) graph)"))

(defmethod raw-triples (pattern (graph local-graph))
  ;; For now, identical to triples - content reference resolution
  ;; will be added in Phase 8
  (triples pattern graph))

;;;; Phase 5: Pattern Matching

(defun %match-element (pattern-elem triple-elem bindings)
  "Helper: Match single element, return updated bindings or NIL."
  (cond
    ((wildcardp pattern-elem) bindings)
    ((variablep pattern-elem)
     (let ((existing (assoc pattern-elem bindings :test #'eq)))
       (if existing
           (if (equal (cdr existing) triple-elem)
               bindings
               nil)
           (acons pattern-elem triple-elem bindings))))
    ((equal pattern-elem triple-elem) bindings)
    (t nil)))

(defun pat-match (pattern triple &optional bindings)
  "Match PATTERN against TRIPLE, return bindings or NIL.

Arguments:
  PATTERN - List of (s p o) with variables ($var) or wildcards (t)
  TRIPLE - List of (s p o) concrete values
  BINDINGS - Optional existing bindings alist

Returns:
  Updated bindings alist if match succeeds, NIL otherwise

Examples:
  (pat-match '($s foaf@name \"Alice\") '(alice foaf@name \"Alice\"))
  => (($s . alice))"
  (let ((result-bindings bindings))
    (loop for pattern-elem in pattern
          for triple-elem in triple
          do (setf result-bindings
                   (%match-element pattern-elem triple-elem result-bindings))
          when (null result-bindings)
            do (return-from pat-match nil))
    result-bindings))

(defun %merge-bindings (bindings1 bindings2)
  "Helper: Merge two binding alists, return NIL if conflict."
  (let ((result bindings1))
    (dolist (binding bindings2 result)
      (let ((var (car binding))
            (val (cdr binding)))
        (let ((existing (assoc var result :test #'eq)))
          (cond
            ((null existing)
             (setf result (acons var val result)))
            ((not (equal (cdr existing) val))
             (return-from %merge-bindings nil))))))))

(defun match-triples-against-pattern (pattern triples &optional bindings)
  "Match PATTERN against list of TRIPLES with optional BINDINGS.

Arguments:
  PATTERN - Pattern with variables/wildcards
  TRIPLES - List of concrete triples
  BINDINGS - Optional existing bindings

Returns:
  List of binding alists for successful matches

Examples:
  (match-triples-against-pattern '($s foaf@name $n)
                                  '((alice foaf@name \"Alice\")))
  => ((($n . \"Alice\") ($s . alice)))"
  (let ((results nil))
    (dolist (triple triples (nreverse results))
      (let ((match-result (pat-match pattern triple bindings)))
        (when match-result
          (push match-result results))))))

;;;; Phase 6: Query Engine Core

(defun %apply-pattern-to-bindings (pattern binding graph)
  "Helper: Apply pattern with existing binding, return new bindings."
  (let ((instantiated-pattern
         (mapcar (lambda (elem)
                   (if (variablep elem)
                       (let ((bound-val (cdr (assoc elem binding :test #'eq))))
                         (or bound-val elem))
                       elem))
                 pattern)))
    (let ((matching-triples (triples instantiated-pattern graph)))
      (match-triples-against-pattern pattern matching-triples binding))))

(defun %process-clause (clause binding graph)
  "Helper: Process single clause with binding, return new bindings."
  (if (eq (first clause) 'optional)
      (let ((optional-pattern (second clause)))
        (let ((results (%apply-pattern-to-bindings optional-pattern
                                                    binding
                                                    graph)))
          (if results
              results
              (list binding))))
      (%apply-pattern-to-bindings clause binding graph)))

(defun %process-clauses-with-bindings (clauses bindings graph)
  "Helper: Process remaining clauses with current bindings."
  (if (null clauses)
      bindings
      (let ((new-bindings nil))
        (dolist (binding bindings)
          (let ((clause-results (%process-clause (first clauses)
                                                  binding
                                                  graph)))
            (setf new-bindings (nconc new-bindings clause-results))))
        (%process-clauses-with-bindings (rest clauses) new-bindings graph))))

(defgeneric graph-query (clauses graph)
  (:documentation "Execute query with multiple CLAUSES on GRAPH.

Arguments:
  CLAUSES - List of patterns, supports (OPTIONAL pattern) syntax
  GRAPH - local-graph instance

Returns:
  List of binding alists

Examples:
  (graph-query '(($s foaf@name $n)) graph)
  (graph-query '(($s foaf@name $n) (OPTIONAL ($s foaf@age $a))) graph)"))

(defmethod graph-query (clauses (graph local-graph))
  ;; Trigger query hooks
  (dolist (hook (graph-query-hooks graph))
    (funcall hook graph 'graph-query clauses))

  (if (null clauses)
      nil
      (let ((first-clause (first clauses)))
        (let ((initial-bindings
               (if (eq (first first-clause) 'optional)
                   (list nil)
                   (let ((pattern (if (listp first-clause)
                                      first-clause
                                      (list first-clause))))
                     (match-triples-against-pattern pattern
                                                    (triples pattern graph))))))
          (%process-clauses-with-bindings (rest clauses)
                                          initial-bindings
                                          graph)))))

;;;; Phase 7: Query Operations

(defun select (vars bindings)
  "Project variables VARS from BINDINGS.

Arguments:
  VARS - List of variable symbols to project
  BINDINGS - List of binding alists from query

Returns:
  List of projected binding alists

Examples:
  (select '($name) bindings) => ((($name . \"Alice\")) (($name . \"Bob\")))"
  (mapcar (lambda (binding)
            (mapcar (lambda (var)
                      (assoc var binding :test #'eq))
                    vars))
          bindings))

(defun ask (bindings)
  "Boolean query - check if BINDINGS is non-empty.

Arguments:
  BINDINGS - List of binding alists from query

Returns:
  T if bindings exist, NIL otherwise

Examples:
  (ask bindings) => T"
  (not (null bindings)))

(defun %instantiate-pattern (pattern bindings)
  "Helper: Replace variables in pattern with values from bindings."
  (mapcar (lambda (elem)
            (if (variablep elem)
                (let ((binding (assoc elem bindings :test #'eq)))
                  (if binding
                      (cdr binding)
                      elem))
                elem))
          pattern))

(defun construct (template bindings)
  "Construct new triples from TEMPLATE using BINDINGS.

Arguments:
  TEMPLATE - Triple pattern with variables
  BINDINGS - List of binding alists from query

Returns:
  List of constructed triples

Examples:
  (construct '($s rdf@type foaf@Person) bindings)
  => ((alice rdf@type foaf@Person) (bob rdf@type foaf@Person))"
  (mapcar (lambda (binding)
            (%instantiate-pattern template binding))
          bindings))

(defun filter (predicate bindings)
  "Filter BINDINGS using PREDICATE function.

Arguments:
  PREDICATE - Function accepting binding alist, returns T to keep
  BINDINGS - List of binding alists from query

Returns:
  Filtered list of binding alists

Examples:
  (filter (lambda (b) (> (cdr (assoc '$age b)) 18)) bindings)"
  (remove-if-not predicate bindings))

(defun delete-data (pattern graph)
  "Delete all triples matching PATTERN from GRAPH.

Arguments:
  PATTERN - Triple pattern (may contain variables/wildcards)
  GRAPH - local-graph instance

Side Effects:
  Deletes matching triples from graph
  Triggers delete-hooks

Returns:
  Number of triples deleted

Examples:
  (delete-data '($s foaf@name \"Alice\") graph) => 1"
  (let ((matching-triples (triples pattern graph)))
    (delete-triples matching-triples graph)
    (length matching-triples)))

;;;; Phase 8: Content Reference System

(defvar *content-reference-threshold* 1000
  "Maximum string length before converting to content reference.")

(defun %ensure-content-cache-dir ()
  "Helper: Ensure content cache directory exists and return path."
  (let ((cache-dir (merge-pathnames "cl-rdf/content/"
                                     (uiop:xdg-cache-home))))
    (ensure-directories-exist cache-dir)
    cache-dir))

(defun %compute-content-hash (content)
  "Helper: Compute MD5 hash of CONTENT string."
  (let ((digest (ironclad:make-digest :md5)))
    (ironclad:update-digest digest
                            (ironclad:ascii-string-to-byte-array content))
    (ironclad:byte-array-to-hex-string
     (ironclad:produce-digest digest))))

(defun content-reference-p (value)
  "Return T if VALUE is a content reference string.

Arguments:
  VALUE - Value to test

Returns:
  T if value is content reference, NIL otherwise

Examples:
  (content-reference-p \"file:content-abc123.txt\") => T
  (content-reference-p \"regular string\") => NIL"
  (and (stringp value)
       (>= (length value) 17)
       (alexandria:starts-with-subseq "file:content-" value)
       (alexandria:ends-with-subseq ".txt" value)))

(defun store-large-content (content)
  "Store CONTENT as file reference if it exceeds threshold.

Arguments:
  CONTENT - String content to potentially store

Returns:
  Content reference string or original content

Side Effects:
  May create file in cache directory

Examples:
  (store-large-content \"short\") => \"short\"
  (store-large-content <long-string>) => \"file:content-<hash>.txt\""
  (if (and (stringp content)
           (> (length content) *content-reference-threshold*))
      (let* ((hash (%compute-content-hash content))
             (filename (format nil "content-~A.txt" hash))
             (filepath (merge-pathnames filename (%ensure-content-cache-dir))))
        (with-open-file (stream filepath :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string content stream))
        (format nil "file:~A" filename))
      content))

(defun resolve-content-reference (reference)
  "Resolve content REFERENCE to actual content.

Arguments:
  REFERENCE - Content reference string

Returns:
  Actual content from file

Examples:
  (resolve-content-reference \"file:content-abc123.txt\") => <content>"
  (if (content-reference-p reference)
      (let* ((filename (subseq reference 5))
             (filepath (merge-pathnames filename (%ensure-content-cache-dir))))
        (if (probe-file filepath)
            (uiop:read-file-string filepath)
            reference))
      reference))

(defun %resolve-triple-content (triple)
  "Helper: Resolve content references in a single triple."
  (list (first triple)
        (second triple)
        (if (content-reference-p (third triple))
            (resolve-content-reference (third triple))
            (third triple))))

(defun resolve-all-content-references (triples)
  "Resolve all content references in TRIPLES.

Arguments:
  TRIPLES - List of triples

Returns:
  List of triples with content references resolved

Examples:
  (resolve-all-content-references triples)"
  (mapcar #'%resolve-triple-content triples))

;;;; Phase 9: Serialization and Format Conversion

(defun triples-to-string (triples)
  "Serialize TRIPLES to string representation.

Arguments:
  TRIPLES - List of triples

Returns:
  String representation suitable for read-from-string

Examples:
  (triples-to-string '((alice foaf@name \"Alice\")))
  => \"((alice foaf@name \\\"Alice\\\"))\""
  (with-output-to-string (out)
    (write triples :stream out :case :downcase :readably t)))

(defun el-rdf-symbol-p (symbol)
  "Return T if SYMBOL uses el-rdf format (contains colon).

Arguments:
  SYMBOL - Symbol to test

Returns:
  T if symbol has colon separator, NIL otherwise

Examples:
  (el-rdf-symbol-p '|foaf:name|) => T
  (el-rdf-symbol-p 'foaf@name) => NIL"
  (and (symbolp symbol)
       (find #\: (symbol-name symbol) :test #'char=)))

(defun convert-symbol-el-to-cl (symbol)
  "Convert el-rdf symbol to cl-rdf format (: to @).

Arguments:
  SYMBOL - Symbol with : separator

Returns:
  Symbol with @ separator

Examples:
  (convert-symbol-el-to-cl '|foaf:name|) => foaf@name
  (convert-symbol-el-to-cl '|rdf:type|) => rdf@type"
  (if (el-rdf-symbol-p symbol)
      (let ((name (symbol-name symbol)))
        (intern (substitute #\@ #\: name) (symbol-package symbol)))
      symbol))

(defun %convert-triple-element (elem)
  "Helper: Convert a single triple element from el-rdf to cl-rdf."
  (cond
    ((el-rdf-symbol-p elem) (convert-symbol-el-to-cl elem))
    ((listp elem) (mapcar #'%convert-triple-element elem))
    (t elem)))

(defun convert-triple-el-to-cl (triple)
  "Convert triple from el-rdf format to cl-rdf format.

Arguments:
  TRIPLE - Triple using el-rdf symbol format

Returns:
  Triple using cl-rdf symbol format

Examples:
  (convert-triple-el-to-cl '(|alice| |foaf:name| \"Alice\"))
  => (|alice| foaf@name \"Alice\")"
  (mapcar #'%convert-triple-element triple))

(defun %convert-el-to-cl-in-string (content)
  "Convert el-rdf format to cl-rdf in string, preserving strings and keywords.

Replaces : with @ outside of quoted strings to convert
namespace:resource to namespace@resource format.
Preserves keywords (symbols starting with :).

Arguments:
  CONTENT - String with el-rdf format symbols

Returns:
  String with cl-rdf format symbols"
  (with-output-to-string (out)
    (loop with in-string = nil
          with escape-next = nil
          with prev-char = nil
          for ch across content
          do (cond
               (escape-next
                (write-char ch out)
                (setf escape-next nil
                      prev-char ch))
               ((and (char= ch #\\) in-string)
                (write-char ch out)
                (setf escape-next t
                      prev-char ch))
               ((char= ch #\")
                (write-char ch out)
                (setf in-string (not in-string)
                      prev-char ch))
               ;; Replace : with @ only if preceded by alphanumeric
               ((and (char= ch #\:)
                     (not in-string)
                     prev-char
                     (or (alphanumericp prev-char)
                         (char= prev-char #\-)))
                (write-char #\@ out)
                (setf prev-char #\@))
               (t
                (write-char ch out)
                (setf prev-char ch))))))

(defun save-graph (graph filename)
  "Save GRAPH triples to FILENAME in cl-rdf format.

Arguments:
  GRAPH - local-graph instance
  FILENAME - Path to save file

Side Effects:
  Writes file to filesystem

Examples:
  (save-graph graph \"/tmp/my-graph.rdf\")"
  (let* ((triples (raw-triples '(t t t) graph))
         (serialized (triples-to-string triples)))
    (with-open-file (out filename :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write-string serialized out))))

(defun load-graph (graph filename)
  "Load triples from FILENAME into GRAPH with auto-format detection.

Arguments:
  GRAPH - local-graph instance
  FILENAME - Path to load file

Side Effects:
  Adds triples to graph
  Auto-converts el-rdf format to cl-rdf format

Examples:
  (load-graph graph \"/tmp/my-graph.rdf\")"
  (let* ((content (uiop:read-file-string filename))
         (processed (%convert-el-to-cl-in-string content))
         (triples (read-from-string processed)))
    (add-triples triples graph)))

;;;; Phase 10: Checkpointing System

(defvar *graph-checkpoints* (make-hash-table :test 'eq)
  "Hash table mapping graphs to their checkpoint information.")

(defun get-checkpoint-dir ()
  "Get the checkpoint directory path, creating it if needed.

Returns:
  Pathname of checkpoint directory

Examples:
  (get-checkpoint-dir) => #P\"/home/user/.cache/cl-rdf/checkpoints/\""
  (let ((checkpoint-dir (merge-pathnames "cl-rdf/checkpoints/"
                                         (uiop:xdg-cache-home))))
    (ensure-directories-exist checkpoint-dir)
    checkpoint-dir))

(defun checkpoint-file-path (graph-name)
  "Get checkpoint file path for GRAPH-NAME.

Arguments:
  GRAPH-NAME - String name of graph

Returns:
  Pathname of checkpoint file

Examples:
  (checkpoint-file-path \"my-graph\")
  => #P\"/home/user/.cache/cl-rdf/checkpoints/my-graph.checkpoint\""
  (merge-pathnames (format nil "~A.checkpoint" graph-name)
                   (get-checkpoint-dir)))

(defun register-graph-for-checkpointing (graph graph-name)
  "Register GRAPH for automatic checkpointing with GRAPH-NAME.

Arguments:
  GRAPH - local-graph instance
  GRAPH-NAME - String name for checkpoint files

Side Effects:
  Registers graph in *graph-checkpoints*
  Adds checkpoint-hook to add-hooks and delete-hooks

Examples:
  (register-graph-for-checkpointing graph \"my-graph\")"
  (setf (gethash graph *graph-checkpoints*)
        (cons graph-name (get-universal-time)))
  (add-hook-to-graph graph 'add-hooks #'checkpoint-hook)
  (add-hook-to-graph graph 'delete-hooks #'checkpoint-hook))

(defun checkpoint-hook (graph operation data)
  "Hook function that checkpoints registered graphs.

Arguments:
  GRAPH - local-graph instance
  OPERATION - Symbol indicating operation type
  DATA - Operation data (triples)

Side Effects:
  Saves checkpoint if graph is registered

Examples:
  Called automatically via hooks"
  (let ((checkpoint-info (gethash graph *graph-checkpoints*)))
    (when checkpoint-info
      (let* ((graph-name (car checkpoint-info))
             (checkpoint-file (checkpoint-file-path graph-name)))
        (save-graph graph checkpoint-file)
        (save-checkpoint-metadata graph-name operation data)
        (setf (gethash graph *graph-checkpoints*)
              (cons graph-name (get-universal-time)))))))

(defun save-named-graph (graph)
  "Save checkpoint for registered GRAPH using its name.

Arguments:
  GRAPH - local-graph instance

Side Effects:
  Saves checkpoint file

Examples:
  (save-named-graph graph)"
  (let ((checkpoint-info (gethash graph *graph-checkpoints*)))
    (when checkpoint-info
      (let* ((graph-name (car checkpoint-info))
             (checkpoint-file (checkpoint-file-path graph-name)))
        (save-graph graph checkpoint-file)))))

(defun restore-named-graph (graph-name)
  "Restore graph from checkpoint file for GRAPH-NAME.

Arguments:
  GRAPH-NAME - String name of checkpoint

Returns:
  New local-graph instance with restored data

Examples:
  (restore-named-graph \"my-graph\") => #<LOCAL-GRAPH my-graph>"
  (let ((checkpoint-file (checkpoint-file-path graph-name)))
    (when (probe-file checkpoint-file)
      (let ((graph (make-graph graph-name)))
        (load-graph graph checkpoint-file)
        graph))))

(defun save-checkpoint-metadata (graph-name operation data)
  "Save metadata about checkpoint operation.

Arguments:
  GRAPH-NAME - String name of graph
  OPERATION - Symbol indicating operation type
  DATA - Operation data

Side Effects:
  Writes metadata file

Examples:
  (save-checkpoint-metadata \"my-graph\" 'add-triples triples)"
  (let ((metadata-file (merge-pathnames
                        (format nil "~A.metadata" graph-name)
                        (get-checkpoint-dir))))
    (with-open-file (out metadata-file :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write (list :last-operation operation
                   :data-size (length data)
                   :timestamp (get-universal-time))
             :stream out :case :downcase :readably t))))

(defun load-checkpoint-metadata (graph-name)
  "Load checkpoint metadata for GRAPH-NAME.

Arguments:
  GRAPH-NAME - String name of graph

Returns:
  Plist of metadata or NIL if not found

Examples:
  (load-checkpoint-metadata \"my-graph\")
  => (:last-operation add-triples :data-size 10 :timestamp 3918234156)"
  (let ((metadata-file (merge-pathnames
                        (format nil "~A.metadata" graph-name)
                        (get-checkpoint-dir))))
    (when (probe-file metadata-file)
      (with-open-file (in metadata-file :direction :input)
        (read in)))))

(defun list-checkpoints ()
  "List all available checkpoint files.

Returns:
  List of checkpoint filenames

Examples:
  (list-checkpoints)
  => (\"graph1.checkpoint\" \"graph2.checkpoint\")"
  (let ((checkpoint-dir (get-checkpoint-dir)))
    (when (probe-file checkpoint-dir)
      (mapcar #'file-namestring
              (uiop:directory-files checkpoint-dir "*.checkpoint")))))

(defun delete-checkpoint (graph-name)
  "Delete checkpoint files for GRAPH-NAME.

Removes both checkpoint file and metadata file.

Arguments:
  GRAPH-NAME - String name of checkpoint to delete

Side Effects:
  Deletes checkpoint and metadata files
  Removes from *graph-checkpoints* if registered

Examples:
  (delete-checkpoint \"my-graph\")"
  (let* ((checkpoint-file (checkpoint-file-path graph-name))
         (metadata-file (merge-pathnames
                         (format nil "~A.metadata" graph-name)
                         (get-checkpoint-dir))))
    (when (probe-file checkpoint-file)
      (delete-file checkpoint-file))
    (when (probe-file metadata-file)
      (delete-file metadata-file))
    ;; Remove from registered checkpoints if present
    (maphash (lambda (graph info)
               (when (string= (car info) graph-name)
                 (remhash graph *graph-checkpoints*)))
             *graph-checkpoints*)))

;;;; Phase 11: TTL Import

(defun register-prefix (graph prefix namespace-uri)
  "Register PREFIX to expand to NAMESPACE-URI in GRAPH.

Arguments:
  GRAPH - local-graph instance
  PREFIX - String prefix (e.g., \"foaf\", \"schema\")
  NAMESPACE-URI - Full namespace URI

Side Effects:
  Adds prefix mapping to graph

Examples:
  (register-prefix graph \"foaf\" \"http://xmlns.com/foaf/0.1/\")"
  (setf (graph-prefixes graph)
        (acons prefix namespace-uri (graph-prefixes graph))))

(defun expand-prefixed-iri (graph prefixed-iri)
  "Expand prefixed IRI to full IRI using GRAPH prefixes.

Arguments:
  GRAPH - local-graph instance
  PREFIXED-IRI - String like \"schema:Person\" or \"foaf:name\"

Returns:
  Full IRI string or original if no prefix match

Examples:
  (expand-prefixed-iri graph \"foaf:name\")
  => \"http://xmlns.com/foaf/0.1/name\""
  (if (and (stringp prefixed-iri)
           (find #\: prefixed-iri :test #'char=))
      (let* ((colon-pos (position #\: prefixed-iri))
             (prefix (subseq prefixed-iri 0 colon-pos))
             (local-part (subseq prefixed-iri (1+ colon-pos)))
             (namespace-uri (cdr (assoc prefix (graph-prefixes graph)
                                        :test #'string=))))
        (if namespace-uri
            (concatenate 'string namespace-uri local-part)
            prefixed-iri))
      prefixed-iri))

(defun %compress-iri-with-prefix (iri prefixes)
  "Helper: Try to compress IRI using registered prefixes."
  (dolist (prefix-entry prefixes iri)
    (let ((prefix (car prefix-entry))
          (namespace-uri (cdr prefix-entry)))
      (when (alexandria:starts-with-subseq namespace-uri iri :test #'char=)
        (return (format nil "~A@~A"
                        prefix
                        (subseq iri (length namespace-uri))))))))

(defun intern-rdf-resource (graph resource-string &optional namespace)
  "Convert RDF resource string to symbol with @ separator.

Arguments:
  GRAPH - local-graph instance
  RESOURCE-STRING - Resource string
  NAMESPACE - Optional namespace prefix

Returns:
  Interned symbol in cl-rdf format

Examples:
  (intern-rdf-resource graph \"foaf:name\") => foaf@name
  (intern-rdf-resource graph \":name\" \"foaf\") => foaf@name"
  (let ((final-resource
         (cond
           ((and namespace (alexandria:starts-with-subseq ":" resource-string))
            (format nil "~A@~A" namespace (subseq resource-string 1)))
           ((and namespace (not (find #\: resource-string :test #'char=)))
            (format nil "~A@~A" namespace resource-string))
           ((find #\: resource-string :test #'char=)
            (let ((expanded (expand-prefixed-iri graph resource-string)))
              ;; If expanded to full IRI, compress back with @
              (if (string= expanded resource-string)
                  ;; Not expanded, just substitute : with @
                  (substitute #\@ #\: resource-string)
                  ;; Was expanded, compress IRI with registered prefixes
                  (%compress-iri-with-prefix expanded (graph-prefixes graph)))))
           (t resource-string))))
    (intern final-resource)))

(defun parse-ttl-value (graph value-string &optional namespace)
  "Parse TTL value into appropriate Lisp form.

Arguments:
  GRAPH - local-graph instance
  VALUE-STRING - String value from TTL
  NAMESPACE - Optional namespace prefix

Returns:
  Parsed value (symbol, string, number, etc.)

Examples:
  (parse-ttl-value graph \"<http://example.org/foo>\") => symbol
  (parse-ttl-value graph \"\\\"Alice\\\"\") => \"Alice\""
  (cond
    ((string= value-string "a") 'a)
    ((alexandria:starts-with-subseq "<" value-string)
     (let ((iri (subseq value-string 1 (1- (length value-string)))))
       (intern (%compress-iri-with-prefix iri (graph-prefixes graph)))))
    ((alexandria:starts-with-subseq "\"" value-string)
     (%parse-quoted-string value-string))
    ((alexandria:starts-with-subseq "_:" value-string) (bnode))
    ((find #\: value-string :test #'char=)
     (intern-rdf-resource graph value-string namespace))
    (t (intern-rdf-resource graph value-string namespace))))

(defun %parse-quoted-string (value-string)
  "Helper: Parse quoted string, handle language tags and datatypes."
  (let* ((content-end (or (position #\" value-string :from-end t) 0))
         (content (subseq value-string 1 content-end))
         (rest-of-string (subseq value-string (min (1+ content-end)
                                                    (length value-string)))))
    (cond
      ((alexandria:starts-with-subseq "^^" rest-of-string)
       (let ((datatype-start (+ 2 (or (position #\< rest-of-string) 0)))
             (datatype-end (or (position #\> rest-of-string) 0)))
         (if (and (> datatype-end 0)
                  (string= "http://www.w3.org/2001/XMLSchema#integer"
                           (subseq rest-of-string datatype-start datatype-end)))
             (parse-integer content :junk-allowed t)
             content)))
      ((alexandria:starts-with-subseq "@" rest-of-string) content)
      (t content))))

(defun simple-tokenize-ttl (content)
  "Tokenize TTL CONTENT string into list of tokens.

Arguments:
  CONTENT - TTL file content string

Returns:
  Vector of token strings

Examples:
  (simple-tokenize-ttl \"@prefix foaf: <...> .\")
  => #(\"@prefix\" \"foaf:\" \"<...>\" \".\")"
  (coerce (%tokenize-ttl content) 'vector))

(defun %tokenize-ttl (content)
  "Helper: Tokenize TTL content, returns list."
  (let ((tokens nil)
        (pos 0)
        (len (length content)))
    (loop while (< pos len)
          do (multiple-value-bind (token new-pos)
                 (%read-next-token content pos len)
               (when token
                 (push token tokens))
               (setf pos new-pos)))
    (nreverse tokens)))

(defun %read-next-token (content pos len)
  "Helper: Read next token from content at pos, return (token new-pos)."
  (let ((ch (char content pos)))
    (cond
      ((member ch '(#\Space #\Tab #\Newline #\Return))
       (values nil (1+ pos)))
      ((char= ch #\#) (%skip-comment content pos len))
      ((char= ch #\") (%read-quoted-string content pos len))
      ((char= ch #\<) (%read-angle-bracket-iri content pos len))
      ((member ch '(#\; #\. #\, #\[ #\] #\( #\)))
       (values (string ch) (1+ pos)))
      (t (%read-regular-token content pos len)))))

(defun %skip-comment (content pos len)
  "Helper: Skip comment to end of line."
  (loop while (and (< pos len)
                   (not (member (char content pos) '(#\Newline #\Return))))
        do (incf pos))
  (values nil pos))

(defun %read-quoted-string (content pos len)
  "Helper: Read quoted string token."
  (let ((start pos))
    (incf pos)
    (loop while (and (< pos len) (char/= (char content pos) #\"))
          do (when (char= (char content pos) #\\)
               (incf pos))
             (incf pos))
    (when (< pos len) (incf pos))
    (values (subseq content start pos) pos)))

(defun %read-angle-bracket-iri (content pos len)
  "Helper: Read angle bracket IRI token."
  (let ((start pos))
    (loop while (and (< pos len) (char/= (char content pos) #\>))
          do (incf pos))
    (when (< pos len) (incf pos))
    (values (subseq content start pos) pos)))

(defun %read-regular-token (content pos len)
  "Helper: Read regular token (prefix, resource, etc.)."
  (let ((start pos))
    (loop while (and (< pos len)
                     (not (member (char content pos)
                                  '(#\Space #\Tab #\Newline #\Return
                                    #\; #\, #\< #\" #\[ #\] #\( #\)))))
          do (incf pos))
    (values (subseq content start pos) pos)))

(defun parse-rdf-collection (tokens pos graph namespace)
  "Parse RDF collection ( ... ) into linked list structure.

Arguments:
  TOKENS - Vector of token strings
  POS - Current position in tokens
  GRAPH - local-graph instance
  NAMESPACE - Optional namespace prefix

Returns:
  (list-head . (triples . next-pos))

Examples:
  (parse-rdf-collection tokens 5 graph nil)
  => (_:G1 . (((triples)) . 10))"
  (let ((triples nil)
        (list-head nil)
        (prev-node nil))
    (when (and (< pos (length tokens))
               (string= (aref tokens pos) "("))
      (incf pos)
      (if (and (< pos (length tokens))
               (string= (aref tokens pos) ")"))
          (progn (incf pos)
                 (setf list-head 'rdf@nil))
          (progn
            (loop while (and (< pos (length tokens))
                             (not (string= (aref tokens pos) ")")))
                  do (let* ((item (aref tokens pos))
                            (current-node (bnode))
                            (parsed-item (if (symbolp item)
                                             item
                                             (parse-ttl-value graph item namespace))))
                       (unless list-head
                         (setf list-head current-node))
                       (when prev-node
                         (push (list prev-node 'rdf@rest current-node) triples))
                       (push (list current-node 'rdf@first parsed-item) triples)
                       (setf prev-node current-node)
                       (incf pos)))
            (when prev-node
              (push (list prev-node 'rdf@rest 'rdf@nil) triples))
            (when (and (< pos (length tokens))
                       (string= (aref tokens pos) ")"))
              (incf pos)))))
    (cons (or list-head 'rdf@nil) (cons (nreverse triples) pos))))

(defun parse-blank-node-bracket (tokens pos graph namespace)
  "Parse blank node bracket [ ... ] into triples.

Arguments:
  TOKENS - Vector of token strings
  POS - Current position in tokens
  GRAPH - local-graph instance
  NAMESPACE - Optional namespace prefix

Returns:
  (blank-node . (triples . next-pos))

Examples:
  (parse-blank-node-bracket tokens 3 graph nil)
  => (_:G1 . (((triples)) . 8))"
  (let ((blank-node (bnode))
        (triples nil)
        (current-pos pos))
    (when (and (< current-pos (length tokens))
               (string= (aref tokens current-pos) "["))
      (incf current-pos)
      (loop while (and (< current-pos (length tokens))
                       (not (string= (aref tokens current-pos) "]")))
            when (< (1+ current-pos) (length tokens))
              do (let ((predicate (aref tokens current-pos)))
                   (incf current-pos)
                   (setf current-pos
                         (%parse-bracket-objects tokens current-pos graph namespace
                                                blank-node predicate triples))
                   (when (and (< current-pos (length tokens))
                              (string= (aref tokens current-pos) ";"))
                     (incf current-pos))))
      (when (and (< current-pos (length tokens))
                 (string= (aref tokens current-pos) "]"))
        (incf current-pos)))
    (cons blank-node (cons (nreverse triples) current-pos))))

(defun %parse-bracket-objects (tokens pos graph namespace blank-node pred triples)
  "Helper: Parse objects in bracket notation for predicate. Returns new pos."
  (let ((current-pos pos))
    (loop while (and (< current-pos (length tokens))
                     (not (member (aref tokens current-pos) '(";" "]") :test #'string=)))
          do (let ((object (aref tokens current-pos)))
               (unless (string= object ",")
                 (let ((processed-obj (parse-ttl-value graph object namespace)))
                   (push (list blank-node pred processed-obj) triples)))
               (incf current-pos)
               (when (and (< current-pos (length tokens))
                          (string= (aref tokens current-pos) ","))
                 (incf current-pos))))
    current-pos))

(defun parse-simple-ttl-statement (tokens start-pos graph namespace)
  "Parse single TTL statement from TOKENS.

Arguments:
  TOKENS - Vector of token strings
  START-POS - Starting position
  GRAPH - local-graph instance
  NAMESPACE - Optional namespace prefix

Returns:
  (triples . next-pos)

Examples:
  (parse-simple-ttl-statement tokens 0 graph nil)
  => (((triples)) . 5)"
  (let ((current-pos start-pos)
        (len (length tokens))
        (triples nil)
        (subject nil))
    (when (< current-pos len)
      (setf subject (parse-ttl-value graph (aref tokens current-pos) namespace))
      (incf current-pos)
      (setf current-pos
            (%parse-statement-predicates tokens current-pos len graph namespace
                                        subject triples))
      (when (and (< current-pos len) (string= (aref tokens current-pos) "."))
        (incf current-pos)))
    (cons (nreverse triples) current-pos)))

(defun %parse-statement-predicates (tokens pos len graph ns subject triples)
  "Helper: Parse predicate-object pairs for statement. Returns new pos."
  (let ((current-pos pos))
    (loop while (and (< current-pos len)
                     (not (string= (aref tokens current-pos) ".")))
          when (< (1+ current-pos) len)
            do (let ((predicate (parse-ttl-value graph (aref tokens current-pos) ns)))
                 (incf current-pos)
                 (setf current-pos
                       (%parse-statement-objects tokens current-pos len graph ns
                                                subject predicate triples))
                 (when (and (< current-pos len) (string= (aref tokens current-pos) ";"))
                   (incf current-pos))))
    current-pos))

(defun %parse-statement-objects (tokens pos len graph ns subj pred triples)
  "Helper: Parse objects for predicate in statement. Returns new pos."
  (let ((current-pos pos))
    (loop while (and (< current-pos len)
                     (not (member (aref tokens current-pos) '(";" ".") :test #'string=)))
          do (let ((object (aref tokens current-pos)))
               (unless (string= object ",")
                 (let ((parsed-obj (parse-ttl-value graph object ns)))
                   (push (list subj pred parsed-obj) triples)))
               (incf current-pos)
               (when (and (< current-pos len) (string= (aref tokens current-pos) ","))
                 (incf current-pos))))
    current-pos))

(defun parse-ttl-content (graph content &optional namespace)
  "Parse TTL CONTENT string and add triples to GRAPH.

Arguments:
  GRAPH - local-graph instance
  CONTENT - TTL file content string
  NAMESPACE - Optional namespace prefix for resources

Side Effects:
  Adds triples to graph
  Registers prefix directives

Examples:
  (parse-ttl-content graph ttl-string nil)"
  (%extract-prefix-directives graph content)
  (let* ((token-list (%tokenize-ttl content))
         (tokens (coerce token-list 'vector))
         (pos 0)
         (len (length tokens)))
    (loop while (< pos len)
          do (let ((token (aref tokens pos)))
               (cond
                 ((string= token "@prefix")
                  (setf pos (%skip-prefix-directive tokens pos len)))
                 ((and token (alexandria:starts-with-subseq "#" token))
                  (incf pos))
                 (t
                  (multiple-value-bind (triples next-pos)
                      (%parse-and-add-statement tokens pos graph namespace)
                    (declare (ignore triples))
                    (setf pos next-pos))))))))

(defun %extract-prefix-directives (graph content)
  "Helper: Extract @prefix directives from content."
  (let ((lines (uiop:split-string content :separator '(#\Newline))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab) line)))
        (when (alexandria:starts-with-subseq "@prefix" trimmed)
          (%register-prefix-from-line graph trimmed))))))

(defun %register-prefix-from-line (graph line)
  "Helper: Register prefix from @prefix line."
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings "@prefix\\s+(\\S+):\\s*<([^>]+)>" line)
    (declare (ignore match))
    (when groups
      (register-prefix graph (aref groups 0) (aref groups 1)))))

(defun %skip-prefix-directive (tokens pos len)
  "Helper: Skip @prefix directive tokens."
  (loop while (and (< pos len)
                   (not (string= (aref tokens pos) ".")))
        do (incf pos))
  (when (< pos len) (incf pos))
  pos)

(defun %parse-and-add-statement (tokens pos graph namespace)
  "Helper: Parse statement and add triples to graph."
  (let ((result (parse-simple-ttl-statement tokens pos graph namespace)))
    (let ((triples (car result))
          (next-pos (cdr result)))
      (dolist (triple triples)
        (when (= (length triple) 3)
          (add-triple triple graph)))
      (values triples next-pos))))

(defun import-ttl (filename graph &optional namespace)
  "Import TTL file into GRAPH.

Arguments:
  FILENAME - Path to TTL file
  GRAPH - local-graph instance
  NAMESPACE - Optional namespace prefix for resources

Side Effects:
  Adds triples to graph from TTL file
  Registers prefix directives

Examples:
  (import-ttl \"/path/to/file.ttl\" graph)
  (import-ttl \"/path/to/file.ttl\" graph \"myns\")"
  (when (probe-file filename)
    (let ((content (uiop:read-file-string filename)))
      (parse-ttl-content graph content namespace))
    graph))

;;;; Phase 12: Visualization

(defun namespace (symbol)
  "Extract namespace prefix from SYMBOL with @ separator.

Arguments:
  SYMBOL - Symbol with namespace@resource format

Returns:
  Namespace string before @ separator

Examples:
  (namespace 'foaf@name) => \"foaf\"
  (namespace 'schema@Person) => \"schema\""
  (let ((name (symbol-name symbol)))
    (let ((at-pos (position #\@ name)))
      (if at-pos
          (subseq name 0 at-pos)
          name))))

(defun nodes (triples)
  "Extract all unique nodes from TRIPLES (subjects and objects only).

Arguments:
  TRIPLES - List of triples

Returns:
  List of unique nodes (subjects and objects)

Examples:
  (nodes '((alice foaf@name \"Alice\"))) => (alice \"Alice\")"
  (remove-duplicates
   (append (mapcar #'first triples)
           (mapcar #'third triples))
   :test #'equal))

(defun literals (nodelist)
  "Filter non-symbol nodes from NODELIST (strings, numbers, etc).

Arguments:
  NODELIST - List of nodes

Returns:
  List of literal values (non-symbols)

Examples:
  (literals '(alice \"Alice\" 30)) => (\"Alice\" 30)"
  (remove-if #'symbolp nodelist))

(defun render-triple (triple)
  "Render TRIPLE to Graphviz DOT format.

If object is a symbol, creates an edge between subject and object.
If object is a literal, creates an edge to a generated node with box shape.

Arguments:
  TRIPLE - Triple to render

Returns:
  DOT format string

Examples:
  (render-triple '(alice foaf@knows bob))
  => \"\\\"alice\\\" -> \\\"bob\\\" [label=\\\"foaf@knows\\\"];\\n\""
  (destructuring-bind (subject predicate object) triple
    (if (symbolp object)
        (format nil "\"~A\" -> \"~A\" [label=\"~A\"];~%" subject object predicate)
        (let ((literal-node (gensym "LIT")))
          (format nil "\"~A\" -> \"~A\" [label=\"~A\"];~%~A [label=\"~A\",shape=box];~%"
                  subject literal-node predicate literal-node object)))))

(defun filter-triples (pattern triples)
  "Filter TRIPLES that match PATTERN.

Arguments:
  PATTERN - Pattern with variables
  TRIPLES - List of triples

Returns:
  List of matching triples

Examples:
  (filter-triples '($a rdf@type rdfs@Class) triples)"
  (remove-if-not
   (lambda (triple)
     (let ((match (pat-match pattern triple)))
       (and match (not (member '(nil . nil) match :test #'equal)))))
   triples))

(defun apply-node-styles (triples &optional styles)
  "Apply styling to nodes in TRIPLES based on STYLES.

Arguments:
  TRIPLES - List of triples
  STYLES - Alist of (namespace . plist) style definitions

Returns:
  DOT format string with node style definitions

Examples:
  (apply-node-styles triples '((\"foaf\" . (:color \"blue\"))))"
  (let* ((all-vertices (nodes triples))
         (all-vertices (set-difference all-vertices
                                       '(rdf@Property rdfs@Class skos@Concept)))
         (vertices (set-difference all-vertices (literals all-vertices))))
    (with-output-to-string (out)
      (dolist (node vertices)
        (let* ((ns (namespace node))
               (style (cdr (assoc ns styles :test #'string=)))
               (default (cdr (assoc "default" styles :test #'string=)))
               (color (or (getf style :color) (getf default :color)))
               (fillcolor (or (getf style :fillcolor) (getf default :fillcolor)))
               (fontcolor (or (getf style :fontcolor) (getf default :fontcolor))))
          (when (or style default)
            (format out "\"~A\" [color=\"~A\",fillcolor=\"~A\",fontcolor=\"~A\"];~%"
                    node color fillcolor fontcolor)))))))

(defun render-triples (triples &optional styles)
  "Render TRIPLES to complete Graphviz DOT format.

Arguments:
  TRIPLES - List of triples
  STYLES - Optional alist of style definitions

Returns:
  Complete DOT format string

Examples:
  (render-triples '((alice foaf@knows bob)))"
  (let* ((classes (filter-triples '($a a skos@Concept) triples))
         (properties (filter-triples '($a a rdf@Property) triples))
         (filtered-triples (set-difference
                            (set-difference triples properties :test #'equal)
                            classes :test #'equal))
         (class-style (or (cdr (assoc "class" styles :test #'string=))
                          '(("default" . (:color "#ffff00" :fillcolor "#00ff00"
                                          :fontcolor "white")))))
         (property-style (or (cdr (assoc "property" styles :test #'string=))
                             '(("default" . (:color "#00ffff" :fillcolor "#00ffff"
                                             :fontcolor "white"))))))
    (with-output-to-string (out)
      (write-string "digraph G {\noverlap=prism;\n" out)
      (write-string "node[shape=circle,style=filled,fontcolor=\"black\",fillcolor=\"white\"];\n" out)
      (write-string "layout=\"fdp\";\nbeautify=true;\nsep=\"2\";\n" out)
      (write-string (apply-node-styles filtered-triples styles) out)
      (write-string (apply-node-styles classes class-style) out)
      (write-string (apply-node-styles properties property-style) out)
      (dolist (triple filtered-triples)
        (write-string (render-triple triple) out))
      (write-string "}" out))))

(defun render-graph (triples filename &optional styles)
  "Render TRIPLES to SVG file via Graphviz.

Arguments:
  TRIPLES - List of triples
  FILENAME - Output SVG file path
  STYLES - Optional style definitions

Returns:
  FILENAME

Side Effects:
  Creates DOT file in /tmp and calls 'dot' command

Examples:
  (render-graph triples \"/tmp/graph.svg\")"
  (let ((dot-file "/tmp/graph.dot"))
    (with-open-file (out dot-file :direction :output :if-exists :supersede)
      (write-string (render-triples triples styles) out))
    (uiop:run-program (list "dot" dot-file "-Tsvg" "-o" filename)
                      :ignore-error-status t)
    filename))

(defun render-graph-json (triples filename &optional styles)
  "Render TRIPLES to JSON file via Graphviz.

Arguments:
  TRIPLES - List of triples
  FILENAME - Output JSON file path
  STYLES - Optional style definitions

Returns:
  FILENAME

Side Effects:
  Creates DOT file in /tmp and calls 'dot' command

Examples:
  (render-graph-json triples \"/tmp/graph.json\")"
  (let ((dot-file "/tmp/graph.dot"))
    (with-open-file (out dot-file :direction :output :if-exists :supersede)
      (write-string (render-triples triples styles) out))
    (uiop:run-program (list "dot" dot-file "-Tjson" "-o" filename)
                      :ignore-error-status t)
    filename))

;;;; Phase 13: Bidirectional Format Conversion (cl-rdf → el-rdf)

(defun convert-symbol-cl-to-elisp (symbol)
  "Convert cl-rdf symbol to el-rdf format (@ to :).

Arguments:
  SYMBOL - Symbol with @ separator

Returns:
  Symbol with : separator (may use pipe notation)

Examples:
  (convert-symbol-cl-to-elisp 'foaf@name) => |foaf:name|
  (convert-symbol-cl-to-elisp 'alice) => alice"
  (if (symbolp symbol)
      (let ((name (symbol-name symbol)))
        (if (find #\@ name)
            (intern (substitute #\: #\@ name) (symbol-package symbol))
            symbol))
      symbol))

(defun convert-triple-cl-to-elisp (triple)
  "Convert triple from cl-rdf format to el-rdf format.

Arguments:
  TRIPLE - Triple using cl-rdf symbol format

Returns:
  Triple using el-rdf symbol format

Examples:
  (convert-triple-cl-to-elisp '(alice foaf@name \"Alice\"))
  => (alice |foaf:name| \"Alice\")"
  (mapcar (lambda (elem)
            (if (symbolp elem)
                (convert-symbol-cl-to-elisp elem)
                elem))
          triple))

(defun save-for-elisp (graph filename)
  "Save GRAPH triples to FILENAME in el-rdf format (: separator).

Arguments:
  GRAPH - local-graph instance
  FILENAME - Path to save file

Side Effects:
  Writes file to filesystem in el-rdf format

Examples:
  (save-for-elisp graph \"/tmp/my-graph-elisp.rdf\")"
  (let* ((triples (raw-triples '(t t t) graph))
         (el-triples (mapcar #'convert-triple-cl-to-elisp triples))
         (serialized (triples-to-string el-triples)))
    (with-open-file (out filename :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write-string serialized out))))
