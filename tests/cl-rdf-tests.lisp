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
;;; Phase 5: Pattern Matching
;;; ============================================================================

(in-suite :storage)

;; Tests for augmented-eq

(test augmented-eq-symbols
  "Test augmented-eq with symbols (uses EQ)"
  (is (augmented-eq 'alice 'alice))
  (is (not (augmented-eq 'alice 'bob)))
  (is (augmented-eq 'foaf@name 'foaf@name)))

(test augmented-eq-strings
  "Test augmented-eq with strings (uses STRING=)"
  (is (augmented-eq "Alice" "Alice"))
  (is (not (augmented-eq "Alice" "Bob")))
  (is (augmented-eq "" "")))

(test augmented-eq-numbers
  "Test augmented-eq with numbers (uses EQL)"
  (is (augmented-eq 42 42))
  (is (augmented-eq 3.14 3.14))
  (is (not (augmented-eq 42 43))))

(test augmented-eq-mixed-types
  "Test augmented-eq with different types (should not match)"
  (is (not (augmented-eq 'alice "alice")))
  (is (not (augmented-eq 42 "42")))
  (is (not (augmented-eq 'a 1))))

;; Tests for pat-match

(test pat-match-variables
  "Test pat-match binds variables"
  (let ((bindings (pat-match '$subject 'alice)))
    (is (= 1 (length bindings)))
    (is (equal '($subject . alice) (first bindings)))))

(test pat-match-atoms-match
  "Test pat-match with matching atoms"
  (let ((bindings (pat-match 'alice 'alice)))
    (is (member '(t . alice) bindings :test #'equal))))

(test pat-match-atoms-no-match
  "Test pat-match with non-matching atoms"
  (let ((bindings (pat-match 'alice 'bob)))
    (is (member '(nil . nil) bindings :test #'equal))))

(test pat-match-simple-list
  "Test pat-match with simple lists"
  (let ((bindings (pat-match '($s $p $o) '(alice foaf@name "Alice"))))
    (is (member '($s . alice) bindings :test #'equal))
    (is (member '($p . foaf@name) bindings :test #'equal))
    (is (member '($o . "Alice") bindings :test #'equal))))

(test pat-match-mixed-pattern
  "Test pat-match with concrete values and variables"
  (let ((bindings (pat-match '($subject foaf@name $name)
                              '(alice foaf@name "Alice"))))
    (is (member '($subject . alice) bindings :test #'equal))
    (is (member '($name . "Alice") bindings :test #'equal))
    ;; foaf@name matches itself (wildcard marker)
    (is (member '(t . foaf@name) bindings :test #'equal))))

(test pat-match-no-match-predicate
  "Test pat-match when predicate doesn't match"
  (let ((bindings (pat-match '($subject foaf@name $name)
                              '(alice foaf@age 30))))
    (is (member '(nil . nil) bindings :test #'equal))))

;; Tests for traverse-graph

(test traverse-graph-basic
  "Test traverse-graph returns bindings for matching triples"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")
                    (alice foaf@age 30)))
         (bindings (traverse-graph '($subject foaf@name $name) triples)))
    ;; Should match 2 triples (Alice and Bob's names)
    (is (= 2 (length bindings)))
    ;; Each binding set should have $subject and $name
    (is (every (lambda (b)
                 (and (assoc '$subject b)
                      (assoc '$name b)))
               bindings))))

(test traverse-graph-no-matches
  "Test traverse-graph with non-matching pattern"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")))
         (bindings (traverse-graph '($subject foaf@age $age) triples)))
    (is (null bindings))))

(test traverse-graph-all-variables
  "Test traverse-graph with all variables pattern"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")))
         (bindings (traverse-graph '($s $p $o) triples)))
    (is (= 2 (length bindings)))
    (is (every (lambda (b)
                 (and (assoc '$s b)
                      (assoc '$p b)
                      (assoc '$o b)))
               bindings))))

;; Tests for filter-triples

(test filter-triples-basic
  "Test filter-triples returns matching triples"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")
                    (alice foaf@age 30)))
         (filtered (filter-triples '($subject foaf@name $name) triples)))
    ;; Should return 2 triples with foaf@name predicate
    (is (= 2 (length filtered)))
    (is (member '(alice foaf@name "Alice") filtered :test #'equal))
    (is (member '(bob foaf@name "Bob") filtered :test #'equal))))

(test filter-triples-no-matches
  "Test filter-triples with non-matching pattern"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")))
         (filtered (filter-triples '($subject foaf@age $age) triples)))
    (is (null filtered))))

(test filter-triples-specific-subject
  "Test filter-triples with concrete subject"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")
                    (alice foaf@age 30)))
         (filtered (filter-triples '(alice $p $o) triples)))
    (is (= 2 (length filtered)))
    (is (member '(alice foaf@name "Alice") filtered :test #'equal))
    (is (member '(alice foaf@age 30) filtered :test #'equal))))

;;; ============================================================================
;;; Phase 6: Query Execution Engine
;;; ============================================================================

(in-suite :query)

;; Tests for clean-bindings

(test clean-bindings-removes-t-markers
  "Test clean-bindings removes success markers (t . value)"
  (let ((bindings '((($s . alice) (t . alice) ($p . foaf@name))
                    (($s . bob) (t . bob) ($p . foaf@age)))))
    (let ((cleaned (clean-bindings bindings)))
      (is (= 2 (length cleaned)))
      (is (not (assoc t (first cleaned))))
      (is (not (assoc t (second cleaned))))
      (is (not (null (assoc '$s (first cleaned)))))
      (is (not (null (assoc '$p (first cleaned))))))))

(test clean-bindings-empty-list
  "Test clean-bindings with empty list"
  (is (null (clean-bindings '()))))

(test clean-bindings-no-t-markers
  "Test clean-bindings when no t markers present"
  (let ((bindings '((($s . alice) ($p . foaf@name)))))
    (let ((cleaned (clean-bindings bindings)))
      (is (equal bindings cleaned)))))

;; Tests for compatible-bindings-p

(test compatible-bindings-p-same-values
  "Test compatible-bindings-p returns T when variables bind to same values"
  (let ((new '(($s . alice) ($p . foaf@name)))
        (old '((($s . alice) ($age . 30)))))
    (is (compatible-bindings-p new old))))

(test compatible-bindings-p-different-variables
  "Test compatible-bindings-p when no overlapping variables"
  (let ((new '(($p . foaf@name) ($o . "Alice")))
        (old '((($s . alice)))))
    (is (compatible-bindings-p new old))))

(test compatible-bindings-p-conflicting-values
  "Test compatible-bindings-p returns NIL on conflicting bindings"
  (let ((new '(($s . alice) ($p . foaf@name)))
        (old '((($s . bob) ($age . 30)))))
    (is (not (compatible-bindings-p new old)))))

(test compatible-bindings-p-empty-new
  "Test compatible-bindings-p with empty new bindings"
  (let ((new '())
        (old '((($s . alice)))))
    (is (compatible-bindings-p new old))))

(test compatible-bindings-p-multiple-same-var
  "Test compatible-bindings-p with multiple checks on same variable"
  (let ((new '(($s . alice) ($s . alice) ($p . foaf@name)))
        (old '((($s . alice) ($age . 30)))))
    (is (compatible-bindings-p new old))))

;; Tests for update-bindings

(test update-bindings-merge-compatible
  "Test update-bindings merges compatible bindings"
  (let ((new '((($p . foaf@name) ($o . "Alice"))))
        (old '((($s . alice) ($age . 30)))))
    (let ((updated (update-bindings new old)))
      (is (= 1 (length updated)))
      (is (not (null (assoc '$s (first updated)))))
      (is (not (null (assoc '$p (first updated)))))
      (is (not (null (assoc '$o (first updated)))))
      (is (not (null (assoc '$age (first updated))))))))

(test update-bindings-reject-incompatible
  "Test update-bindings returns NIL on incompatible bindings"
  (let ((new '((($s . alice)) (($s . bob))))
        (old '((($s . charlie)))))
    (let ((updated (update-bindings new old)))
      (is (null updated)))))

(test update-bindings-nil-new-bindings
  "Test update-bindings with nil new bindings returns cleaned old"
  (let ((old '((($s . alice) (t . alice) ($p . foaf@name)))))
    (let ((updated (update-bindings nil old)))
      (is (= 1 (length updated)))
      (is (not (assoc t (first updated)))))))

(test update-bindings-removes-duplicates
  "Test update-bindings removes duplicate bindings"
  (let ((new '((($s . alice) ($p . foaf@name))))
        (old '((($s . alice) ($age . 30)))))
    (let ((updated (update-bindings new old)))
      (is (= 1 (length updated)))
      ;; Count occurrences of $s binding
      (is (= 1 (count '$s (first updated) :key #'car))))))

(test update-bindings-multiple-new-branches
  "Test update-bindings with multiple new binding branches"
  (let ((new '((($p . foaf@name)) (($p . foaf@age))))
        (old '((($s . alice)))))
    (let ((updated (update-bindings new old)))
      (is (= 2 (length updated)))
      (is (every (lambda (b) (assoc '$s b)) updated))
      (is (every (lambda (b) (assoc '$p b)) updated)))))

;; Tests for normalize-pattern

(test normalize-pattern-rdf-type-to-a
  "Test normalize-pattern converts rdf@type to a when no variables"
  (let ((pattern '(alice rdf@type schema@Person)))
    (is (equal '(alice a schema@Person) (normalize-pattern pattern)))))

(test normalize-pattern-preserves-with-variables
  "Test normalize-pattern doesn't convert when variables present"
  (let ((pattern '($s rdf@type schema@Person)))
    (is (equal pattern (normalize-pattern pattern))))
  (let ((pattern '(alice rdf@type $type)))
    (is (equal pattern (normalize-pattern pattern)))))

(test normalize-pattern-non-rdf-type
  "Test normalize-pattern doesn't change non-rdf@type patterns"
  (let ((pattern '(alice foaf@name "Alice")))
    (is (equal pattern (normalize-pattern pattern)))))

(test normalize-pattern-short-pattern
  "Test normalize-pattern with pattern shorter than 3 elements"
  (let ((pattern '(alice foaf@name)))
    (is (equal pattern (normalize-pattern pattern)))))

;; Tests for optional-clause-p and unwrap-optional

(test optional-clause-p-recognizes-optional
  "Test optional-clause-p recognizes (optional ...) patterns"
  (is (optional-clause-p '(optional ($s foaf@name $name))))
  (is (not (optional-clause-p '($s foaf@name $name)))))

(test unwrap-optional-extracts-pattern
  "Test unwrap-optional extracts pattern from (optional ...)"
  (is (equal '($s foaf@name $name)
             (unwrap-optional '(optional ($s foaf@name $name))))))

(test unwrap-optional-non-optional-unchanged
  "Test unwrap-optional returns pattern unchanged if not optional"
  (let ((pattern '($s foaf@name $name)))
    (is (equal pattern (unwrap-optional pattern)))))

;; Tests for graph-query - comprehensive test suite

(test graph-query-single-clause
  "Test graph-query with single clause"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    (let ((result (graph-query '(($s foaf@name $name)) graph)))
      (is (listp result))
      (is (= 2 (length result)))
      ;; Check structure: (((bindings)))
      (is (every #'consp result))
      (is (not (null (assoc '$s (caar result)))))
      (is (not (null (assoc '$name (caar result))))))))

(test graph-query-multi-clause
  "Test graph-query with multiple clauses"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30)
                   (bob foaf@name "Bob"))
                 graph)
    (let ((result (graph-query '(($s foaf@name $name)
                                 ($s foaf@age $age))
                               graph)))
      (is (= 1 (length result)))
      (is (not (null (assoc '$s (caar result)))))
      (is (not (null (assoc '$name (caar result)))))
      (is (not (null (assoc '$age (caar result)))))
      (is (equal 'alice (cdr (assoc '$s (caar result))))))))

(test graph-query-no-match-signals-error
  "Test graph-query signals pattern-match-failure when pattern doesn't match"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    ;; Pattern doesn't match - should signal error but default handler returns :no-match
    (let ((result (graph-query '(($s foaf@nonexistent $x)) graph)))
      (is (eq :no-match result)))))

(test graph-query-optional-clause-success
  "Test graph-query with OPTIONAL clause that matches"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30)
                   (bob foaf@name "Bob"))
                 graph)
    (let ((result (graph-query '(($s foaf@name $name)
                                 (optional ($s foaf@age $age)))
                               graph)))
      (is (= 2 (length result)))
      ;; Alice should have both name and age
      (let ((alice-result (find 'alice result
                                :key (lambda (r) (cdr (assoc '$s (car r)))))))
        (is (not (null alice-result)))
        (is (not (null (assoc '$age (car alice-result))))))
      ;; Bob should have only name (age was optional)
      (let ((bob-result (find 'bob result
                              :key (lambda (r) (cdr (assoc '$s (car r)))))))
        (is (not (null bob-result)))
        (is (not (null (assoc '$name (car bob-result)))))))))

(test graph-query-optional-clause-failure
  "Test graph-query with OPTIONAL clause that doesn't match"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    ;; Optional clause fails but query should still succeed
    (let ((result (graph-query '(($s foaf@name $name)
                                 (optional ($s foaf@age $age)))
                               graph)))
      (is (= 2 (length result)))
      ;; Neither should have age binding
      (is (every (lambda (r) (not (assoc '$age (car r)))) result)))))

(test graph-query-empty-bindings
  "Test graph-query with pattern that has no variables"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    ;; Pattern matches but no variables to bind
    (let ((result (graph-query '((alice foaf@name "Alice")) graph)))
      ;; Should return empty list (not :no-match)
      (is (listp result)))))

(test graph-query-multiple-branches
  "Test graph-query that creates multiple binding branches"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@knows bob)
                   (alice foaf@knows charlie)
                   (bob foaf@name "Bob")
                   (charlie foaf@name "Charlie"))
                 graph)
    (let ((result (graph-query '((alice foaf@knows $friend)
                                 ($friend foaf@name $fname))
                               graph)))
      (is (= 2 (length result)))
      (is (member "Bob" result :key (lambda (r) (cdr (assoc '$fname (car r)))) :test #'equal))
      (is (member "Charlie" result :key (lambda (r) (cdr (assoc '$fname (car r)))) :test #'equal)))))

(test graph-query-with-rdf-type
  "Test graph-query handles rdf@type equivalence"
  (let ((graph (make-graph)))
    (add-triple '(alice a schema@Person) graph)
    ;; Query with rdf@type should match triple with 'a
    (let ((result (graph-query '((alice rdf@type $type)) graph)))
      (is (listp result))
      (is (plusp (length result))))))

(test graph-query-calls-query-hooks
  "Test graph-query calls registered query hooks"
  (let ((graph (make-graph))
        (hook-called nil))
    (add-triple '(alice foaf@name "Alice") graph)
    (add-hook-to-graph graph 'query-hooks
                       (lambda (g op data)
                         (setf hook-called t)))
    (graph-query '(($s foaf@name $name)) graph)
    (is hook-called)))

(test graph-query-handler-can-override-error
  "Test caller can override pattern-match-failure with custom handler"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    ;; Override default handler to use empty bindings restart
    (let ((result (handler-bind ((pattern-match-failure
                                   (lambda (c)
                                     (declare (ignore c))
                                     (invoke-restart 'use-empty-bindings))))
                    (graph-query '(($s foaf@nonexistent $x)) graph))))
      ;; Should return empty list instead of :no-match
      (is (listp result))
      (is (null result)))))

;;; ============================================================================
;;; Phase 7: Query Operations (ASK, CONSTRUCT, DELETE-DATA)
;;; ============================================================================

;; Tests for ASK

(test ask-pattern-matches
  "Test ask returns T when pattern matches"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    (is (ask '(($s foaf@name $name)) graph))))

(test ask-pattern-no-match
  "Test ask returns NIL when pattern doesn't match"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    (is (not (ask '(($s foaf@age $age)) graph)))))

(test ask-empty-graph
  "Test ask returns NIL on empty graph"
  (let ((graph (make-graph)))
    (is (not (ask '(($s foaf@name $name)) graph)))))

(test ask-concrete-pattern-matches
  "Test ask with concrete pattern that matches"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    (is (ask '((alice foaf@name "Alice")) graph))))

(test ask-concrete-pattern-no-match
  "Test ask with concrete pattern that doesn't match"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    (is (not (ask '((alice foaf@name "Bob")) graph)))))

(test ask-multi-clause-matches
  "Test ask with multiple clauses that all match"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30))
                 graph)
    (is (ask '(($s foaf@name "Alice")
               ($s foaf@age 30))
             graph))))

(test ask-multi-clause-no-match
  "Test ask with multiple clauses where one doesn't match"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    (is (not (ask '(($s foaf@name "Alice")
                    ($s foaf@age 30))
                  graph)))))

;; Tests for expand-list-bindings

(test expand-list-bindings-single-triple
  "Test expand-list-bindings with single triple (no list)"
  (let ((result (expand-list-bindings '((alice foaf@name "Alice")))))
    (is (= 1 (length result)))
    (is (equal '(alice foaf@name "Alice") (first result)))))

(test expand-list-bindings-list-object
  "Test expand-list-bindings expands list in object position"
  (let ((result (expand-list-bindings '((alice foaf@knows (bob charlie))))))
    (is (= 2 (length result)))
    (is (member '(alice foaf@knows bob) result :test #'equal))
    (is (member '(alice foaf@knows charlie) result :test #'equal))))

(test expand-list-bindings-multiple-triples
  "Test expand-list-bindings with multiple triples"
  (let ((result (expand-list-bindings '((alice foaf@name "Alice")
                                        (bob foaf@name "Bob")))))
    (is (= 2 (length result)))
    (is (member '(alice foaf@name "Alice") result :test #'equal))
    (is (member '(bob foaf@name "Bob") result :test #'equal))))

(test expand-list-bindings-mixed
  "Test expand-list-bindings with mix of list and non-list objects"
  (let ((result (expand-list-bindings '((alice foaf@knows (bob charlie))
                                        (alice foaf@name "Alice")))))
    (is (= 3 (length result)))
    (is (member '(alice foaf@knows bob) result :test #'equal))
    (is (member '(alice foaf@knows charlie) result :test #'equal))
    (is (member '(alice foaf@name "Alice") result :test #'equal))))

(test expand-list-bindings-empty-list
  "Test expand-list-bindings with empty input"
  (is (null (expand-list-bindings '()))))

;; Tests for construct

(test construct-simple
  "Test construct with simple variable substitution"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (bob foaf@name "Bob"))
                         graph))
         (bindings (graph-query '(($s foaf@name $name)) graph))
         (result (construct '(($s rdf@type foaf@Person)) bindings)))
    (declare (ignore _))
    (is (= 2 (length result)))
    (is (member '(alice rdf@type foaf@Person) result :test #'equal))
    (is (member '(bob rdf@type foaf@Person) result :test #'equal))))

(test construct-multiple-clauses
  "Test construct with multiple template clauses"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@age 30))
                         graph))
         (bindings (graph-query '(($s foaf@name $name)
                                  ($s foaf@age $age))
                                graph))
         (result (construct '(($s rdf@type foaf@Person)
                              ($s schema@verified t))
                            bindings)))
    (declare (ignore _))
    (is (= 2 (length result)))
    (is (member '(alice rdf@type foaf@Person) result :test #'equal))
    (is (member '(alice schema@verified t) result :test #'equal))))

(test construct-with-list-expansion
  "Test construct expands list objects into multiple triples"
  (let* ((graph (make-graph))
         (_ (add-triple '(alice foaf@name "Alice") graph))
         ;; Manually create bindings with list in object position
         (bindings '(((($s . alice) ($friends . (bob charlie))))))
         (result (construct '(($s foaf@knows $friends)) bindings)))
    (declare (ignore _))
    (is (= 2 (length result)))
    (is (member '(alice foaf@knows bob) result :test #'equal))
    (is (member '(alice foaf@knows charlie) result :test #'equal))))

(test construct-no-matches
  "Test construct with no bindings returns empty list"
  (let ((result (construct '(($s rdf@type foaf@Person)) '())))
    (is (null result))))

(test construct-preserves-concrete-values
  "Test construct preserves concrete (non-variable) values in template"
  (let* ((graph (make-graph))
         (_ (add-triple '(alice foaf@name "Alice") graph))
         (bindings (graph-query '(($s foaf@name "Alice")) graph))
         (result (construct '(($s foaf@knows bob)) bindings)))
    (declare (ignore _))
    (is (= 1 (length result)))
    (is (equal '(alice foaf@knows bob) (first result)))))

;; Tests for delete-data

(test delete-data-single-match
  "Test delete-data removes matching triples"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    (is (delete-data '((alice foaf@name "Alice")) graph))
    ;; Verify alice's triple is gone
    (is (not (ask '((alice foaf@name "Alice")) graph)))
    ;; Verify bob's triple remains
    (is (ask '((bob foaf@name "Bob")) graph))))

(test delete-data-variable-pattern
  "Test delete-data with variable pattern deletes all matches"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob")
                   (charlie foaf@name "Charlie"))
                 graph)
    ;; Delete all foaf@name triples
    (is (delete-data '(($s foaf@name $name)) graph))
    ;; Verify all name triples are gone
    (is (not (ask '(($s foaf@name $name)) graph)))))

(test delete-data-no-match
  "Test delete-data returns NIL when pattern doesn't match"
  (let ((graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") graph)
    (is (not (delete-data '(($s foaf@age $age)) graph)))
    ;; Verify original triple still exists
    (is (ask '((alice foaf@name "Alice")) graph))))

(test delete-data-empty-graph
  "Test delete-data on empty graph returns NIL"
  (let ((graph (make-graph)))
    (is (not (delete-data '(($s foaf@name $name)) graph)))))

(test delete-data-multi-clause
  "Test delete-data with multiple clauses (join pattern)"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30)
                   (bob foaf@name "Bob")
                   (bob foaf@age 25))
                 graph)
    ;; Delete all triples for people named "Alice"
    (is (delete-data '(($s foaf@name "Alice")
                       ($s foaf@age $age))
                     graph))
    ;; Verify alice's age is gone
    (is (not (ask '((alice foaf@age 30)) graph)))
    ;; Verify bob's triples remain
    (is (ask '((bob foaf@name "Bob")) graph))
    (is (ask '((bob foaf@age 25)) graph))))

(test delete-data-preserves-other-triples
  "Test delete-data only removes matching triples"
  (let ((graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30)
                   (alice foaf@email "alice@example.com"))
                 graph)
    ;; Delete only age triple
    (is (delete-data '((alice foaf@age 30)) graph))
    ;; Verify age is gone but other triples remain
    (is (not (ask '((alice foaf@age 30)) graph)))
    (is (ask '((alice foaf@name "Alice")) graph))
    (is (ask '((alice foaf@email "alice@example.com")) graph))))

(test delete-data-calls-delete-hooks
  "Test delete-data triggers delete hooks"
  (let ((graph (make-graph))
        (hook-called nil))
    (add-triple '(alice foaf@name "Alice") graph)
    (add-hook-to-graph graph 'delete-hooks
                       (lambda (g op data)
                         (declare (ignore g op data))
                         (setf hook-called t)))
    (delete-data '((alice foaf@name "Alice")) graph)
    (is hook-called)))

;;; ============================================================================
;;; Phase 7: Additional query operations (SELECT, FILTER)
;;; ============================================================================

;; Tests for binding-val

(test binding-val-finds-variable
  "Test binding-val extracts value for variable"
  (let ((bindings '(($s . alice) ($name . "Alice") ($age . 30))))
    (is (equal 'alice (binding-val '$s bindings)))
    (is (equal "Alice" (binding-val '$name bindings)))
    (is (equal 30 (binding-val '$age bindings)))))

(test binding-val-missing-variable
  "Test binding-val returns NIL for missing variable"
  (let ((bindings '(($s . alice))))
    (is (null (binding-val '$name bindings)))))

(test binding-val-empty-bindings
  "Test binding-val with empty bindings"
  (is (null (binding-val '$s '()))))

;; Tests for bindings-from-row

(test bindings-from-row-simple
  "Test bindings-from-row extracts multiple variables"
  (let ((row '((($s . alice) ($name . "Alice") ($age . 30)))))
    (let ((result (bindings-from-row '($name $age) row)))
      (is (= 1 (length result)))
      (is (equal '("Alice" 30) (first result))))))

(test bindings-from-row-multiple-branches
  "Test bindings-from-row with multiple binding branches"
  (let ((row '((($s . alice) ($name . "Alice"))
               (($s . bob) ($name . "Bob")))))
    (let ((result (bindings-from-row '($s $name) row)))
      (is (= 2 (length result)))
      (is (member '(alice "Alice") result :test #'equal))
      (is (member '(bob "Bob") result :test #'equal)))))

(test bindings-from-row-missing-variable
  "Test bindings-from-row with missing variable returns NIL"
  (let ((row '((($s . alice) ($name . "Alice")))))
    (let ((result (bindings-from-row '($name $age) row)))
      (is (= 1 (length result)))
      (is (equal '("Alice" nil) (first result))))))

;; Tests for select

(test select-simple
  "Test select projects specific variables"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@age 30)
                           (bob foaf@name "Bob")
                           (bob foaf@age 25))
                         graph))
         (where-result (where '(($s foaf@name $name)
                                ($s foaf@age $age))
                              graph))
         (result (select '($name) where-result)))
    (declare (ignore _))
    (is (= 2 (length result)))
    (is (member '("Alice") result :test #'equal))
    (is (member '("Bob") result :test #'equal))))

(test select-multiple-variables
  "Test select with multiple variables"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@age 30))
                         graph))
         (where-result (where '(($s foaf@name $name)
                                ($s foaf@age $age))
                              graph))
         (result (select '($name $age) where-result)))
    (declare (ignore _))
    (is (= 1 (length result)))
    (is (equal '("Alice" 30) (first result)))))

(test select-all-variables
  "Test select with all variables (*)"
  (let* ((graph (make-graph))
         (_ (add-triple '(alice foaf@name "Alice") graph))
         (where-result (where '(($s foaf@name $name)) graph))
         (result (select '($s $name) where-result)))
    (declare (ignore _))
    (is (= 1 (length result)))
    (is (equal '(alice "Alice") (first result)))))

(test select-with-no-match
  "Test select returns nil values when WHERE returns :no-match"
  (let* ((result (select '($name $age) :no-match)))
    (is (= 1 (length result)))
    (is (equal '(nil nil) (first result)))))

(test select-with-nil
  "Test select returns nil values when WHERE returns nil"
  (let ((result (select '($name $age) nil)))
    (is (= 1 (length result)))
    (is (equal '(nil nil) (first result)))))

(test select-empty-variable-list
  "Test select with empty variable list"
  (let* ((graph (make-graph))
         (_ (add-triple '(alice foaf@name "Alice") graph))
         (where-result (where '(($s foaf@name $name)) graph))
         (result (select '() where-result)))
    (declare (ignore _))
    ;; Should return empty rows for each match
    (is (= 1 (length result)))
    (is (null (first result)))))

;; Tests for eval-with-bindings

(test eval-with-bindings-simple
  "Test eval-with-bindings binds variables and evaluates function"
  (let ((bindings '(($x . 5) ($y . 10))))
    (is (equal 15 (eval-with-bindings bindings (lambda () (+ $x $y)))))))

(test eval-with-bindings-with-symbols
  "Test eval-with-bindings handles unbound symbols as quoted"
  (let ((bindings '(($name . alice))))
    (is (equal 'alice (eval-with-bindings bindings (lambda () $name))))))

(test eval-with-bindings-filters-t-marker
  "Test eval-with-bindings filters out (t . value) markers"
  (let ((bindings '((t . ignore) ($x . 42))))
    (is (equal 42 (eval-with-bindings bindings (lambda () $x))))))

(test eval-with-bindings-comparison
  "Test eval-with-bindings with comparison predicate"
  (let ((bindings '(($age . 30))))
    (is (eval-with-bindings bindings (lambda () (> $age 25))))
    (is (not (eval-with-bindings bindings (lambda () (< $age 25)))))))

;; Tests for filter

(test filter-simple-predicate
  "Test filter with simple numeric comparison"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@age 30)
                           (bob foaf@age 25)
                           (charlie foaf@age 35))
                         graph))
         (where-result (where '(($s foaf@age $age)) graph))
         (result (filter (lambda () (> $age 28)) where-result)))
    (declare (ignore _))
    ;; Should return alice and charlie (ages 30 and 35)
    (is (= 2 (length result)))
    (is (every (lambda (binding-set)
                 (let ((age (cdr (assoc '$age (car binding-set)))))
                   (> age 28)))
               result))))

(test filter-string-comparison
  "Test filter with string comparison"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (bob foaf@name "Bob")
                           (ann foaf@name "Ann"))
                         graph))
         (where-result (where '(($s foaf@name $name)) graph))
         (result (filter (lambda () (string< $name "B")) where-result)))
    (declare (ignore _))
    ;; Should return alice and ann (names < "B")
    (is (= 2 (length result)))))

(test filter-no-matches
  "Test filter returns empty when no bindings satisfy predicate"
  (let* ((graph (make-graph))
         (_ (add-triple '(alice foaf@age 30) graph))
         (where-result (where '(($s foaf@age $age)) graph))
         (result (filter (lambda () (> $age 100)) where-result)))
    (declare (ignore _))
    (is (null result))))

(test filter-all-match
  "Test filter returns all when all bindings satisfy predicate"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@age 30)
                           (bob foaf@age 25))
                         graph))
         (where-result (where '(($s foaf@age $age)) graph))
         (result (filter (lambda () (> $age 20)) where-result)))
    (declare (ignore _))
    (is (= 2 (length result)))))

(test filter-with-multiple-variables
  "Test filter with predicate using multiple variables"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@age 30)
                           (bob foaf@name "Bob")
                           (bob foaf@age 25))
                         graph))
         (where-result (where '(($s foaf@name $name)
                                ($s foaf@age $age))
                              graph))
         (result (filter (lambda () (and (string= $name "Alice") (> $age 25)))
                         where-result)))
    (declare (ignore _))
    (is (= 1 (length result)))
    (is (equal 'alice (cdr (assoc '$s (caar result)))))))

(test filter-empty-bindings
  "Test filter with empty binding list"
  (is (null (filter (lambda () t) '()))))

;; Tests for filter-exists and filter-not-exists

(test filter-exists-basic
  "Test filter-exists keeps bindings where pattern matches"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@email "alice@example.com")
                           (bob foaf@name "Bob"))
                         graph))
         (where-result (where '(($person foaf@name $name)) graph))
         (result (filter-exists '(($person foaf@email $email)) graph where-result)))
    (declare (ignore _))
    ;; Should only return alice (has email)
    (is (= 1 (length result)))
    (is (equal 'alice (cdr (assoc '$person (caar result)))))))

(test filter-not-exists-basic
  "Test filter-not-exists keeps bindings where pattern doesn't match"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@email "alice@example.com")
                           (bob foaf@name "Bob"))
                         graph))
         (where-result (where '(($person foaf@name $name)) graph))
         (result (filter-not-exists '(($person foaf@email $email)) graph where-result)))
    (declare (ignore _))
    ;; Should only return bob (no email)
    (is (= 1 (length result)))
    (is (equal 'bob (cdr (assoc '$person (caar result)))))))

(test filter-exists-with-multiple-vars
  "Test filter-exists with pattern using multiple variables"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@knows bob)
                           (bob foaf@name "Bob")
                           (bob foaf@knows charlie))
                         graph))
         (where-result (where '(($person foaf@name $name)) graph))
         (result (filter-exists '(($person foaf@knows bob)) graph where-result)))
    (declare (ignore _))
    ;; Should only return alice (knows bob)
    (is (= 1 (length result)))
    (is (equal 'alice (cdr (assoc '$person (caar result)))))))

(test filter-not-exists-all-match
  "Test filter-not-exists when pattern matches everything"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (alice foaf@age 30)
                           (bob foaf@name "Bob")
                           (bob foaf@age 25))
                         graph))
         (where-result (where '(($person foaf@name $name)) graph))
         (result (filter-not-exists '(($person foaf@age $age)) graph where-result)))
    (declare (ignore _))
    ;; Should return empty (everyone has age)
    (is (null result))))

(test filter-exists-no-matches
  "Test filter-exists when pattern matches nothing"
  (let* ((graph (make-graph))
         (_ (add-triples '((alice foaf@name "Alice")
                           (bob foaf@name "Bob"))
                         graph))
         (where-result (where '(($person foaf@name $name)) graph))
         (result (filter-exists '(($person foaf@email $email)) graph where-result)))
    (declare (ignore _))
    ;; Should return empty (nobody has email)
    (is (null result))))

;;; ============================================================================
;;; Phase 8: Content Reference System Tests
;;; ============================================================================

(in-suite :storage)

(test content-reference-p-valid
  "Test content-reference-p recognizes valid file references"
  (is (content-reference-p "file:content-abc123.txt"))
  (is (content-reference-p "file:content-1234567890abcdef.txt")))

(test content-reference-p-invalid
  "Test content-reference-p rejects invalid formats"
  (is (not (content-reference-p "regular string")))
  (is (not (content-reference-p "file:other.txt")))
  (is (not (content-reference-p "content-abc123.txt")))
  (is (not (content-reference-p "")))
  (is (not (content-reference-p nil)))
  (is (not (content-reference-p 42))))

(test store-large-content-basic
  "Test store-large-content creates file reference for large strings"
  (let* ((large-content (make-string 1500 :initial-element #\x))
         (reference (store-large-content large-content)))
    (is (stringp reference))
    (is (content-reference-p reference))
    (is (alexandria:starts-with-subseq "file:content-" reference))
    (is (alexandria:ends-with-subseq ".txt" reference))))

(test store-large-content-small-unchanged
  "Test store-large-content returns small strings unchanged"
  (let* ((small-content "This is a short string")
         (result (store-large-content small-content)))
    (is (equal result small-content))))

(test store-large-content-threshold
  "Test store-large-content at 1000 character threshold"
  (let* ((at-threshold (make-string 1000 :initial-element #\a))
         (below-threshold (make-string 999 :initial-element #\b))
         (above-threshold (make-string 1001 :initial-element #\c)))
    ;; At or below threshold should be unchanged
    (is (equal at-threshold (store-large-content at-threshold)))
    (is (equal below-threshold (store-large-content below-threshold)))
    ;; Above threshold should be a reference
    (is (content-reference-p (store-large-content above-threshold)))))

(test store-large-content-deduplication
  "Test store-large-content produces same hash for same content"
  (let* ((content1 (make-string 1500 :initial-element #\z))
         (content2 (make-string 1500 :initial-element #\z))
         (ref1 (store-large-content content1))
         (ref2 (store-large-content content2)))
    ;; Same content should produce same reference
    (is (equal ref1 ref2))))

(test store-large-content-different-hashes
  "Test store-large-content produces different hashes for different content"
  (let* ((content1 (make-string 1500 :initial-element #\a))
         (content2 (make-string 1500 :initial-element #\b))
         (ref1 (store-large-content content1))
         (ref2 (store-large-content content2)))
    ;; Different content should produce different references
    (is (not (equal ref1 ref2)))))

(test resolve-content-reference-basic
  "Test resolve-content-reference reads stored content"
  (let* ((original-content (make-string 1500 :initial-element #\q))
         (reference (store-large-content original-content))
         (resolved (resolve-content-reference reference)))
    (is (equal original-content resolved))))

(test resolve-content-reference-non-reference
  "Test resolve-content-reference returns non-references unchanged"
  (let ((regular-string "not a reference"))
    (is (equal regular-string (resolve-content-reference regular-string)))))

(test resolve-content-reference-missing-file
  "Test resolve-content-reference handles missing files gracefully"
  (let ((fake-reference "file:content-nonexistent123.txt"))
    ;; Should either return the reference unchanged or signal an error
    ;; Implementation can choose appropriate behavior
    (handler-case
        (let ((result (resolve-content-reference fake-reference)))
          (is (or (equal result fake-reference)
                  (null result))))
      (error () (pass)))))

(test process-triple-object-large-string
  "Test process-triple-object converts large strings to references"
  (let* ((large-obj (make-string 1500 :initial-element #\m))
         (processed (process-triple-object large-obj)))
    (is (content-reference-p processed))))

(test process-triple-object-small-string
  "Test process-triple-object leaves small strings unchanged"
  (let* ((small-obj "small")
         (processed (process-triple-object small-obj)))
    (is (equal processed small-obj))))

(test process-triple-object-non-string
  "Test process-triple-object leaves non-strings unchanged"
  (is (equal 42 (process-triple-object 42)))
  (is (equal 'symbol (process-triple-object 'symbol)))
  (is (equal nil (process-triple-object nil))))

(test resolve-triple-object-with-reference
  "Test resolve-triple-object resolves file references in triples"
  (let* ((original-content (make-string 1500 :initial-element #\r))
         (reference (store-large-content original-content))
         (triple (list 'subj 'pred reference))
         (resolved-triple (resolve-triple-object triple)))
    (is (equal (list 'subj 'pred original-content) resolved-triple))))

(test resolve-triple-object-without-reference
  "Test resolve-triple-object leaves regular triples unchanged"
  (let* ((triple '(alice foaf@name "Alice"))
         (resolved (resolve-triple-object triple)))
    (is (equal triple resolved))))

(test resolve-triple-objects-batch
  "Test resolve-triple-objects resolves multiple triples"
  (let* ((content1 (make-string 1500 :initial-element #\x))
         (content2 (make-string 1500 :initial-element #\y))
         (ref1 (store-large-content content1))
         (ref2 (store-large-content content2))
         (triples (list (list 'subj1 'pred1 ref1)
                        (list 'subj2 'pred2 "small")
                        (list 'subj3 'pred3 ref2)))
         (resolved (resolve-triple-objects triples)))
    (is (= 3 (length resolved)))
    (is (equal content1 (third (first resolved))))
    (is (equal "small" (third (second resolved))))
    (is (equal content2 (third (third resolved))))))

(test content-reference-integration-add-triple
  "Test content references are created automatically when adding triples"
  (let* ((graph (make-graph))
         (large-bio (make-string 1500 :initial-element #\L)))
    ;; Add triple with large object
    (add-triple 'alice 'foaf@bio large-bio graph)
    ;; Get raw triple (should have reference)
    (let ((raw (raw-triples '(alice foaf@bio t) graph)))
      (is (= 1 (length raw)))
      (is (content-reference-p (third (first raw)))))))

(test content-reference-integration-triples
  "Test triples function resolves content references automatically"
  (let* ((graph (make-graph))
         (large-bio (make-string 1500 :initial-element #\B)))
    ;; Add triple with large object
    (add-triple 'bob 'foaf@bio large-bio graph)
    ;; Get resolved triple
    (let ((resolved (triples '(bob foaf@bio t) graph)))
      (is (= 1 (length resolved)))
      (is (equal large-bio (third (first resolved)))))))

(test content-reference-roundtrip
  "Test complete roundtrip: store large content, add to graph, retrieve"
  (let* ((graph (make-graph))
         (large-desc (concatenate 'string
                                   "This is a very long description that exceeds "
                                   "the 1000 character threshold for content references. "
                                   (make-string 900 :initial-element #\x))))
    ;; Add triple with large content
    (add-triple 'project 'dc@description large-desc graph)
    ;; Retrieve via raw-triples (should have reference)
    (let ((raw (raw-triples '(project dc@description t) graph)))
      (is (content-reference-p (third (first raw)))))
    ;; Retrieve via triples (should have resolved content)
    (let ((resolved (triples '(project dc@description t) graph)))
      (is (equal large-desc (third (first resolved)))))))

;;; ============================================================================
;;; Phase 9: Serialization and Format Conversion Tests
;;; ============================================================================

(in-suite :persistence)

;;; Serialization Tests

(test triples-to-string-basic
  "Test triples-to-string with simple triples"
  (let* ((triples '((alice foaf@name "Alice")
                    (bob foaf@name "Bob")))
         (serialized (triples-to-string triples)))
    (is (stringp serialized))
    (is (search "alice" serialized))
    (is (search "foaf@name" serialized))
    (is (search "Alice" serialized))))

(test triples-to-string-symbols-with-special-chars
  "Test triples-to-string handles symbols with # correctly"
  (let* ((triples '((|resource#1| foaf@name "Test")))
         (serialized (triples-to-string triples)))
    ;; Should be able to read it back
    (let ((read-back (read-from-string serialized)))
      (is (equal triples read-back)))))

(test triples-to-string-empty
  "Test triples-to-string with empty list"
  (let ((serialized (triples-to-string nil)))
    (is (stringp serialized))
    (is (equal nil (read-from-string serialized)))))

(test triples-to-string-preserves-types
  "Test triples-to-string preserves different value types"
  (let* ((triples '((alice foaf@age 30)
                    (bob foaf@name "Bob")
                    (charlie rdf@type foaf@Person)))
         (serialized (triples-to-string triples))
         (read-back (read-from-string serialized)))
    (is (equal triples read-back))))

;;; Format Conversion Tests

(test el-rdf-symbol-p-detects-el-format
  "Test el-rdf-symbol-p detects el-rdf format symbols"
  (is (el-rdf-symbol-p '|foaf:name|))
  (is (el-rdf-symbol-p '|schema:Person|))
  (is (el-rdf-symbol-p '|rdf:type|)))

(test el-rdf-symbol-p-rejects-cl-format
  "Test el-rdf-symbol-p rejects cl-rdf format"
  (is (not (el-rdf-symbol-p 'foaf@name)))
  (is (not (el-rdf-symbol-p 'schema@Person))))

(test el-rdf-symbol-p-rejects-variables
  "Test el-rdf-symbol-p doesn't convert variables"
  (is (not (el-rdf-symbol-p '$name)))
  (is (not (el-rdf-symbol-p '$subject))))

(test el-rdf-symbol-p-rejects-keywords
  "Test el-rdf-symbol-p doesn't convert keywords"
  (is (not (el-rdf-symbol-p :keyword)))
  (is (not (el-rdf-symbol-p :test))))

(test el-rdf-symbol-p-rejects-non-symbols
  "Test el-rdf-symbol-p rejects non-symbols"
  (is (not (el-rdf-symbol-p "string")))
  (is (not (el-rdf-symbol-p 42)))
  (is (not (el-rdf-symbol-p nil))))

(test convert-symbol-el-to-cl-basic
  "Test convert-symbol-el-to-cl converts namespace:resource"
  (is (eq 'foaf@name (convert-symbol-el-to-cl '|foaf:name|)))
  (is (eq 'schema@Person (convert-symbol-el-to-cl '|schema:Person|)))
  (is (eq 'rdf@type (convert-symbol-el-to-cl '|rdf:type|))))

(test convert-symbol-el-to-cl-preserves-cl-format
  "Test convert-symbol-el-to-cl leaves cl-rdf symbols unchanged"
  (is (eq 'foaf@name (convert-symbol-el-to-cl 'foaf@name)))
  (is (eq 'schema@Person (convert-symbol-el-to-cl 'schema@Person))))

(test convert-symbol-el-to-cl-preserves-variables
  "Test convert-symbol-el-to-cl doesn't convert variables"
  (is (eq '$name (convert-symbol-el-to-cl '$name)))
  (is (eq '$subject (convert-symbol-el-to-cl '$subject))))

(test convert-symbol-el-to-cl-preserves-keywords
  "Test convert-symbol-el-to-cl doesn't convert keywords"
  (is (eq :keyword (convert-symbol-el-to-cl :keyword))))

(test convert-symbol-el-to-cl-preserves-non-symbols
  "Test convert-symbol-el-to-cl preserves non-symbol values"
  (is (equal "string" (convert-symbol-el-to-cl "string")))
  (is (equal 42 (convert-symbol-el-to-cl 42)))
  (is (equal nil (convert-symbol-el-to-cl nil))))

(test convert-triple-el-to-cl-basic
  "Test convert-triple-el-to-cl converts entire triple"
  (let ((el-triple '(alice |foaf:name| "Alice"))
        (cl-triple '(alice foaf@name "Alice")))
    (is (equal cl-triple (convert-triple-el-to-cl el-triple)))))

(test convert-triple-el-to-cl-mixed-format
  "Test convert-triple-el-to-cl handles mixed el/cl format"
  (let ((mixed '(alice |foaf:name| "Alice"))
        (expected '(alice foaf@name "Alice")))
    (is (equal expected (convert-triple-el-to-cl mixed)))))

(test convert-triple-el-to-cl-preserves-strings
  "Test convert-triple-el-to-cl preserves string objects"
  (let ((triple '(bob |foaf:bio| "A long biography"))
        (expected '(bob foaf@bio "A long biography")))
    (is (equal expected (convert-triple-el-to-cl triple)))))

(test convert-triple-el-to-cl-with-rdf-type
  "Test convert-triple-el-to-cl handles rdf:type"
  (let ((el-triple '(alice |rdf:type| |foaf:Person|))
        (cl-triple '(alice rdf@type foaf@Person)))
    (is (equal cl-triple (convert-triple-el-to-cl el-triple)))))

;;; Save/Load Tests

(test save-graph-basic
  "Test save-graph creates file with triples"
  (let* ((graph (make-graph))
         (tmpfile (format nil "/tmp/cl-rdf-test-~A.rdf" (get-universal-time))))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    (save-graph graph tmpfile)
    (is (probe-file tmpfile))
    (delete-file tmpfile)))

(test save-load-roundtrip-cl-format
  "Test save-graph and load-graph preserve cl-rdf format triples"
  (let* ((graph (make-graph))
         (tmpfile (format nil "/tmp/cl-rdf-test-~A.rdf" (get-universal-time))))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@age 30)
                   (charlie rdf@type foaf@Person))
                 graph)
    (save-graph graph tmpfile)

    (let ((loaded-graph (make-graph)))
      (load-graph loaded-graph tmpfile)
      (let ((loaded-triples (triples '(t t t) loaded-graph)))
        (is (= 3 (length loaded-triples)))
        (is (member '(alice foaf@name "Alice") loaded-triples :test #'equal))
        (is (member '(bob foaf@age 30) loaded-triples :test #'equal))
        (is (member '(charlie rdf@type foaf@Person) loaded-triples :test #'equal))))

    (delete-file tmpfile)))

(test load-graph-el-format-conversion
  "Test load-graph auto-converts el-rdf format to cl-rdf"
  (let* ((tmpfile (format nil "/tmp/cl-rdf-test-~A.rdf" (get-universal-time)))
         (el-format-triples '((alice |foaf:name| "Alice")
                              (bob |foaf:age| 30)
                              (charlie |rdf:type| |foaf:Person|))))
    ;; Write el-rdf format file directly (symbols with : will be written with pipes)
    (with-open-file (out tmpfile
                         :direction :output
                         :if-exists :supersede)
      (write el-format-triples :stream out :case :downcase :readably t))

    ;; Load and verify conversion
    (let ((graph (make-graph)))
      (load-graph graph tmpfile)
      (let ((loaded-triples (triples '(t t t) graph)))
        (is (= 3 (length loaded-triples)))
        ;; Should be converted to cl-rdf format
        (is (member '(alice foaf@name "Alice") loaded-triples :test #'equal))
        (is (member '(bob foaf@age 30) loaded-triples :test #'equal))
        (is (member '(charlie rdf@type foaf@Person) loaded-triples :test #'equal))))

    (delete-file tmpfile)))

(test save-preserves-content-references
  "Test save-graph preserves content references"
  (let* ((graph (make-graph))
         (large-content (make-string 1500 :initial-element #\x))
         (tmpfile (format nil "/tmp/cl-rdf-test-~A.rdf" (get-universal-time))))
    (add-triple 'alice 'foaf@bio large-content graph)

    ;; Save and check raw triples have reference
    (save-graph graph tmpfile)

    ;; Load and verify content is resolved
    (let ((loaded-graph (make-graph)))
      (load-graph loaded-graph tmpfile)
      (let ((loaded-triples (triples '(alice foaf@bio t) loaded-graph)))
        (is (= 1 (length loaded-triples)))
        (is (equal large-content (third (first loaded-triples))))))

    (delete-file tmpfile)))

(test save-graph-empty
  "Test save-graph handles empty graph"
  (let* ((graph (make-graph))
         (tmpfile (format nil "/tmp/cl-rdf-test-~A.rdf" (get-universal-time))))
    (save-graph graph tmpfile)
    (is (probe-file tmpfile))

    (let ((loaded-graph (make-graph)))
      (load-graph loaded-graph tmpfile)
      (is (null (triples '(t t t) loaded-graph))))

    (delete-file tmpfile)))

(test load-graph-nonexistent-file
  "Test load-graph handles missing files gracefully"
  (let ((graph (make-graph)))
    (signals error
      (load-graph graph "/nonexistent/path/file.rdf"))))

(test save-graph-symbols-with-hash
  "Test save-graph handles symbols with # character"
  (let* ((graph (make-graph))
         (tmpfile (format nil "/tmp/cl-rdf-test-~A.rdf" (get-universal-time))))
    (add-triple '|resource#1| 'foaf@name "Test" graph)
    (save-graph graph tmpfile)

    (let ((loaded-graph (make-graph)))
      (load-graph loaded-graph tmpfile)
      (let ((loaded-triples (triples '(t t t) loaded-graph)))
        (is (= 1 (length loaded-triples)))
        (is (equal '(|resource#1| foaf@name "Test") (first loaded-triples)))))

    (delete-file tmpfile)))

;;; ============================================================================
;;; Phase 10: Checkpointing System Tests
;;; ============================================================================

(in-suite :persistence)

;;; Checkpoint Utilities Tests

(test get-checkpoint-dir-creates-directory
  "Test get-checkpoint-dir creates checkpoint directory"
  (let ((dir (get-checkpoint-dir)))
    (is (stringp dir))
    (is (probe-file dir))
    (is (uiop:directory-pathname-p dir))))

(test get-checkpoint-dir-uses-xdg-cache
  "Test get-checkpoint-dir uses XDG_CACHE_HOME"
  (let ((dir (get-checkpoint-dir)))
    (is (search "cl-rdf" (namestring dir)))
    (is (search "checkpoints" (namestring dir)))))

(test checkpoint-file-path-format
  "Test checkpoint-file-path generates correct format"
  (let ((path (checkpoint-file-path "test-graph")))
    (is (stringp path))
    (is (search "test-graph.checkpoint" path))
    (is (search "checkpoints" path))))

;;; Checkpoint Operations Tests

(test save-named-graph-basic
  "Test save-named-graph saves graph to checkpoint"
  (let ((graph (make-graph :name "test-save")))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    (save-named-graph graph)
    (let ((checkpoint-file (checkpoint-file-path "test-save")))
      (is (probe-file checkpoint-file))
      (delete-checkpoint "test-save"))))

(test save-named-graph-requires-name
  "Test save-named-graph errors on unnamed graph"
  (let ((graph (make-graph)))
    (signals error
      (save-named-graph graph))))

(test restore-named-graph-basic
  "Test restore-named-graph loads saved graph"
  (let ((original-graph (make-graph :name "test-restore")))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@age 30))
                 original-graph)
    (save-named-graph original-graph)

    (let ((restored-graph (restore-named-graph "test-restore")))
      (is (not (null restored-graph)))
      (let ((restored-triples (triples '(t t t) restored-graph)))
        (is (= 2 (length restored-triples)))
        (is (member '(alice foaf@name "Alice") restored-triples :test #'equal))
        (is (member '(bob foaf@age 30) restored-triples :test #'equal))))

    (delete-checkpoint "test-restore")))

(test restore-named-graph-missing-file
  "Test restore-named-graph handles missing checkpoint"
  (signals error
    (restore-named-graph "nonexistent-checkpoint")))

(test register-graph-for-checkpointing-basic
  "Test register-graph-for-checkpointing sets up auto-checkpointing"
  (let ((graph (make-graph :name "test-register")))
    (register-graph-for-checkpointing graph "test-register")

    ;; Add data which should trigger checkpoint
    (add-triples '((alice foaf@name "Alice")) graph)

    ;; Check checkpoint was created
    (let ((checkpoint-file (checkpoint-file-path "test-register")))
      (is (probe-file checkpoint-file)))

    (delete-checkpoint "test-register")))

(test checkpoint-hook-saves-on-add
  "Test checkpoint-hook triggers on add-triples"
  (let ((graph (make-graph :name "test-hook")))
    (register-graph-for-checkpointing graph "test-hook")

    ;; Add triples - should trigger checkpoint
    (add-triples '((bob foaf@name "Bob")) graph)

    ;; Verify checkpoint exists
    (is (probe-file (checkpoint-file-path "test-hook")))

    ;; Verify we can restore
    (let ((restored (restore-named-graph "test-hook")))
      (is (member '(bob foaf@name "Bob")
                  (triples '(t t t) restored)
                  :test #'equal)))

    (delete-checkpoint "test-hook")))

(test checkpoint-hook-saves-on-delete
  "Test checkpoint-hook triggers on delete-triples"
  (let ((graph (make-graph :name "test-hook-delete")))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob"))
                 graph)
    (register-graph-for-checkpointing graph "test-hook-delete")

    ;; Delete triples - should trigger checkpoint
    (delete-triples '((bob foaf@name "Bob")) graph)

    ;; Verify checkpoint has updated data
    (let ((restored (restore-named-graph "test-hook-delete")))
      (let ((restored-triples (triples '(t t t) restored)))
        (is (= 1 (length restored-triples)))
        (is (member '(alice foaf@name "Alice") restored-triples :test #'equal))
        (is (not (member '(bob foaf@name "Bob") restored-triples :test #'equal)))))

    (delete-checkpoint "test-hook-delete")))

;;; Checkpoint Metadata Tests

(test save-checkpoint-metadata-basic
  "Test save-checkpoint-metadata creates metadata file"
  (save-checkpoint-metadata "test-meta" 'add-triples '((alice foaf@name "Alice")))

  (let* ((checkpoint-dir (get-checkpoint-dir))
         (metadata-file (merge-pathnames "test-meta.metadata" checkpoint-dir)))
    (is (probe-file metadata-file))
    (delete-file metadata-file)))

(test load-checkpoint-metadata-basic
  "Test load-checkpoint-metadata reads saved metadata"
  (save-checkpoint-metadata "test-meta-load" 'add-triples '((alice foaf@name "Alice") (bob foaf@age 30)))

  (let ((metadata (load-checkpoint-metadata "test-meta-load")))
    (is (not (null metadata)))
    (is (eql 'add-triples (getf metadata :last-operation)))
    (is (= 2 (getf metadata :data-size)))
    (is (not (null (getf metadata :timestamp)))))

  (let* ((checkpoint-dir (get-checkpoint-dir))
         (metadata-file (merge-pathnames "test-meta-load.metadata" checkpoint-dir)))
    (delete-file metadata-file)))

(test load-checkpoint-metadata-missing
  "Test load-checkpoint-metadata returns nil for missing file"
  (let ((metadata (load-checkpoint-metadata "nonexistent-meta")))
    (is (null metadata))))

(test list-checkpoints-empty
  "Test list-checkpoints returns empty when no checkpoints"
  ;; Clean up any existing checkpoints first
  (let ((existing (list-checkpoints)))
    (dolist (cp existing)
      (let ((name (subseq cp 0 (- (length cp) 11)))) ; Remove ".checkpoint"
        (delete-checkpoint name))))

  (let ((checkpoints (list-checkpoints)))
    (is (or (null checkpoints) (listp checkpoints)))))

(test list-checkpoints-shows-saved
  "Test list-checkpoints finds saved checkpoints"
  (let ((graph (make-graph :name "test-list-1")))
    (add-triple 'alice 'foaf@name "Alice" graph)
    (save-named-graph graph))

  (let ((graph2 (make-graph :name "test-list-2")))
    (add-triple 'bob 'foaf@name "Bob" graph2)
    (save-named-graph graph2))

  (let ((checkpoints (list-checkpoints)))
    (is (member "test-list-1.checkpoint" checkpoints :test #'equal))
    (is (member "test-list-2.checkpoint" checkpoints :test #'equal)))

  (delete-checkpoint "test-list-1")
  (delete-checkpoint "test-list-2"))

(test delete-checkpoint-removes-files
  "Test delete-checkpoint removes checkpoint and metadata files"
  (let ((graph (make-graph :name "test-delete")))
    (add-triple 'alice 'foaf@name "Alice" graph)
    (save-named-graph graph)
    (save-checkpoint-metadata "test-delete" 'manual-save nil))

  (let* ((checkpoint-file (checkpoint-file-path "test-delete"))
         (checkpoint-dir (get-checkpoint-dir))
         (metadata-file (merge-pathnames "test-delete.metadata" checkpoint-dir)))
    (is (probe-file checkpoint-file))
    (is (probe-file metadata-file))

    (delete-checkpoint "test-delete")

    (is (not (probe-file checkpoint-file)))
    (is (not (probe-file metadata-file)))))

(test delete-checkpoint-missing-files
  "Test delete-checkpoint handles missing files gracefully"
  ;; Should not error even if files don't exist
  (delete-checkpoint "truly-nonexistent-checkpoint"))

(test checkpoint-content-references
  "Test checkpoints preserve content references"
  (let ((graph (make-graph :name "test-content-ref"))
        (large-content (make-string 1500 :initial-element #\C)))
    (add-triple 'alice 'foaf@bio large-content graph)
    (save-named-graph graph)

    (let ((restored (restore-named-graph "test-content-ref")))
      (let ((restored-triples (triples '(alice foaf@bio t) restored)))
        (is (= 1 (length restored-triples)))
        (is (equal large-content (third (first restored-triples))))))

    (delete-checkpoint "test-content-ref")))

(test checkpoint-roundtrip-complex
  "Test complete checkpoint roundtrip with complex data"
  (let ((graph (make-graph :name "test-complex")))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30)
                   (alice foaf@knows bob)
                   (bob foaf@name "Bob")
                   (bob foaf@age 25)
                   (bob rdf@type foaf@Person))
                 graph)
    (save-named-graph graph)

    (let ((restored (restore-named-graph "test-complex")))
      (let ((restored-triples (triples '(t t t) restored)))
        (is (= 6 (length restored-triples)))
        (is (member '(alice foaf@name "Alice") restored-triples :test #'equal))
        (is (member '(bob rdf@type foaf@Person) restored-triples :test #'equal))))

    (delete-checkpoint "test-complex")))

;;; ============================================================================
;;; Phase 11: TTL Import Tests
;;; ============================================================================

(in-suite :ttl)

;;; Basic TTL Import Tests

(test import-ttl-basic
  "Test basic TTL import with prefixes"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-ttl-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix schema: <https://schema.org/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

schema:Person rdf:type rdfs:Class .
schema:Person rdfs:label \"Person\" .
schema:name rdf:type rdf:Property .
schema:name rdfs:label \"name\" ." out))

    (import-ttl tmpfile graph)

    (let ((all-triples (triples '(t t t) graph)))
      (is (= 4 (length all-triples)))
      (is (ask (graph-query '((schema@Person rdf@type rdfs@Class)) graph)))
      (is (ask (graph-query '((schema@name rdfs@label "name")) graph))))

    (delete-file tmpfile)))

(test import-ttl-rdf-collections-complex
  "Test RDF collections with owl:unionOf - must not create malformed symbols"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-collection-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix wn30schema: <http://example.org/wn30schema/> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

wn30schema:seeAlso a owl:ObjectProperty ;
    rdfs:domain [ a owl:Class ;
                  owl:unionOf ( wn30schema:AdjectiveWordSense wn30schema:VerbWordSense ) ] ;
    rdfs:range [ a owl:Class ;
                 owl:unionOf ( wn30schema:VerbWordSense wn30schema:AdjectiveWordSense ) ] ." out))

    (import-ttl tmpfile graph)

    (let ((all-triples (triples '(t t t) graph)))
      ;; Check no malformed symbols with ( or )
      (dolist (triple all-triples)
        (dolist (elem triple)
          (when (symbolp elem)
            (let ((name (symbol-name elem)))
              (is (not (find #\( name)))
              (is (not (find #\) name)))))))

      ;; Should have owl@unionOf relationships
      (let ((union-triples (remove-if-not
                            (lambda (tr) (eq (second tr) 'owl@unionOf))
                            all-triples)))
        (is (= 2 (length union-triples))))

      ;; Should have rdf@first and rdf@rest triples
      (is (some (lambda (tr) (eq (second tr) 'rdf@first)) all-triples))
      (is (some (lambda (tr) (eq (second tr) 'rdf@rest)) all-triples)))

    (delete-file tmpfile)))

(test import-ttl-blank-nodes
  "Test blank node import"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-blanks-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix ex: <http://example.org/> .

_:person1 ex:name \"Alice\" .
_:person2 ex:knows _:person1 ." out))

    (import-ttl tmpfile graph)

    (let ((all-triples (triples '(t t t) graph)))
      (is (= 2 (length all-triples)))
      ;; Subjects should be blank nodes (_:G...)
      (dolist (triple all-triples)
        (is (symbolp (first triple)))
        (is (alexandria:starts-with-subseq "_:" (symbol-name (first triple))))))

    (delete-file tmpfile)))

(test import-ttl-blank-node-brackets
  "Test blank node bracket notation [ ... ]"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-brackets-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix frame: <http://example.org/frame/> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

frame:Killing rdfs:subClassOf [ a owl:Restriction ;
                                 owl:onProperty frame:hasComponent ] ." out))

    (import-ttl tmpfile graph)

    (let ((all-triples (triples '(t t t) graph)))
      ;; Should parse bracket notation into separate triples
      (is (>= (length all-triples) 3))

      ;; Check no malformed symbols with [ or ]
      (dolist (triple all-triples)
        (dolist (elem triple)
          (when (symbolp elem)
            (is (not (find #\[ (symbol-name elem))))
            (is (not (find #\] (symbol-name elem))))))))

    (delete-file tmpfile)))

(test import-ttl-literals-and-datatypes
  "Test various literal types"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-literals-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix ex: <http://example.org/> .

ex:person ex:name \"John Doe\" .
ex:person ex:age \"30\"^^<http://www.w3.org/2001/XMLSchema#integer> .
ex:person ex:description \"A person\"@en ." out))

    (import-ttl tmpfile graph)

    (is (ask (graph-query '((ex@person ex@name "John Doe")) graph)))
    (is (ask (graph-query '((ex@person ex@age 30)) graph)))
    (is (ask (graph-query '((ex@person ex@description "A person")) graph))))

    (delete-file tmpfile))

(test import-ttl-comments
  "Test TTL with comments and empty lines"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-comments-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix ex: <http://example.org/> .

# Comment line
ex:alice ex:name \"Alice\" .

# Another comment
ex:bob ex:name \"Bob\" ." out))

    (import-ttl tmpfile graph)

    (let ((all-triples (triples '(t t t) graph)))
      (is (= 2 (length all-triples))))

    (delete-file tmpfile)))

(test import-ttl-empty-collection
  "Test empty RDF collection ()"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-empty-coll-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix ex: <http://example.org/> .

ex:emptyList ex:value () ." out))

    (import-ttl tmpfile graph)

    (is (ask (graph-query '((ex@emptyList ex@value rdf@nil)) graph)))

    (delete-file tmpfile)))

(test import-ttl-with-namespace-prefix
  "Test import with namespace parameter"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-ns-~A.ttl" (get-universal-time))))
    (with-open-file (out tmpfile :direction :output :if-exists :supersede)
      (write-string "@prefix schema: <https://schema.org/> .

:hasOccupation schema:label \"has occupation\" .
someProperty schema:label \"some property\" ." out))

    (import-ttl tmpfile graph "myschema")

    (is (ask (graph-query '((myschema@hasOccupation schema@label "has occupation")) graph)))
    (is (ask (graph-query '((myschema@someProperty schema@label "some property")) graph)))

    (delete-file tmpfile)))

;;; ============================================================================
;;; Phase 12: Visualization Tests
;;; ============================================================================

(in-suite :visualization)

;;; Helper Function Tests

(test namespace-function
  "Test namespace extraction from symbols"
  (is (string= "foaf" (namespace 'foaf@name)))
  (is (string= "schema" (namespace 'schema@Person)))
  (is (string= "rdf" (namespace 'rdf@type)))
  ;; Symbol without @ should return whole symbol
  (is (string= "alice" (namespace 'alice))))

(test nodes-function
  "Test extracting all nodes from triples"
  (let ((triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob")
                   (alice foaf@knows bob))))
    (let ((node-list (nodes triples)))
      ;; Should include subjects and objects, NOT predicates
      (is (member 'alice node-list))
      (is (member 'bob node-list))
      (is (member "Alice" node-list :test #'equal))
      (is (member "Bob" node-list :test #'equal))
      ;; Predicates should NOT be in nodes list
      (is (not (member 'foaf@name node-list)))
      (is (not (member 'foaf@knows node-list))))))

(test literals-function
  "Test filtering literals from node list"
  (let ((nodelist '(alice bob "Alice" "Bob" 30 foaf@name)))
    (let ((lits (literals nodelist)))
      ;; Should only include non-symbols
      (is (member "Alice" lits :test #'equal))
      (is (member "Bob" lits :test #'equal))
      (is (member 30 lits))
      (is (not (member 'alice lits)))
      (is (not (member 'bob lits)))
      (is (not (member 'foaf@name lits))))))

;;; Rendering Function Tests

(test render-triple-with-symbol-object
  "Test rendering triple with symbol object (edge between nodes)"
  (let ((triple '(alice foaf@knows bob)))
    (let ((dot (render-triple triple)))
      ;; Should create edge from alice to bob labeled with foaf@knows
      (is (alexandria:starts-with-subseq "\"alice\" -> \"bob\"" dot))
      (is (search "[label=\"foaf@knows\"]" dot)))))

(test render-triple-with-literal-object
  "Test rendering triple with literal object (creates literal node)"
  (let ((triple '(alice foaf@name "Alice")))
    (let ((dot (render-triple triple)))
      ;; Should create edge to generated node and define literal node
      (is (search "alice" dot))
      (is (search "foaf@name" dot))
      (is (search "Alice" dot))
      (is (search "[label=" dot))
      (is (search "shape=box" dot)))))

(test render-triples-basic
  "Test rendering multiple triples to DOT format"
  (let ((triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob")
                   (alice foaf@knows bob))))
    (let ((dot (render-triples triples)))
      ;; Should have DOT header
      (is (search "digraph G {" dot))
      ;; Should have node styling
      (is (search "node[" dot))
      ;; Should have edges
      (is (search "alice" dot))
      (is (search "bob" dot))
      (is (search "foaf@knows" dot))
      ;; Should have closing brace
      (is (search "}" dot)))))

(test render-triples-with-styles
  "Test rendering with custom node styles"
  (let ((triples '((schema@Person rdf@type rdfs@Class)))
        (styles '(("schema" . (:color "blue" :fillcolor "lightblue" :fontcolor "black")))))
    (let ((dot (render-triples triples styles)))
      (is (search "digraph G {" dot))
      (is (search "schema@Person" dot)))))

(test apply-node-styles-basic
  "Test applying styles to nodes"
  (let ((triples '((alice foaf@name "Alice")
                   (bob foaf@name "Bob")))
        (styles '(("default" . (:color "red" :fillcolor "pink" :fontcolor "white")))))
    (let ((styled (apply-node-styles triples styles)))
      ;; Should generate style definitions for nodes
      (is (stringp styled))
      ;; Should include node names and colors
      (when (> (length styled) 0)
        (is (or (search "alice" styled)
                (search "bob" styled)))))))

(test render-graph-to-svg
  "Test rendering graph to SVG file via Graphviz"
  (let ((triples '((alice foaf@name "Alice")
                   (bob foaf@knows alice)))
        (tmpfile (format nil "/tmp/cl-rdf-graph-~A.svg" (get-universal-time))))
    ;; Only run if dot command is available
    (handler-case
        (progn
          (render-graph triples tmpfile)
          (is (probe-file tmpfile))
          (when (probe-file tmpfile)
            (delete-file tmpfile)))
      (error (e)
        ;; Skip test if Graphviz not installed
        (format t "~%Skipping render-graph test (Graphviz not available): ~A~%" e)
        (is t))))) ; Pass test anyway

(test render-graph-json-to-json
  "Test rendering graph to JSON file via Graphviz"
  (let ((triples '((alice foaf@name "Alice")
                   (bob foaf@knows alice)))
        (tmpfile (format nil "/tmp/cl-rdf-graph-~A.json" (get-universal-time))))
    ;; Only run if dot command is available
    (handler-case
        (progn
          (render-graph-json triples tmpfile)
          (is (probe-file tmpfile))
          (when (probe-file tmpfile)
            (delete-file tmpfile)))
      (error (e)
        ;; Skip test if Graphviz not installed
        (format t "~%Skipping render-graph-json test (Graphviz not available): ~A~%" e)
        (is t))))) ; Pass test anyway

;;; ============================================================================
;;; Phase 13: Bidirectional Format Conversion (cl-rdf → el-rdf)
;;; ============================================================================

(in-suite :conversion)

;;; Symbol Conversion Tests

(test convert-symbol-cl-to-elisp
  "Test converting cl-rdf symbols to el-rdf format (@ to :)"
  (let ((converted1 (convert-symbol-cl-to-elisp 'foaf@name))
        (converted2 (convert-symbol-cl-to-elisp 'schema@Person))
        (converted3 (convert-symbol-cl-to-elisp 'rdf@type)))
    (is (string= (symbol-name converted1) "foaf:name"))
    (is (string= (symbol-name converted2) "schema:Person"))
    (is (string= (symbol-name converted3) "rdf:type"))
    ;; Symbol without @ should remain unchanged
    (is (eq (convert-symbol-cl-to-elisp 'alice) 'alice))))

(test convert-triple-cl-to-elisp
  "Test converting cl-rdf triple to el-rdf format"
  (let ((cl-triple '(alice foaf@name "Alice")))
    (let ((el-triple (convert-triple-cl-to-elisp cl-triple)))
      (is (eq (first el-triple) 'alice))
      (is (string= (symbol-name (second el-triple)) "foaf:name"))
      (is (equal (third el-triple) "Alice")))))

;;; Save for el-rdf Tests

(test save-for-elisp-basic
  "Test saving graph in el-rdf format"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-elisp-~A.rdf" (get-universal-time))))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@age 30)
                   (charlie rdf@type foaf@Person))
                 graph)

    (save-for-elisp graph tmpfile)

    ;; Read file and verify it uses : separator
    (let ((content (uiop:read-file-string tmpfile)))
      (is (search "foaf:name" content))
      (is (search "foaf:age" content))
      (is (search "rdf:type" content))
      ;; Should NOT have @ separator
      (is (not (search "foaf@name" content)))
      (is (not (search "foaf@age" content))))

    (delete-file tmpfile)))

(test roundtrip-cl-to-el-to-cl
  "Test round-trip conversion: cl-rdf → el-rdf → cl-rdf"
  (let ((graph1 (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-roundtrip-~A.rdf" (get-universal-time))))
    (add-triples '((alice foaf@name "Alice")
                   (bob foaf@knows alice)
                   (charlie schema@birthDate "1990-01-01"))
                 graph1)

    ;; Save in el-rdf format
    (save-for-elisp graph1 tmpfile)

    ;; Load back into new graph (auto-converts to cl-rdf)
    (let ((graph2 (make-graph)))
      (load-graph graph2 tmpfile)

      ;; Should have same triples with @ separator
      (let ((triples (triples '(t t t) graph2)))
        (is (= 3 (length triples)))
        (is (member '(alice foaf@name "Alice") triples :test #'equal))
        (is (member '(bob foaf@knows alice) triples :test #'equal))
        (is (member '(charlie schema@birthDate "1990-01-01") triples :test #'equal))))

    (delete-file tmpfile)))

(test save-for-elisp-with-complex-symbols
  "Test saving symbols with multiple @ separators"
  (let ((graph (make-graph))
        (tmpfile (format nil "/tmp/cl-rdf-complex-~A.rdf" (get-universal-time))))
    (add-triples '((wn30schema@seeAlso rdf@type owl@ObjectProperty)
                   (ex@item rdfs@label "Test Item"))
                 graph)

    (save-for-elisp graph tmpfile)

    (let ((content (uiop:read-file-string tmpfile)))
      ;; Should have colons
      (is (search "wn30schema:seeAlso" content))
      (is (search "rdf:type" content))
      (is (search "owl:ObjectProperty" content))
      (is (search "rdfs:label" content)))

    (delete-file tmpfile)))

(test convert-symbols-preserves-literals
  "Test that literal values are preserved during conversion"
  (let ((triple '(alice foaf@age 30)))
    (let ((converted (convert-triple-cl-to-elisp triple)))
      (is (equal (third converted) 30))
      (is (numberp (third converted))))))

;;; ============================================================================
;;; End of Test Suites
;;; ============================================================================

;;; ============================================================================
;;; HTTP Server and Remote Graph Tests
;;; ============================================================================

(in-suite :http)

(test graph-registry
  "Test graph registration for HTTP access"
  (let ((graph (make-graph)))
    ;; Register (tested implicitly by HTTP operations)
    (register-graph-for-http "test-graph" graph)

    ;; Unregister
    (is (unregister-graph-for-http "test-graph"))

    ;; Unregister non-existent
    (is (not (unregister-graph-for-http "test-graph")))))

(test remote-graph-creation
  "Test remote-graph instance creation"
  (let ((remote (make-remote-graph :url "http://localhost:8080"
                                   :graph-name "test"
                                   :token "secret"
                                   :timeout 30)))
    (is (not (null remote)))
    (is (string= "http://localhost:8080" (remote-graph-url remote)))
    (is (string= "test" (remote-graph-name remote)))
    (is (string= "secret" (remote-graph-token remote)))
    (is (= 30 (remote-graph-timeout remote)))))

;; NOTE: Integration tests below require actual HTTP server which may not work in CI
;; Uncomment for local testing

#|
(test server-lifecycle
  "Test server start/stop"
  ;; Stop any existing server
  (when cl-rdf::*server*
    (stop-server))

  ;; Start server
  (let ((server (start-server :port 18080 :token "test-token")))
    (is (not (null server)))
    (is (eq server cl-rdf::*server*))

    ;; Verify it's running
    (sleep 0.5)  ; Give server time to start

    ;; Stop server
    (is (stop-server))
    (is (null cl-rdf::*server*))

    ;; Stop when not running
    (is (not (stop-server)))))

(test remote-graph-triples
  "Test remote graph triples operation"
  ;; Setup: local graph with data
  (let ((local-graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@knows bob)
                   (bob foaf@name "Bob"))
                 local-graph)

    ;; Register and start server
    (register-graph-for-http "test" local-graph)
    (start-server :port 18081 :token "secret")

    (sleep 0.5)  ; Give server time to start

    (unwind-protect
        (progn
          ;; Create remote graph client
          (let ((remote (make-remote-graph :url "http://localhost:18081"
                                           :graph-name "test"
                                           :token "secret")))

            ;; Query via remote graph
            (let ((results (triples '(alice t t) remote)))
              (is (= 2 (length results)))
              (is (member '(alice foaf@name "Alice") results :test #'equal))
              (is (member '(alice foaf@knows bob) results :test #'equal)))

            ;; Query specific predicate
            (let ((results (triples '(t foaf@name t) remote)))
              (is (= 2 (length results))))))

      ;; Cleanup
      (stop-server)
      (unregister-graph-for-http "test"))))

(test remote-graph-add-delete
  "Test remote graph add and delete operations"
  (let ((local-graph (make-graph)))
    ;; Register and start server
    (register-graph-for-http "test" local-graph)
    (start-server :port 18082 :token "secret")

    (sleep 0.5)

    (unwind-protect
        (let ((remote (make-remote-graph :url "http://localhost:18082"
                                         :graph-name "test"
                                         :token "secret")))

          ;; Add via remote
          (add-triple '(alice foaf@name "Alice") remote)

          ;; Verify in local graph
          (is (= 1 (length (triples '(t t t) local-graph))))

          ;; Add multiple
          (add-triples '((bob foaf@name "Bob")
                        (charlie foaf@name "Charlie"))
                      remote)

          (is (= 3 (length (triples '(t t t) local-graph))))

          ;; Delete via remote
          (delete-triple '(alice foaf@name "Alice") remote)

          (is (= 2 (length (triples '(t t t) local-graph)))))

      ;; Cleanup
      (stop-server)
      (unregister-graph-for-http "test"))))

(test remote-graph-query
  "Test remote graph complex queries"
  (let ((local-graph (make-graph)))
    (add-triples '((alice foaf@name "Alice")
                   (alice foaf@age 30)
                   (bob foaf@name "Bob")
                   (bob foaf@age 25))
                 local-graph)

    ;; Register and start server
    (register-graph-for-http "test" local-graph)
    (start-server :port 18083 :token "secret")

    (sleep 0.5)

    (unwind-protect
        (let ((remote (make-remote-graph :url "http://localhost:18083"
                                         :graph-name "test"
                                         :token "secret")))

          ;; Execute query
          (let ((results (graph-query '((($s foaf@name $name))) remote)))
            (is (= 2 (length results)))
            ;; Check bindings structure
            (is (not (null (assoc '$s (first results)))))
            (is (not (null (assoc '$name (first results)))))))

      ;; Cleanup
      (stop-server)
      (unregister-graph-for-http "test"))))

(test remote-graph-authentication
  "Test bearer token authentication"
  (let ((local-graph (make-graph)))
    (add-triple '(alice foaf@name "Alice") local-graph)

    ;; Register and start server with token
    (register-graph-for-http "test" local-graph)
    (start-server :port 18084 :token "correct-token")

    (sleep 0.5)

    (unwind-protect
        (progn
          ;; Should work with correct token
          (let ((remote (make-remote-graph :url "http://localhost:18084"
                                           :graph-name "test"
                                           :token "correct-token")))
            (is (not (null (triples '(t t t) remote)))))

          ;; Should fail with wrong token
          (let ((remote (make-remote-graph :url "http://localhost:18084"
                                           :graph-name "test"
                                           :token "wrong-token")))
            (signals error (triples '(t t t) remote)))

          ;; Should fail with no token
          (let ((remote (make-remote-graph :url "http://localhost:18084"
                                           :graph-name "test"
                                           :token nil)))
            (signals error (triples '(t t t) remote))))

      ;; Cleanup
      (stop-server)
      (unregister-graph-for-http "test"))))

(test health-check-endpoint
  "Test health check endpoint"
  (start-server :port 18085)
  (sleep 0.5)

  (unwind-protect
        (let ((response (drakma:http-request "http://localhost:18085/health" :force-text t)))
        (is (search ":status" response)))

    ;; Cleanup
    (stop-server)))

;;; ============================================================================
;;; End of HTTP Tests
;;; ============================================================================
|#
