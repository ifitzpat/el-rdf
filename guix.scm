;;; guix.scm --- Guix package definition for cl-rdf

;;; This file can be used to test cl-rdf locally with Guix:
;;;
;;;   guix shell -D -f guix.scm          # Development environment
;;;   guix shell -f guix.scm -- sbcl     # SBCL with cl-rdf loaded
;;;   guix build -f guix.scm             # Build the package
;;;
;;; Inside the shell, you can:
;;;   sbcl
;;;   * (asdf:load-system :cl-rdf)
;;;   * (asdf:test-system :cl-rdf)

(define-module (cl-rdf)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix build-system asdf)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages lisp)
  #:use-module (gnu packages lisp-xyz))

(define vcs-file?
  ;; Return true if the given file is under version control.
  (or (git-predicate (current-source-directory))
      (const #t)))  ; not in a Git checkout

(define-public cl-rdf
  (package
    (name "cl-rdf")
    (version "0.3.0")
    (source
     (local-file "." "cl-rdf-checkout"
                 #:recursive? #t
                 #:select? vcs-file?))
    (build-system asdf-build-system/sbcl)
    (arguments
     (list
      #:asd-systems ''("cl-rdf" "cl-rdf/tests")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'fix-paths
            (lambda _
              ;; Ensure test files are found
              (substitute* "cl-rdf.asd"
                (("\\(\"tests\"") "(\"tests\"")))))
        ))
    (native-inputs
     (list sbcl-fiveam))  ; Testing framework
    (inputs
     (list sbcl-alexandria   ; Utilities library
           sbcl-ironclad))   ; For MD5 hashing (content references)
    ;; Note: uiop is included with ASDF/SBCL, no need to list it
    (home-page "https://github.com/ifitzpat/el-rdf")
    (synopsis "In-memory RDF triple store for Common Lisp")
    (description
     "cl-rdf is an in-memory RDF triple store for Common Lisp, ported from
the Emacs Lisp el-rdf library.  It provides SPARQL-like query operations,
TTL file import, and graph visualization capabilities.

Features:
@itemize
@item Triple-indexed storage (SPO, OSP, POS) for efficient querying
@item SPARQL-like query language with pattern matching
@item Support for SELECT, ASK, CONSTRUCT, FILTER, and OPTIONAL queries
@item Hook system for CRUD operations
@item Automatic checkpointing for named graphs
@item Content reference system for large strings
@item TTL (Turtle) import with full syntax support
@item Graph visualization via Graphviz
@end itemize

cl-rdf uses period separators for RDF resources (namespace.resource)
to avoid conflicts with Common Lisp package syntax and SPARQL 1.1
property path operators.")
    (license license:gpl3+)))

;; Return the package for use with 'guix shell -f guix.scm'
cl-rdf
