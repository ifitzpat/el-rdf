;;;; cl-rdf.asd --- ASDF system definition for cl-rdf

(asdf:defsystem #:cl-rdf
  :description "In-memory RDF triple store for Common Lisp"
  :author "Ian FitzPatrick <ian@ianfitzpatrick.eu>"
  :license "GPLv3"
  :version "0.3.0"
  :homepage "https://github.com/ifitzpat/el-rdf"
  :bug-tracker "https://github.com/ifitzpat/el-rdf/issues"
  :source-control (:git "https://github.com/ifitzpat/el-rdf.git")

  :depends-on (#:alexandria
               #:bordeaux-threads  ; For threading/parallelization
               #:lparallel         ; For parallel map/reduce operations
               #:ironclad          ; For MD5 hashing (content references)
               #:log4cl            ; Logging framework
               #:cl-ppcre          ; Regular expressions (TTL import)
               #:uiop)             ; Portable pathname/filesystem operations

  :components ((:file "package")
               (:file "cl-rdf" :depends-on ("package")))

  :in-order-to ((test-op (test-op #:cl-rdf/tests))))


;;; ============================================================================
;;; HTTP Server (Optional)
;;; ============================================================================
;;;
;;; This system provides HTTP server and remote graph functionality.
;;; It is separate from the core system to avoid mandatory dependencies
;;; on hunchentoot and drakma.
;;;
;;; Usage:
;;;   (ql:quickload :cl-rdf/http)  ; Loads :cl-rdf plus HTTP features
;;;
;;; Features:
;;;   - HTTP API with Hunchentoot
;;;   - Bearer token authentication
;;;   - S-expression protocol (application/sexp)
;;;   - remote-graph class for accessing graphs over HTTP
;;;
;;; Example:
;;;   ;; Server side
;;;   (cl-rdf:register-graph-for-http "my-graph" graph)
;;;   (cl-rdf:start-server :port 8080 :token "secret")
;;;
;;;   ;; Client side
;;;   (defvar *remote* (cl-rdf:make-remote-graph
;;;                      :url "http://localhost:8080"
;;;                      :graph-name "my-graph"
;;;                      :token "secret"))
;;;   (cl-rdf:triples '(alice t t) *remote*)

(asdf:defsystem #:cl-rdf/http
  :description "HTTP server and remote graph for cl-rdf"
  :author "Ian FitzPatrick <ian@ianfitzpatrick.eu>"
  :license "GPLv3"
  :version "0.3.0"

  :depends-on (#:cl-rdf
               #:hunchentoot       ; HTTP server
               #:drakma)           ; HTTP client

  :components ((:file "http-server"))

  :in-order-to ((test-op (test-op #:cl-rdf/tests))))


;;; ============================================================================
;;; Optimized Production Build
;;; ============================================================================
;;;
;;; This system provides an optimized build of cl-rdf for production use.
;;; It uses the same source code but compiles with aggressive optimization
;;; settings for maximum performance.
;;;
;;; Usage:
;;;   ;; Development (default - better error messages, debugging)
;;;   (ql:quickload :cl-rdf)
;;;
;;;   ;; Production (optimized - maximum performance)
;;;   (ql:quickload :cl-rdf/optimized)
;;;
;;; Optimization settings:
;;;   speed 3  - Maximum speed optimization
;;;   safety 1 - Minimal safety checks (assumes correct usage)
;;;   debug 1  - Minimal debug info
;;;   space 0  - Don't optimize for space
;;;
;;; Note: The optimized build uses inline functions and type declarations
;;; that are already present in the source code. This system only changes
;;; the compiler optimization settings.

(asdf:defsystem #:cl-rdf/optimized
  :description "Optimized production build of cl-rdf (speed 3, safety 1)"
  :author "Ian FitzPatrick <ian@ianfitzpatrick.eu>"
  :license "GPLv3"
  :version "0.3.0"
  :homepage "https://github.com/ifitzpat/el-rdf"
  :bug-tracker "https://github.com/ifitzpat/el-rdf/issues"
  :source-control (:git "https://github.com/ifitzpat/el-rdf.git")

  :depends-on (#:alexandria
               #:bordeaux-threads
               #:lparallel
               #:ironclad
               #:log4cl
               #:cl-ppcre
               #:uiop)

  ;; Use same source code as main system
  :components ((:file "package")
               (:file "cl-rdf" :depends-on ("package")))

  ;; Apply aggressive optimization settings during compilation
  :around-compile (lambda (next)
                    (proclaim '(optimize (speed 3) (safety 1) (debug 1) (space 0)))
                    (funcall next))

  :in-order-to ((test-op (test-op #:cl-rdf/tests))))


(asdf:defsystem #:cl-rdf/tests
  :description "Test suite for cl-rdf"
  :author "Ian FitzPatrick <ian@ianfitzpatrick.eu>"
  :license "GPLv3"

  :depends-on (#:cl-rdf
               #:fiveam)

  :components ((:module "tests"
                :components ((:file "test-package")
                             (:file "cl-rdf-tests" :depends-on ("test-package")))))

  :perform (test-op (o c)
             (symbol-call :fiveam '#:run! :cl-rdf)))
