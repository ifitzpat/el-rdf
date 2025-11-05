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
               #:cl-ppcre          ; Regular expressions (format conversion)
               #:uiop)             ; Portable pathname/filesystem operations

  :components ((:file "package")
               (:file "cl-rdf" :depends-on ("package")))

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
