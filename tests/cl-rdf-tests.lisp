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

;;; ============================================================================
;;; Phase 3: Hook System
;;; ============================================================================

(in-suite :hooks)

;; Hook tests will be added here

;;; ============================================================================
;;; Phase 4-12: Additional test suites
;;; ============================================================================

;; Tests for remaining phases will be added as implementation progresses
;; See CL-PORT-PLAN.md for complete phase breakdown
