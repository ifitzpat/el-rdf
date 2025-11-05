;;;; cl-rdf.lisp --- In-memory RDF triple store for Common Lisp

;;; This is a port of el-rdf.el from Emacs Lisp to Common Lisp.
;;; See CL-PORT-PLAN.md for the implementation plan.

(in-package #:cl-rdf)

;;; Implementation will follow Test-Driven Development:
;;; 1. Write test first (in tests/cl-rdf-tests.lisp)
;;; 2. Run test (should fail)
;;; 3. Implement function
;;; 4. Run test (should pass)
;;; 5. Refactor if needed

;;; Functions will be implemented in phases according to CL-PORT-PLAN.md
;;; Phase 1: Core Data Structures and Utilities
;;; Phase 2: Triple Storage
;;; Phase 3: Hook System
;;; ... (see plan for complete phase list)

;;; Note: This file will grow as we port functions from el-rdf.el
