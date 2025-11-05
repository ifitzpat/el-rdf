;;;; package.lisp --- Package definition for cl-rdf

(defpackage #:cl-rdf
  (:use #:cl #:alexandria)
  (:import-from #:bordeaux-threads
                #:make-lock
                #:with-lock-held
                #:make-thread
                #:join-thread)
  (:import-from #:lparallel
                #:pmap
                #:premove-if
                #:*kernel*
                #:make-kernel
                #:end-kernel)
  (:import-from #:log4cl)
  (:import-from #:hunchentoot)
  (:import-from #:drakma)
  (:documentation "In-memory RDF triple store for Common Lisp")

  ;; Core graph classes and operations
  (:export #:graph              ; Abstract base class
           #:local-graph        ; Local in-memory graph
           #:make-graph
           #:graph-name
           #:graph-spo
           #:graph-osp
           #:graph-pos
           #:graph-add-hooks
           #:graph-delete-hooks
           #:graph-query-hooks
           #:graph-prefixes)

  ;; Triple operations
  (:export #:add-triple
           #:add-triples
           #:delete-triple
           #:delete-triples
           #:triples
           #:raw-triples)

  ;; Query operations
  (:export #:graph-query
           #:where
           #:ask
           #:select
           #:construct
           #:filter
           #:delete-data)

  ;; Predicates
  (:export #:variablep
           #:var-or-wildp
           #:optional-clause-p)

  ;; Utilities
  (:export #:bnode
           #:namespace
           #:rdf
           #:make-rdf-symbol)

  ;; Alist manipulation helpers (used internally by triple storage)
  (:export #:update-dual
           #:remove-dual)

  ;; Hook system
  (:export #:add-hook-to-graph
           #:remove-hook-from-graph
           #:get-graph-hooks)

  ;; Content references (Phase 8)
  (:export #:content-reference-p
           #:store-large-content
           #:resolve-content-reference
           #:process-triple-object
           #:resolve-triple-object
           #:resolve-triple-objects)

  ;; Persistence
  (:export #:save-graph
           #:load-graph
           #:triples-to-string)

  ;; Checkpointing
  (:export #:get-checkpoint-dir
           #:checkpoint-file-path
           #:register-graph-for-checkpointing
           #:checkpoint-hook
           #:save-named-graph
           #:restore-named-graph
           #:save-checkpoint-metadata
           #:load-checkpoint-metadata
           #:list-checkpoints
           #:delete-checkpoint)

  ;; TTL import (Phase 11)
  (:export #:import-ttl
           #:register-prefix
           #:expand-prefixed-iri
           #:intern-rdf-resource
           #:parse-ttl-value
           #:simple-tokenize-ttl
           #:parse-rdf-collection
           #:parse-blank-node-bracket
           #:parse-simple-ttl-statement
           #:parse-ttl-content)

  ;; Visualization (Phase 12)
  (:export #:namespace
           #:nodes
           #:literals
           #:render-triple
           #:filter-triples
           #:apply-node-styles
           #:render-triples
           #:render-graph
           #:render-graph-json)

  ;; Format conversion (el-rdf ↔ cl-rdf)
  ;; Phase 9: el-rdf → cl-rdf
  (:export #:el-rdf-symbol-p
           #:convert-symbol-el-to-cl
           #:convert-triple-el-to-cl
           ;; Phase 13: cl-rdf → el-rdf (bidirectional)
           #:convert-symbol-cl-to-elisp
           #:convert-triple-cl-to-elisp
           #:save-for-elisp)

  ;; HTTP Server & Remote Graph
  (:export #:start-server
           #:stop-server
           #:*server*
           #:remote-graph
           #:make-remote-graph
           #:remote-graph-url
           #:remote-graph-token
           #:register-graph-for-http
           #:unregister-graph-for-http))
