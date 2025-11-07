;;;; build-ecl-binary.lisp - Build standalone cl-rdf-server binary for ECL

;;; This script builds a standalone executable for cl-rdf HTTP server
;;; Usage: ecl -load build-ecl-binary.lisp

(require 'asdf)

;; Load Quicklisp if available
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
                                        (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; Load the system with all dependencies
(format t "~%Loading cl-rdf/http system...~%")
(asdf:load-system :cl-rdf/http)

(format t "~%Building standalone binary...~%")

;; Define entry point
(defun cl-rdf-server-main ()
  "Entry point for cl-rdf server binary"
  (let ((port 8080)
        (host "0.0.0.0"))
    ;; Parse command line arguments
    (let ((args (ext:command-args)))
      (loop for (flag value) on args by #'cddr
            do (cond
                 ((string= flag "--port")
                  (setf port (parse-integer value :junk-allowed t)))
                 ((string= flag "--host")
                  (setf host value))
                 ((or (string= flag "--help") (string= flag "-h"))
                  (format t "Usage: cl-rdf-server [OPTIONS]~%")
                  (format t "~%Options:~%")
                  (format t "  --port PORT    HTTP server port (default: 8080)~%")
                  (format t "  --host HOST    Bind address (default: 0.0.0.0)~%")
                  (format t "  --help, -h     Show this help message~%")
                  (ext:quit 0)))))

    (format t "~%Starting cl-rdf HTTP server on ~A:~A~%" host port)
    (format t "Press Ctrl+C to stop~%~%")

    ;; Start server (blocking)
    (handler-case
        (cl-rdf-http:start-server :port port :host host)
      (error (e)
        (format t "~%Error starting server: ~A~%" e)
        (ext:quit 1)))))

;; Build the executable
(asdf:make-build :cl-rdf/http
                 :type :program
                 :move-here #P"./"
                 :prologue-code '(require 'asdf)
                 :epilogue-code '(cl-rdf-server-main))

(format t "~%Build complete! Binary: ./cl-rdf-http~%")
(format t "Run with: ./cl-rdf-http --port 8080~%")

(ext:quit 0)
