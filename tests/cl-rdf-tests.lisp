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

;; Storage tests will be added here

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
