;;;; http-server.lisp --- HTTP API for remote graph access

(in-package #:cl-rdf)

;;;; ============================================================================
;;;; Configuration
;;;; ============================================================================

(defvar *server* nil
  "The Hunchentoot acceptor instance.")

(defvar *graph-registry* (make-hash-table :test 'equal)
  "Registry mapping graph names to graph instances for HTTP access.")

(defvar *default-port* 8080
  "Default port for HTTP server.")

(defparameter *api-token* nil
  "Bearer token for API authentication. Set via CL_RDF_API_TOKEN env var.")

(defparameter *max-request-size* (* 10 1024 1024)
  "Maximum request body size (10MB default).")

;;;; ============================================================================
;;;; Utilities
;;;; ============================================================================

(defun get-api-token-from-env ()
  "Read API token from CL_RDF_API_TOKEN environment variable."
  (uiop:getenv "CL_RDF_API_TOKEN"))

(defun %read-sexp-safely (string)
  "Read S-expression from STRING with safety checks.

Arguments:
  string - String containing S-expression

Returns:
  Parsed Lisp data structure or NIL on error

Security:
  - Disables *READ-EVAL* to prevent code execution
  - Uses safe reader settings
  - Catches read errors"
  (handler-case
      (let ((*read-eval* nil)
            (*package* (find-package :cl-rdf)))
        (read-from-string string))
    (error (e)
      (log:error "Failed to read S-expression: ~A" e)
      nil)))

(defun %write-sexp-to-string (data)
  "Write DATA as S-expression string.

Arguments:
  data - Lisp data structure

Returns:
  String representation

Uses case-preserving output for symbol names."
  (let ((*print-case* :downcase)
        (*print-readably* t))
    (prin1-to-string data)))

(defun %get-auth-token ()
  "Extract bearer token from Authorization header.

Returns:
  Token string or NIL if not present

Expected format: Authorization: Bearer <token>"
  (let ((auth-header (hunchentoot:header-in* :authorization)))
    (when (and auth-header (string-prefix-p "Bearer " auth-header))
      (subseq auth-header 7))))

(defun string-prefix-p (prefix string)
  "Return T if STRING starts with PREFIX."
  (and (>= (length string) (length prefix))
       (string= prefix string :end2 (length prefix))))

;;;; ============================================================================
;;;; Authentication Middleware
;;;; ============================================================================

(defun require-authentication ()
  "Check bearer token authentication.

Returns:
  T if authenticated, NIL otherwise

Side Effects:
  Sets HTTP 401 response if authentication fails"
  (let ((required-token (or *api-token* (get-api-token-from-env))))
    (if (null required-token)
        ;; No token configured, allow all requests
        t
        ;; Token required, check it
        (let ((provided-token (%get-auth-token)))
          (if (and provided-token (string= required-token provided-token))
              t
              (progn
                (setf (hunchentoot:return-code*) hunchentoot:+http-unauthorized+)
                (setf (hunchentoot:content-type*) "application/sexp")
                nil))))))

;;;; ============================================================================
;;;; Request/Response Handling
;;;; ============================================================================

(defun %parse-request-body ()
  "Parse request body as S-expression.

Returns:
  Parsed data structure or NIL on error

Side Effects:
  Sets HTTP 400 response if parsing fails"
  (let* ((content-length (hunchentoot:content-length*))
         (body (when (and content-length (<= content-length *max-request-size*))
                 (hunchentoot:raw-post-data :force-text t))))
    (if body
        (or (%read-sexp-safely body)
            (progn
              (setf (hunchentoot:return-code*) hunchentoot:+http-bad-request+)
              nil))
        (progn
          (setf (hunchentoot:return-code*) hunchentoot:+http-bad-request+)
          nil))))

(defun %send-sexp-response (data)
  "Send DATA as S-expression response.

Arguments:
  data - Lisp data structure to send

Side Effects:
  Sets content-type to application/sexp
  Returns serialized S-expression string"
  (setf (hunchentoot:content-type*) "application/sexp")
  (%write-sexp-to-string data))

(defun %send-error (message &optional (code hunchentoot:+http-internal-server-error+))
  "Send error response.

Arguments:
  message - Error message string
  code - HTTP status code (default 500)

Returns:
  S-expression error response"
  (setf (hunchentoot:return-code*) code)
  (%send-sexp-response `(:error ,message)))

(defun %send-success (data)
  "Send success response.

Arguments:
  data - Response data

Returns:
  S-expression success response"
  (%send-sexp-response `(:ok ,data)))

;;;; ============================================================================
;;;; Graph Registry
;;;; ============================================================================

(defun register-graph-for-http (name graph)
  "Register GRAPH with NAME for HTTP access.

Arguments:
  name - String name for the graph
  graph - Graph instance (local-graph or remote-graph)

Side Effects:
  Updates *graph-registry*"
  (setf (gethash name *graph-registry*) graph))

(defun unregister-graph-for-http (name)
  "Remove graph with NAME from HTTP registry.

Arguments:
  name - String name of graph to unregister

Returns:
  T if graph was removed, NIL if not found"
  (remhash name *graph-registry*))

(defun %get-graph-from-registry (name)
  "Retrieve graph by NAME from registry.

Arguments:
  name - String name of graph

Returns:
  Graph instance or NIL if not found"
  (gethash name *graph-registry*))

;;;; ============================================================================
;;;; HTTP Endpoints
;;;; ============================================================================

(hunchentoot:define-easy-handler (health-check :uri "/health") ()
  "Health check endpoint for container readiness probes."
  (setf (hunchentoot:content-type*) "application/sexp")
  "(:status :ok)")

(hunchentoot:define-easy-handler (api-triples :uri "/triples") ()
  "Retrieve triples matching a pattern.

Request body (S-exp):
  (:graph \"graph-name\" :pattern (subject predicate object))

Response (S-exp):
  (:ok (triple1 triple2 ...))

Example:
  POST /triples
  (:graph \"my-graph\" :pattern (alice t t))"
  (unless (require-authentication)
    (return-from api-triples (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let ((request (%parse-request-body)))
    (unless request
      (return-from api-triples (%send-error "Invalid request body" hunchentoot:+http-bad-request+)))

    (let* ((graph-name (getf request :graph))
           (pattern (getf request :pattern))
           (graph (%get-graph-from-registry graph-name)))

      (cond
        ((null graph-name)
         (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
        ((null pattern)
         (%send-error "Missing :pattern parameter" hunchentoot:+http-bad-request+))
        ((null graph)
         (%send-error (format nil "Graph '~A' not found" graph-name) hunchentoot:+http-not-found+))
        (t
         (handler-case
             (%send-success (triples pattern graph))
           (error (e)
             (%send-error (format nil "Query failed: ~A" e)))))))))

(hunchentoot:define-easy-handler (api-add :uri "/add") ()
  "Add triples to a graph.

Request body (S-exp):
  (:graph \"graph-name\" :triples ((s p o) (s2 p2 o2) ...))

Response (S-exp):
  (:ok :added <count>)

Example:
  POST /add
  (:graph \"my-graph\" :triples ((alice foaf@name \"Alice\")))"
  (unless (require-authentication)
    (return-from api-add (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let ((request (%parse-request-body)))
    (unless request
      (return-from api-add (%send-error "Invalid request body" hunchentoot:+http-bad-request+)))

    (let* ((graph-name (getf request :graph))
           (triples-data (getf request :triples))
           (graph (%get-graph-from-registry graph-name)))

      (cond
        ((null graph-name)
         (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
        ((null triples-data)
         (%send-error "Missing :triples parameter" hunchentoot:+http-bad-request+))
        ((null graph)
         (%send-error (format nil "Graph '~A' not found" graph-name) hunchentoot:+http-not-found+))
        (t
         (handler-case
             (progn
               (add-triples triples-data graph)
               (%send-success `(:added ,(length triples-data))))
           (error (e)
             (%send-error (format nil "Add failed: ~A" e)))))))))

(hunchentoot:define-easy-handler (api-delete :uri "/delete") ()
  "Delete triples from a graph.

Request body (S-exp):
  (:graph \"graph-name\" :triples ((s p o) (s2 p2 o2) ...))

Response (S-exp):
  (:ok :deleted <count>)

Example:
  POST /delete
  (:graph \"my-graph\" :triples ((alice foaf@name \"Alice\")))"
  (unless (require-authentication)
    (return-from api-delete (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let ((request (%parse-request-body)))
    (unless request
      (return-from api-delete (%send-error "Invalid request body" hunchentoot:+http-bad-request+)))

    (let* ((graph-name (getf request :graph))
           (triples-data (getf request :triples))
           (graph (%get-graph-from-registry graph-name)))

      (cond
        ((null graph-name)
         (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
        ((null triples-data)
         (%send-error "Missing :triples parameter" hunchentoot:+http-bad-request+))
        ((null graph)
         (%send-error (format nil "Graph '~A' not found" graph-name) hunchentoot:+http-not-found+))
        (t
         (handler-case
             (progn
               (delete-triples triples-data graph)
               (%send-success `(:deleted ,(length triples-data))))
           (error (e)
             (%send-error (format nil "Delete failed: ~A" e)))))))))

(hunchentoot:define-easy-handler (api-query :uri "/query") ()
  "Execute SPARQL-like query on a graph.

Request body (S-exp):
  (:graph \"graph-name\" :clauses ((pattern1) (pattern2) ...))

Response (S-exp):
  (:ok ((($var1 . val1) ($var2 . val2)) ...))

Example:
  POST /query
  (:graph \"my-graph\" :clauses (((\"$s\" foaf@name \"$name\"))))"
  (unless (require-authentication)
    (return-from api-query (%send-error "Unauthorized" hunchentoot:+http-unauthorized+)))

  (let ((request (%parse-request-body)))
    (unless request
      (return-from api-query (%send-error "Invalid request body" hunchentoot:+http-bad-request+)))

    (let* ((graph-name (getf request :graph))
           (clauses (getf request :clauses))
           (graph (%get-graph-from-registry graph-name)))

      (cond
        ((null graph-name)
         (%send-error "Missing :graph parameter" hunchentoot:+http-bad-request+))
        ((null clauses)
         (%send-error "Missing :clauses parameter" hunchentoot:+http-bad-request+))
        ((null graph)
         (%send-error (format nil "Graph '~A' not found" graph-name) hunchentoot:+http-not-found+))
        (t
         (handler-case
             (%send-success (graph-query clauses graph))
           (error (e)
             (%send-error (format nil "Query failed: ~A" e)))))))))

;;;; ============================================================================
;;;; Server Control
;;;; ============================================================================

(defun start-server (&key (port *default-port*) (token nil))
  "Start HTTP server for remote graph access.

Arguments:
  port - Port number (default 8080)
  token - Bearer token for authentication (default: from CL_RDF_API_TOKEN env)

Returns:
  Hunchentoot acceptor instance

Side Effects:
  Starts HTTP server
  Sets *server* global variable
  Sets *api-token* if provided

Example:
  (start-server :port 8080 :token \"secret-token-here\")

Environment:
  CL_RDF_API_TOKEN - Bearer token if not provided as argument"
  (when *server*
    (log:warn "Server already running on port ~A" (hunchentoot:acceptor-port *server*))
    (return-from start-server *server*))

  (when token
    (setf *api-token* token))

  (setf *server* (make-instance 'hunchentoot:easy-acceptor
                                :port port
                                :access-log-destination nil
                                :message-log-destination *standard-output*))

  (hunchentoot:start *server*)

  (log:info "cl-rdf HTTP server started on port ~A" port)
  (if (or *api-token* (get-api-token-from-env))
      (log:info "Authentication: Bearer token required")
      (log:warn "Authentication: DISABLED (no token configured)"))

  *server*)

(defun stop-server ()
  "Stop the HTTP server.

Returns:
  T if server was stopped, NIL if no server running

Side Effects:
  Stops HTTP server
  Clears *server* global variable"
  (if *server*
      (progn
        (hunchentoot:stop *server*)
        (setf *server* nil)
        (log:info "cl-rdf HTTP server stopped")
        t)
      (progn
        (log:warn "No server running")
        nil)))

;;;; ============================================================================
;;;; Remote Graph Client
;;;; ============================================================================

(defclass remote-graph (graph)
  ((url :initarg :url
        :accessor remote-graph-url
        :documentation "Base URL of remote cl-rdf HTTP server")
   (token :initarg :token
          :initform nil
          :accessor remote-graph-token
          :documentation "Bearer token for authentication")
   (timeout :initarg :timeout
            :initform 60
            :accessor remote-graph-timeout
            :documentation "Request timeout in seconds")
   (graph-name :initarg :graph-name
               :accessor remote-graph-name
               :documentation "Name of graph on remote server"))
  (:documentation "Remote graph accessed via HTTP API.

Implements the graph protocol by making HTTP requests to a remote cl-rdf server.

Example:
  (defvar *remote* (make-remote-graph :url \"http://localhost:8080\"
                                       :graph-name \"my-graph\"
                                       :token \"secret\"))
  (triples '(alice t t) *remote*)"))

(defun make-remote-graph (&key url graph-name token (timeout 60))
  "Create a remote graph client.

Arguments:
  url - Base URL of remote server (e.g., \"http://localhost:8080\")
  graph-name - Name of graph on remote server
  token - Bearer token for authentication (optional)
  timeout - Request timeout in seconds (default 60)

Returns:
  remote-graph instance

Example:
  (make-remote-graph :url \"http://localhost:8080\"
                     :graph-name \"knowledge-base\"
                     :token \"my-secret-token\")"
  (make-instance 'remote-graph
                 :url url
                 :graph-name graph-name
                 :token token
                 :timeout timeout))

(defun %remote-request (graph endpoint request-data)
  "Make HTTP request to remote graph server.

Arguments:
  graph - remote-graph instance
  endpoint - API endpoint (e.g., \"/triples\")
  request-data - Request body as Lisp data structure

Returns:
  Response data or signals error

Side Effects:
  Makes HTTP POST request to remote server"
  (let* ((url (format nil "~A~A" (remote-graph-url graph) endpoint))
         (body (%write-sexp-to-string request-data))
         (headers (if (remote-graph-token graph)
                      `(("Authorization" . ,(format nil "Bearer ~A" (remote-graph-token graph))))
                      nil)))

    (multiple-value-bind (response status-code)
        (drakma:http-request url
                             :method :post
                             :content body
                             :content-type "application/sexp"
                             :additional-headers headers
                             :connection-timeout (remote-graph-timeout graph)
                             :want-stream nil
                             :force-text t)

      (let ((response-data (%read-sexp-safely response)))

        (cond
          ((= status-code 200)
           (if (eq (first response-data) :ok)
               (second response-data)
               (error "Remote error: ~A" (second response-data))))
          ((= status-code 401)
           (error "Authentication failed: Invalid or missing token"))
          ((= status-code 404)
           (error "Graph not found on remote server"))
          (t
           (error "HTTP error ~A: ~A" status-code response-data)))))))

;;;; ============================================================================
;;;; Remote Graph Protocol Implementation
;;;; ============================================================================

(defmethod triples (pattern (graph remote-graph))
  "Retrieve triples from remote graph matching PATTERN.

Arguments:
  pattern - Triple pattern (subject predicate object)
  graph - remote-graph instance

Returns:
  List of triples

Side Effects:
  Makes HTTP request to remote server"
  (%remote-request graph "/triples"
                   `(:graph ,(remote-graph-name graph)
                     :pattern ,pattern)))

(defmethod add-triple (triple (graph remote-graph))
  "Add single triple to remote graph.

Arguments:
  triple - Triple to add (subject predicate object)
  graph - remote-graph instance

Returns:
  Response from server

Side Effects:
  Makes HTTP request to remote server"
  (%remote-request graph "/add"
                   `(:graph ,(remote-graph-name graph)
                     :triples (,triple))))

(defmethod add-triples (triples-list (graph remote-graph))
  "Add multiple triples to remote graph.

Arguments:
  triples-list - List of triples to add
  graph - remote-graph instance

Returns:
  Response from server

Side Effects:
  Makes HTTP request to remote server"
  (%remote-request graph "/add"
                   `(:graph ,(remote-graph-name graph)
                     :triples ,triples-list)))

(defmethod delete-triple (triple (graph remote-graph))
  "Delete single triple from remote graph.

Arguments:
  triple - Triple to delete (subject predicate object)
  graph - remote-graph instance

Returns:
  Response from server

Side Effects:
  Makes HTTP request to remote server"
  (%remote-request graph "/delete"
                   `(:graph ,(remote-graph-name graph)
                     :triples (,triple))))

(defmethod delete-triples (triples-list (graph remote-graph))
  "Delete multiple triples from remote graph.

Arguments:
  triples-list - List of triples to delete
  graph - remote-graph instance

Returns:
  Response from server

Side Effects:
  Makes HTTP request to remote server"
  (%remote-request graph "/delete"
                   `(:graph ,(remote-graph-name graph)
                     :triples ,triples-list)))

(defmethod graph-query (clauses (graph remote-graph))
  "Execute SPARQL-like query on remote graph.

Arguments:
  clauses - List of query clauses
  graph - remote-graph instance

Returns:
  Query results (list of binding alists)

Side Effects:
  Makes HTTP request to remote server"
  (%remote-request graph "/query"
                   `(:graph ,(remote-graph-name graph)
                     :clauses ,clauses)))
