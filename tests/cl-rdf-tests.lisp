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

;; Tests will be added here as we implement Phase 1 functions
;; Following TDD: write test first, then implement function

;; Example structure for future tests:
;;
;; (test variablep
;;   "Test variable predicate - identifies symbols starting with $"
;;   (is (variablep '$subject))
;;   (is (variablep '$name))
;;   (is (not (variablep 'regular-symbol)))
;;   (is (not (variablep "string")))
;;   (is (not (variablep 42))))

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
