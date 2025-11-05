;;;; tests/cl-rdf-tests.lisp --- Test suite for cl-rdf

(in-package #:cl-rdf-tests)

;;; This file contains tests for cl-rdf, organized by test suite.
;;; Tests are written using the FiveAM testing framework.
;;;
;;; Test-Driven Development workflow:
;;; 1. Write test first (should fail)
;;; 2. Implement function in cl-rdf.lisp
;;; 3. Run test (should pass)
;;; 4. Refactor
;;;
;;; Run tests with: (fiveam:run! :cl-rdf)
;;; Or specific suite: (fiveam:run! :core)

;;; ============================================================================
;;; Smoke Test - Ensures test infrastructure is working
;;; ============================================================================

(in-suite :cl-rdf)

(test smoke-test
  "Smoke test to verify FiveAM is working"
  (is (= 4 (+ 2 2)))
  (is (eq t t))
  (is (string= "hello" "hello")))

;;; ============================================================================
;;; Phase 1: Core Data Structures and Utilities
;;; ============================================================================

(in-suite :core)

;; Tests for Phase 1: Core Data Structures and Utilities

(test make-graph-basic
  "Test basic graph creation"
  (let ((g (make-graph)))
    ;; Graph should be created
    (is (not (null g)))
    ;; Should have SPO hash table
    (is (hash-table-p (graph-spo g)))
    ;; Should have OSP hash table
    (is (hash-table-p (graph-osp g)))
    ;; Should have POS hash table
    (is (hash-table-p (graph-pos g)))
    ;; Hash tables should be empty initially
    (is (zerop (hash-table-count (graph-spo g))))
    (is (zerop (hash-table-count (graph-osp g))))
    (is (zerop (hash-table-count (graph-pos g))))
    ;; Name should be NIL when not provided
    (is (null (graph-name g)))))

(test make-graph-with-name
  "Test graph creation with optional name"
  (let ((g (make-graph :name "test-graph")))
    (is (not (null g)))
    (is (string= "test-graph" (graph-name g)))))

(test make-graph-hooks-structure
  "Test that graph has proper hooks structure"
  (let ((g (make-graph)))
    ;; Should have add-hooks accessor
    (is (listp (graph-add-hooks g)))
    (is (null (graph-add-hooks g)))  ; Initially empty
    ;; Should have delete-hooks accessor
    (is (listp (graph-delete-hooks g)))
    (is (null (graph-delete-hooks g)))  ; Initially empty
    ;; Should have query-hooks accessor
    (is (listp (graph-query-hooks g)))
    (is (null (graph-query-hooks g))))) ; Initially empty

(test make-graph-prefixes
  "Test that graph has prefixes storage"
  (let ((g (make-graph)))
    ;; Should have prefixes accessor
    (is (listp (graph-prefixes g)))
    (is (null (graph-prefixes g)))))  ; Initially empty

(test make-graph-hash-table-tests
  "Test that hash tables use correct test functions"
  (let ((g (make-graph)))
    ;; SPO: uses EQ test (for symbols as keys)
    (is (eq 'eq (hash-table-test (graph-spo g))))
    ;; OSP: uses EQUAL test (for strings/objects as keys)
    (is (eq 'equal (hash-table-test (graph-osp g))))
    ;; POS: uses EQ test (for symbols as keys)
    (is (eq 'eq (hash-table-test (graph-pos g))))))

(test variablep
  "Test variable predicate - identifies symbols starting with $"
  ;; Variables should return T
  (is (variablep '$subject))
  (is (variablep '$name))
  (is (variablep '$x))
  (is (variablep '$var123))
  ;; Non-variables should return NIL
  (is (not (variablep 'regular-symbol)))
  (is (not (variablep 'schema.Person)))
  (is (not (variablep "string")))
  (is (not (variablep 42)))
  (is (not (variablep nil)))
  ;; Symbol that's just $ should still be a variable
  (is (variablep '$)))

(test var-or-wildp
  "Test predicate for variables or wildcards"
  ;; Wildcard (t) should return T
  (is (var-or-wildp t))
  ;; Variables should return T
  (is (var-or-wildp '$subject))
  (is (var-or-wildp '$name))
  (is (var-or-wildp '$x))
  ;; Regular symbols should return NIL
  (is (not (var-or-wildp 'regular-symbol)))
  (is (not (var-or-wildp 'schema.Person)))
  ;; Other types should return NIL
  (is (not (var-or-wildp "string")))
  (is (not (var-or-wildp 42)))
  (is (not (var-or-wildp nil))))

(test bnode
  "Test blank node generation"
  ;; Generate blank nodes
  (let ((bn1 (bnode))
        (bn2 (bnode)))
    ;; Should be symbols
    (is (symbolp bn1))
    (is (symbolp bn2))
    ;; Should start with _@ (cl-rdf uses at-sign separator)
    (is (alexandria:starts-with-subseq "_@" (symbol-name bn1)))
    (is (alexandria:starts-with-subseq "_@" (symbol-name bn2)))
    ;; Should be unique (different blank nodes)
    (is (not (eq bn1 bn2)))
    ;; Generate multiple and verify they're all different
    (let ((nodes (loop repeat 10 collect (bnode))))
      ;; All should be symbols
      (is (every #'symbolp nodes))
      ;; All should start with _@
      (is (every (lambda (n)
                   (alexandria:starts-with-subseq "_@" (symbol-name n)))
                 nodes))
      ;; All should be unique
      (is (= (length nodes) (length (remove-duplicates nodes)))))))

(test namespace
  "Test namespace extraction from symbols"
  ;; Symbols with namespace@resource format (no vertical bars needed!)
  (is (string= "schema" (namespace 'schema@Person)))
  (is (string= "foaf" (namespace 'foaf@name)))
  (is (string= "rdf" (namespace 'rdf@type)))
  ;; Symbols without namespace (no at-sign)
  (is (null (namespace 'Person)))
  (is (null (namespace 'name)))
  (is (null (namespace 'a)))
  ;; Blank nodes should return nil (they start with _@)
  (is (null (namespace '_@G1234)))
  ;; Variables should return nil (they start with $)
  (is (null (namespace '$subject)))
  (is (null (namespace '$name))))

;;; ============================================================================
;;; Phase 2: Triple Storage
;;; ============================================================================

(in-suite :storage)

;; Tests for alist manipulation helpers used in triple indices

(test update-dual-new-key
  "Test update-dual with a new key"
  ;; Start with empty alist
  (let ((result (update-dual 'key1 'val1 nil)))
    (is (equal '((key1 . (val1))) result)))
  ;; Start with existing different keys
  (let ((result (update-dual 'key3 'val3 '((key1 . (val1)) (key2 . (val2))))))
    (is (equal 3 (length result)))
    (is (equal '(val3) (cdr (assoc 'key3 result))))))

(test update-dual-existing-key
  "Test update-dual adding to existing key"
  ;; Add new value to existing key
  (let ((result (update-dual 'key1 'val2 '((key1 . (val1))))))
    (is (equal 1 (length result)))
    (is (equal 2 (length (cdr (assoc 'key1 result)))))
    (is (member 'val1 (cdr (assoc 'key1 result))))
    (is (member 'val2 (cdr (assoc 'key1 result))))))

(test update-dual-duplicate-value
  "Test update-dual doesn't add duplicate values"
  ;; Try to add value that already exists
  (let* ((initial '((key1 . (val1 val2))))
         (result (update-dual 'key1 'val1 initial)))
    (is (equal 1 (length result)))
    (is (equal 2 (length (cdr (assoc 'key1 result)))))
    (is (member 'val1 (cdr (assoc 'key1 result))))
    (is (member 'val2 (cdr (assoc 'key1 result))))))

(test update-dual-complex-values
  "Test update-dual with complex values (cons pairs)"
  ;; Used for storing (predicate . object) pairs in triple indices
  (let* ((initial nil)
         (result1 (update-dual 'subject1 '(pred1 . obj1) initial))
         (result2 (update-dual 'subject1 '(pred2 . obj2) result1)))
    (is (equal 1 (length result2)))
    (is (equal 2 (length (cdr (assoc 'subject1 result2)))))
    (is (member '(pred1 . obj1) (cdr (assoc 'subject1 result2)) :test #'equal))
    (is (member '(pred2 . obj2) (cdr (assoc 'subject1 result2)) :test #'equal))))

(test remove-dual-single-value
  "Test remove-dual removing the only value for a key"
  ;; When removing the last value, the entire key should be removed
  (let* ((initial '((key1 . (val1))))
         (result (remove-dual 'key1 'val1 initial)))
    ;; Entry should be completely removed
    (is (null result))))

(test remove-dual-multiple-values
  "Test remove-dual with multiple values for a key"
  ;; Remove one value, leaving others
  (let* ((initial '((key1 . (val1 val2 val3))))
         (result (remove-dual 'key1 'val2 initial)))
    (is (equal 1 (length result)))
    (is (equal 2 (length (cdr (assoc 'key1 result)))))
    (is (member 'val1 (cdr (assoc 'key1 result))))
    (is (member 'val3 (cdr (assoc 'key1 result))))
    (is (not (member 'val2 (cdr (assoc 'key1 result)))))))

(test remove-dual-nonexistent-key
  "Test remove-dual with a key that doesn't exist"
  ;; Should return original alist unchanged
  (let* ((initial '((key1 . (val1 val2))))
         (result (remove-dual 'key2 'val1 initial)))
    (is (equal initial result))))

(test remove-dual-nonexistent-value
  "Test remove-dual with a value that doesn't exist"
  ;; Should return original alist unchanged
  (let* ((initial '((key1 . (val1 val2))))
         (result (remove-dual 'key1 'val3 initial)))
    (is (equal initial result))))

(test remove-dual-complex-values
  "Test remove-dual with complex values (cons pairs)"
  ;; Used for triple indices with (predicate . object) pairs
  (let* ((initial '((subject1 . ((pred1 . obj1) (pred2 . obj2)))))
         (result (remove-dual 'subject1 '(pred1 . obj1) initial)))
    (is (equal 1 (length result)))
    (is (equal 1 (length (cdr (assoc 'subject1 result)))))
    (is (member '(pred2 . obj2) (cdr (assoc 'subject1 result)) :test #'equal))
    (is (not (member '(pred1 . obj1) (cdr (assoc 'subject1 result)) :test #'equal)))))

(test remove-dual-multiple-keys
  "Test remove-dual with multiple keys in alist"
  ;; Should only affect the specified key
  (let* ((initial '((key1 . (val1 val2)) (key2 . (val3 val4))))
         (result (remove-dual 'key1 'val1 initial)))
    (is (equal 2 (length result)))
    ;; key1 should have val2 only
    (is (equal '(val2) (cdr (assoc 'key1 result))))
    ;; key2 should be unchanged
    (is (equal '(val3 val4) (cdr (assoc 'key2 result))))))

;; Tests for add-triple

(test add-triple-basic
  "Test adding a single triple to empty graph"
  (let ((g (make-graph)))
    ;; Add: (John schema@name "John Doe")
    (add-triple '(John schema@name "John Doe") g)
    ;; SPO index should have entry
    (let ((spo-entry (gethash 'John (graph-spo g))))
      (is (not (null spo-entry)))
      (is (member "John Doe" (cdr (assoc 'schema@name spo-entry)) :test #'equal)))
    ;; OSP index should have entry
    (let ((osp-entry (gethash "John Doe" (graph-osp g))))
      (is (not (null osp-entry)))
      (is (member 'schema@name (cdr (assoc 'John osp-entry)))))
    ;; POS index should have entry
    (let ((pos-entry (gethash 'schema@name (graph-pos g))))
      (is (not (null pos-entry)))
      (is (member 'John (cdr (assoc "John Doe" pos-entry)))))))

(test add-triple-multiple-same-subject
  "Test adding multiple triples with same subject"
  (let ((g (make-graph)))
    (add-triple '(John schema@name "John Doe") g)
    (add-triple '(John schema@age 30) g)
    ;; SPO should have both predicates for John
    (let ((spo-entry (gethash 'John (graph-spo g))))
      (is (= 2 (length spo-entry)))
      (is (member "John Doe" (cdr (assoc 'schema@name spo-entry)) :test #'equal))
      (is (member 30 (cdr (assoc 'schema@age spo-entry)))))))

(test add-triple-normalize-rdf-type
  "Test that rdf@type is normalized to 'a'"
  (let ((g (make-graph)))
    ;; Add triple with rdf@type
    (add-triple '(John rdf@type schema@Person) g)
    ;; Should be stored as 'a, not 'rdf@type
    (let ((spo-entry (gethash 'John (graph-spo g))))
      (is (not (null (assoc 'a spo-entry))))
      (is (null (assoc 'rdf@type spo-entry)))
      (is (member 'schema@Person (cdr (assoc 'a spo-entry)))))))

(test add-triple-duplicate
  "Test adding the same triple twice (should not duplicate)"
  (let ((g (make-graph)))
    (add-triple '(John schema@name "John Doe") g)
    (add-triple '(John schema@name "John Doe") g)
    ;; Should only have one entry
    (let ((spo-entry (gethash 'John (graph-spo g))))
      (is (= 1 (length (cdr (assoc 'schema@name spo-entry))))))))

(test add-triple-all-indices
  "Test that all three indices are maintained correctly"
  (let ((g (make-graph)))
    (add-triple '(John schema@knows Jane) g)
    ;; Verify SPO index
    (is (not (null (gethash 'John (graph-spo g)))))
    ;; Verify OSP index
    (is (not (null (gethash 'Jane (graph-osp g)))))
    ;; Verify POS index
    (is (not (null (gethash 'schema@knows (graph-pos g)))))))

;; Tests for delete-triple

(test delete-triple-basic
  "Test deleting a single triple"
  (let ((g (make-graph)))
    ;; Add and then delete
    (add-triple '(John schema@name "John Doe") g)
    (delete-triple '(John schema@name "John Doe") g)
    ;; All indices should be cleaned up (entry removed entirely)
    (is (null (gethash 'John (graph-spo g))))
    (is (null (gethash "John Doe" (graph-osp g))))
    (is (null (gethash 'schema@name (graph-pos g))))))

(test delete-triple-multiple-predicates
  "Test deleting one triple while leaving others"
  (let ((g (make-graph)))
    ;; Add two triples for same subject
    (add-triple '(John schema@name "John Doe") g)
    (add-triple '(John schema@age 30) g)
    ;; Delete one
    (delete-triple '(John schema@name "John Doe") g)
    ;; John should still exist in SPO with schema@age
    (let ((spo-entry (gethash 'John (graph-spo g))))
      (is (not (null spo-entry)))
      (is (null (assoc 'schema@name spo-entry)))
      (is (not (null (assoc 'schema@age spo-entry)))))
    ;; "John Doe" should be removed from OSP
    (is (null (gethash "John Doe" (graph-osp g))))
    ;; 30 should still be in OSP
    (is (not (null (gethash 30 (graph-osp g)))))))

(test delete-triple-normalize-rdf-type
  "Test that rdf@type is normalized to 'a during deletion"
  (let ((g (make-graph)))
    ;; Add with 'a
    (add-triple '(John a schema@Person) g)
    ;; Delete with rdf@type (should still work)
    (delete-triple '(John rdf@type schema@Person) g)
    ;; Should be completely removed
    (is (null (gethash 'John (graph-spo g))))))

(test delete-triple-nonexistent
  "Test deleting a triple that doesn't exist"
  (let ((g (make-graph)))
    ;; Add one triple
    (add-triple '(John schema@name "John Doe") g)
    ;; Try to delete a different triple
    (delete-triple '(Jane schema@name "Jane Doe") g)
    ;; Original triple should still exist
    (is (not (null (gethash 'John (graph-spo g)))))))

(test delete-triple-cleanup-empty-keys
  "Test that empty keys are cleaned up with remhash"
  (let ((g (make-graph)))
    ;; Add and delete
    (add-triple '(John schema@name "John Doe") g)
    (delete-triple '(John schema@name "John Doe") g)
    ;; Keys should be completely removed, not just empty
    (is (= 0 (hash-table-count (graph-spo g))))
    (is (= 0 (hash-table-count (graph-osp g))))
    (is (= 0 (hash-table-count (graph-pos g))))))

(test delete-triple-partial-removal
  "Test removing one object from a predicate with multiple objects"
  (let ((g (make-graph)))
    ;; Add two objects for same subject-predicate
    (add-triple '(John schema@knows Jane) g)
    (add-triple '(John schema@knows Bob) g)
    ;; Delete one
    (delete-triple '(John schema@knows Jane) g)
    ;; Bob should still be there
    (let ((spo-entry (gethash 'John (graph-spo g))))
      (is (= 1 (length (cdr (assoc 'schema@knows spo-entry)))))
      (is (member 'Bob (cdr (assoc 'schema@knows spo-entry)))))))

;; Tests for expand-duals

(test expand-duals-empty
  "Test expand-duals with empty alist"
  (let ((result (expand-duals nil 'subject)))
    (is (null result))))

(test expand-duals-spo-order
  "Test expand-duals with SPO order (default)"
  ;; Input: ((pred1 . (obj1 obj2)) (pred2 . (obj3)))
  ;; Element: subject
  ;; Output: ((subject pred1 obj1) (subject pred1 obj2) (subject pred2 obj3))
  (let ((duals '((schema@name . ("John" "Johnny"))
                 (schema@age . (30)))))
    (let ((result (expand-duals duals 'John)))
      (is (= 3 (length result)))
      (is (member '(John schema@name "John") result :test #'equal))
      (is (member '(John schema@name "Johnny") result :test #'equal))
      (is (member '(John schema@age 30) result :test #'equal)))))

(test expand-duals-osp-order
  "Test expand-duals with OSP order"
  ;; Input: ((subj1 . (pred1 pred2)) (subj2 . (pred3)))
  ;; Element: object
  ;; Reorder: 'osp
  ;; Output: ((subj1 pred1 object) (subj1 pred2 object) (subj2 pred3 object))
  (let ((duals '((John . (schema@name schema@age))
                 (Jane . (schema@name)))))
    (let ((result (expand-duals duals "John Doe" :osp)))
      (is (= 3 (length result)))
      (is (member '(John schema@name "John Doe") result :test #'equal))
      (is (member '(John schema@age "John Doe") result :test #'equal))
      (is (member '(Jane schema@name "John Doe") result :test #'equal)))))

(test expand-duals-pos-order
  "Test expand-duals with POS order"
  ;; Input: ((obj1 . (subj1 subj2)) (obj2 . (subj3)))
  ;; Element: predicate
  ;; Reorder: 'pos
  ;; Output: ((subj1 predicate obj1) (subj2 predicate obj1) (subj3 predicate obj2))
  (let ((duals '((schema@Person . (John Jane))
                 (schema@Company . (Acme)))))
    (let ((result (expand-duals duals 'a :pos)))
      (is (= 3 (length result)))
      (is (member '(John a schema@Person) result :test #'equal))
      (is (member '(Jane a schema@Person) result :test #'equal))
      (is (member '(Acme a schema@Company) result :test #'equal)))))

(test expand-duals-single-value
  "Test expand-duals with single value lists"
  (let ((duals '((pred . (obj)))))
    (let ((result (expand-duals duals 'subj)))
      (is (= 1 (length result)))
      (is (equal '(subj pred obj) (first result))))))

(test expand-duals-complex-values
  "Test expand-duals with complex values (cons pairs)"
  ;; This is used internally with predicate-object pairs
  (let ((duals '((pred1 . (obj1 obj2)))))
    (let ((result (expand-duals duals 'subj)))
      (is (= 2 (length result)))
      (is (member '(subj pred1 obj1) result :test #'equal))
      (is (member '(subj pred1 obj2) result :test #'equal)))))

;; Tests for add-triples

(test add-triples-basic
  "Test adding multiple triples at once"
  (let ((g (make-graph)))
    (add-triples '((John schema@name "John Doe")
                   (John schema@age 30)
                   (Jane schema@name "Jane Doe"))
                 g)
    ;; All triples should be added
    (is (not (null (gethash 'John (graph-spo g)))))
    (is (not (null (gethash 'Jane (graph-spo g)))))
    (let ((john-entry (gethash 'John (graph-spo g))))
      (is (member "John Doe" (cdr (assoc 'schema@name john-entry)) :test #'equal))
      (is (member 30 (cdr (assoc 'schema@age john-entry)))))))

(test add-triples-empty-list
  "Test add-triples with empty list"
  (let ((g (make-graph)))
    ;; Should not error
    (add-triples nil g)
    ;; Graph should remain empty
    (is (= 0 (hash-table-count (graph-spo g))))))

(test add-triples-calls-hooks
  "Test that add-triples calls add-hooks"
  (let ((g (make-graph))
        (hook-called nil)
        (hook-operation nil)
        (hook-data nil))
    ;; Add a hook
    (push (lambda (graph operation data)
            (setf hook-called t)
            (setf hook-operation operation)
            (setf hook-data data))
          (graph-add-hooks g))
    ;; Add triples
    (add-triples '((John schema@name "John")) g)
    ;; Hook should have been called
    (is (eq t hook-called))
    (is (eq 'add-triples hook-operation))
    (is (equal '((John schema@name "John")) hook-data))))

(test add-triples-multiple-hooks
  "Test that all add-hooks are called"
  (let ((g (make-graph))
        (hook1-called nil)
        (hook2-called nil))
    ;; Add two hooks
    (push (lambda (graph operation data)
            (declare (ignore graph operation data))
            (setf hook1-called t))
          (graph-add-hooks g))
    (push (lambda (graph operation data)
            (declare (ignore graph operation data))
            (setf hook2-called t))
          (graph-add-hooks g))
    ;; Add triples
    (add-triples '((John schema@name "John")) g)
    ;; Both hooks should be called
    (is (eq t hook1-called))
    (is (eq t hook2-called))))

(test add-triples-no-hooks
  "Test add-triples works with no hooks registered"
  (let ((g (make-graph)))
    ;; Should not error when no hooks present
    (add-triples '((John schema@name "John")) g)
    (is (not (null (gethash 'John (graph-spo g)))))))

;; Tests for delete-triples

(test delete-triples-basic
  "Test deleting multiple triples at once"
  (let ((g (make-graph)))
    ;; Add some triples first
    (add-triples '((John schema@name "John Doe")
                   (John schema@age 30)
                   (Jane schema@name "Jane Doe"))
                 g)
    ;; Delete two of them
    (delete-triples '((John schema@name "John Doe")
                      (Jane schema@name "Jane Doe"))
                    g)
    ;; John's age should remain
    (let ((john-entry (gethash 'John (graph-spo g))))
      (is (not (null john-entry)))
      (is (member 30 (cdr (assoc 'schema@age john-entry)))))
    ;; Jane should be completely removed
    (is (null (gethash 'Jane (graph-spo g))))))

(test delete-triples-empty-list
  "Test delete-triples with empty list"
  (let ((g (make-graph)))
    ;; Add a triple
    (add-triple '(John schema@name "John") g)
    ;; Delete empty list should not error
    (delete-triples nil g)
    ;; Triple should still be there
    (is (not (null (gethash 'John (graph-spo g)))))))

(test delete-triples-calls-hooks
  "Test that delete-triples calls delete-hooks"
  (let ((g (make-graph))
        (hook-called nil)
        (hook-operation nil)
        (hook-data nil))
    ;; Add a triple
    (add-triple '(John schema@name "John") g)
    ;; Add a delete hook
    (push (lambda (graph operation data)
            (setf hook-called t)
            (setf hook-operation operation)
            (setf hook-data data))
          (graph-delete-hooks g))
    ;; Delete triples
    (delete-triples '((John schema@name "John")) g)
    ;; Hook should have been called
    (is (eq t hook-called))
    (is (eq 'delete-triples hook-operation))
    (is (equal '((John schema@name "John")) hook-data))))

(test delete-triples-multiple-hooks
  "Test that all delete-hooks are called"
  (let ((g (make-graph))
        (hook1-called nil)
        (hook2-called nil))
    ;; Add a triple
    (add-triple '(John schema@name "John") g)
    ;; Add two hooks
    (push (lambda (graph operation data)
            (declare (ignore graph operation data))
            (setf hook1-called t))
          (graph-delete-hooks g))
    (push (lambda (graph operation data)
            (declare (ignore graph operation data))
            (setf hook2-called t))
          (graph-delete-hooks g))
    ;; Delete triples
    (delete-triples '((John schema@name "John")) g)
    ;; Both hooks should be called
    (is (eq t hook1-called))
    (is (eq t hook2-called))))

(test delete-triples-no-hooks
  "Test delete-triples works with no hooks registered"
  (let ((g (make-graph)))
    ;; Add and delete without hooks
    (add-triple '(John schema@name "John") g)
    ;; Should not error when no hooks present
    (delete-triples '((John schema@name "John")) g)
    (is (null (gethash 'John (graph-spo g))))))

(test delete-triples-nonexistent
  "Test deleting triples that don't exist"
  (let ((g (make-graph)))
    ;; Add one triple
    (add-triple '(John schema@name "John") g)
    ;; Try to delete different triples
    (delete-triples '((Jane schema@name "Jane")
                      (Bob schema@age 25))
                    g)
    ;; Original triple should still exist
    (is (not (null (gethash 'John (graph-spo g)))))))

;;; ============================================================================
;;; Phase 3: Hook System
;;; ============================================================================

(in-suite :hooks)

;; Tests for add-hook-to-graph

(test add-hook-to-graph-basic
  "Test adding a hook to a graph"
  (let ((g (make-graph))
        (hook-fn (lambda (graph op data)
                   (declare (ignore graph op data))
                   nil)))
    ;; Add hook to add-hooks
    (add-hook-to-graph g :add hook-fn)
    (is (member hook-fn (graph-add-hooks g)))

    ;; Add hook to delete-hooks
    (add-hook-to-graph g :delete hook-fn)
    (is (member hook-fn (graph-delete-hooks g)))

    ;; Add hook to query-hooks
    (add-hook-to-graph g :query hook-fn)
    (is (member hook-fn (graph-query-hooks g)))))

(test add-hook-to-graph-no-duplicates
  "Test that adding same hook twice doesn't create duplicates"
  (let ((g (make-graph))
        (hook-fn (lambda (graph op data)
                   (declare (ignore graph op data))
                   nil)))
    ;; Add hook twice
    (add-hook-to-graph g :add hook-fn)
    (add-hook-to-graph g :add hook-fn)
    ;; Should only appear once
    (is (= 1 (count hook-fn (graph-add-hooks g))))))

(test add-hook-to-graph-multiple-hooks
  "Test adding multiple different hooks"
  (let ((g (make-graph))
        (hook1 (lambda (graph op data)
                 (declare (ignore graph op data))
                 1))
        (hook2 (lambda (graph op data)
                 (declare (ignore graph op data))
                 2)))
    ;; Add two different hooks
    (add-hook-to-graph g :add hook1)
    (add-hook-to-graph g :add hook2)
    ;; Both should be present
    (is (member hook1 (graph-add-hooks g)))
    (is (member hook2 (graph-add-hooks g)))
    (is (= 2 (length (graph-add-hooks g))))))

;; Tests for remove-hook-from-graph

(test remove-hook-from-graph-basic
  "Test removing a hook from a graph"
  (let ((g (make-graph))
        (hook-fn (lambda (graph op data)
                   (declare (ignore graph op data))
                   nil)))
    ;; Add hook first
    (add-hook-to-graph g :add hook-fn)
    (is (member hook-fn (graph-add-hooks g)))
    ;; Remove it
    (remove-hook-from-graph g :add hook-fn)
    (is (not (member hook-fn (graph-add-hooks g))))))

(test remove-hook-from-graph-multiple
  "Test removing one hook while keeping others"
  (let ((g (make-graph))
        (hook1 (lambda (graph op data)
                 (declare (ignore graph op data))
                 1))
        (hook2 (lambda (graph op data)
                 (declare (ignore graph op data))
                 2)))
    ;; Add two hooks
    (add-hook-to-graph g :add hook1)
    (add-hook-to-graph g :add hook2)
    ;; Remove one
    (remove-hook-from-graph g :add hook1)
    ;; hook1 should be gone, hook2 should remain
    (is (not (member hook1 (graph-add-hooks g))))
    (is (member hook2 (graph-add-hooks g)))))

(test remove-hook-from-graph-nonexistent
  "Test removing a hook that doesn't exist (should not error)"
  (let ((g (make-graph))
        (hook-fn (lambda (graph op data)
                   (declare (ignore graph op data))
                   nil)))
    ;; Remove hook that was never added (should not error)
    (remove-hook-from-graph g :add hook-fn)
    ;; Should still be empty
    (is (null (graph-add-hooks g)))))

;; Tests for get-graph-hooks

(test get-graph-hooks-basic
  "Test getting hooks from a graph"
  (let ((g (make-graph))
        (hook1 (lambda (graph op data)
                 (declare (ignore graph op data))
                 1))
        (hook2 (lambda (graph op data)
                 (declare (ignore graph op data))
                 2)))
    ;; Add hooks to different types
    (add-hook-to-graph g :add hook1)
    (add-hook-to-graph g :delete hook2)
    ;; Get hooks by type
    (is (member hook1 (get-graph-hooks g :add)))
    (is (member hook2 (get-graph-hooks g :delete)))
    (is (null (get-graph-hooks g :query)))))

(test get-graph-hooks-empty
  "Test getting hooks from empty graph"
  (let ((g (make-graph)))
    (is (null (get-graph-hooks g :add)))
    (is (null (get-graph-hooks g :delete)))
    (is (null (get-graph-hooks g :query)))))

;;; ============================================================================
;;; Phase 4: Triple Retrieval
;;; ============================================================================

(in-suite :storage)

;; Diagnostic test to check basic triple retrieval

(test triples-basic-diagnostic
  "Minimal test to diagnose triples function"
  (let ((g (make-graph)))
    ;; Add one simple triple
    (add-triple '(alice foaf-name "Alice") g)

    ;; Try to retrieve it
    (let ((results (triples '(alice t t) g)))
      (format t "~%DEBUG: results = ~S~%" results)
      (is (not (null results)) "Should have at least one result")
      (is (= 1 (length results)) "Should have exactly one result")
      (is (equal '(alice foaf-name "Alice") (first results))))))

;; Tests for triples function

(test triples-query-by-subject
  "Test retrieving triples by concrete subject (uses SPO index)"
  (let ((g (make-graph)))
    ;; Add test data
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(alice@person foaf@age 30) g)
    (add-triple '(bob@person foaf@name "Bob") g)

    ;; Query by subject
    (let ((results (triples '(alice@person t t) g)))
      (is (= 2 (length results)))
      (is (member '(alice@person foaf@name "Alice") results :test #'equal))
      (is (member '(alice@person foaf@age 30) results :test #'equal)))

    ;; Query by subject with specific predicate (note: triples doesn't filter by predicate,
    ;; it just selects the index - pattern matching happens in a different layer)
    (let ((results (triples '(alice@person foaf@name t) g)))
      ;; Should still return all triples for alice@person (both name and age)
      (is (= 2 (length results)))
      (is (member '(alice@person foaf@name "Alice") results :test #'equal))
      (is (member '(alice@person foaf@age 30) results :test #'equal))))

(test triples-query-by-predicate
  "Test retrieving triples by concrete predicate (uses POS index)"
  (let ((g (make-graph)))
    ;; Add test data
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(bob@person foaf@name "Bob") g)
    (add-triple '(alice@person foaf@age 30) g)

    ;; Query by predicate
    (let ((results (triples '(t foaf@name t) g)))
      (is (= 2 (length results)))
      (is (member '(alice@person foaf@name "Alice") results :test #'equal))
      (is (member '(bob@person foaf@name "Bob") results :test #'equal)))))

(test triples-query-by-object
  "Test retrieving triples by concrete object (uses OSP index)"
  (let ((g (make-graph)))
    ;; Add test data
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(bob@person foaf@name "Bob") g)
    (add-triple '(alice@person foaf@age 30) g)
    (add-triple '(charlie@person foaf@age 30) g)

    ;; Query by object (number)
    (let ((results (triples '(t t 30) g)))
      (is (= 2 (length results)))
      (is (member '(alice@person foaf@age 30) results :test #'equal))
      (is (member '(charlie@person foaf@age 30) results :test #'equal)))

    ;; Query by object (string)
    (let ((results (triples '(t t "Bob") g)))
      (is (= 1 (length results)))
      (is (equal '(bob@person foaf@name "Bob") (first results))))))

(test triples-universal-pattern
  "Test universal pattern returns all triples"
  (let ((g (make-graph)))
    ;; Add test data
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(bob@person foaf@name "Bob") g)
    (add-triple '(alice@person foaf@age 30) g)

    ;; Query all triples
    (let ((results (triples '(t t t) g)))
      (is (= 3 (length results)))
      (is (member '(alice@person foaf@name "Alice") results :test #'equal))
      (is (member '(bob@person foaf@name "Bob") results :test #'equal))
      (is (member '(alice@person foaf@age 30) results :test #'equal)))))

(test triples-rdf-type-equivalence
  "Test that a and rdf@type are treated as equivalent"
  (let ((g (make-graph)))
    ;; add-triple normalizes rdf@type to 'a' in storage
    (add-triple '(alice@person rdf@type foaf@Person) g)
    (add-triple '(bob@person a schema@Person) g)

    ;; Query using rdf@type should find both (stored as 'a')
    (let ((results (triples '(t rdf@type t) g)))
      (is (= 2 (length results)))
      ;; Results should show rdf@type (transformed from 'a')
      (is (member '(alice@person rdf@type foaf@Person) results :test #'equal))
      (is (member '(bob@person rdf@type schema@Person) results :test #'equal)))

    ;; Query using 'a' directly should also work
    (let ((results (triples '(t a t) g)))
      (is (= 2 (length results))))))

(test triples-empty-results
  "Test that queries with no matches return empty list"
  (let ((g (make-graph)))
    (add-triple '(alice@person foaf@name "Alice") g)

    ;; Query for non-existent subject
    (is (null (triples '(bob@person t t) g)))

    ;; Query for non-existent predicate
    (is (null (triples '(t foaf@age t) g)))

    ;; Query for non-existent object
    (is (null (triples '(t t "Bob") g))))))

(test triples-with-variables
  "Test that variables ($var) work as wildcards"
  (let ((g (make-graph)))
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(bob@person foaf@name "Bob") g)

    ;; Variables should work like wildcards
    (let ((results (triples '($subject foaf@name $name) g)))
      (is (= 2 (length results)))
      (is (member '(alice@person foaf@name "Alice") results :test #'equal))
      (is (member '(bob@person foaf@name "Bob") results :test #'equal)))))

(test triples-empty-graph
  "Test querying an empty graph returns no results"
  (let ((g (make-graph)))
    (is (null (triples '(t t t) g)))
    (is (null (triples '(alice@person foaf@name t) g)))))

;; Tests for raw-triples function

(test raw-triples-basic
  "Test that raw-triples works identically to triples (for now, no content refs)"
  (let ((g (make-graph)))
    ;; Add test data
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(bob@person foaf@age 30) g)

    ;; raw-triples should return same results as triples (no content refs yet)
    (let ((triples-result (triples '(t t t) g))
          (raw-result (raw-triples '(t t t) g)))
      (is (= (length triples-result) (length raw-result)))
      (is (null (set-exclusive-or triples-result raw-result :test #'equal))))))

(test raw-triples-query-patterns
  "Test raw-triples with different query patterns"
  (let ((g (make-graph)))
    (add-triple '(alice@person foaf@name "Alice") g)
    (add-triple '(bob@person foaf@name "Bob") g)
    (add-triple '(alice@person foaf@age 30) g)

    ;; Query by subject
    (let ((results (raw-triples '(alice@person t t) g)))
      (is (= 2 (length results))))

    ;; Query by predicate
    (let ((results (raw-triples '(t foaf@name t) g)))
      (is (= 2 (length results))))

    ;; Query by object
    (let ((results (raw-triples '(t t "Alice") g)))
      (is (= 1 (length results))))))

;;; ============================================================================
;;; Phase 5-12: Additional test suites
;;; ============================================================================

;; Tests for remaining phases will be added as implementation progresses
;; See CL-PORT-PLAN.md for complete phase breakdown
