;;;; tests/test-package.lisp --- Test package definition

(defpackage #:cl-rdf-tests
  (:use #:cl #:cl-rdf #:fiveam)
  (:documentation "Test suite for cl-rdf"))

(in-package #:cl-rdf-tests)

;;; Define test suites

(def-suite :cl-rdf
    :description "Master test suite for cl-rdf")

(def-suite :core
    :in :cl-rdf
    :description "Core data structures and utilities")

(def-suite :storage
    :in :cl-rdf
    :description "Triple storage operations")

(def-suite :query
    :in :cl-rdf
    :description "Query execution")

(def-suite :hooks
    :in :cl-rdf
    :description "Hook system")

(def-suite :persistence
    :in :cl-rdf
    :description "Serialization and persistence")

(def-suite :ttl
    :in :cl-rdf
    :description "TTL import")

(def-suite :conversion
    :in :cl-rdf
    :description "Format conversion (el-rdf ↔ cl-rdf)")
