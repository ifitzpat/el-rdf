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

  ;; Persistence
  (:export #:save-graph
           #:load-graph)

  ;; Checkpointing
  (:export #:register-graph-for-checkpointing
           #:save-named-graph
           #:restore-named-graph
           #:list-checkpoints
           #:delete-checkpoint)

  ;; TTL import
  (:export #:import-ttl)

  ;; Visualization
  (:export #:render-graph
           #:render-graph-json
           #:render-triples)

  ;; Format conversion (el-rdf ↔ cl-rdf)
  (:export #:convert-symbol-elisp-to-cl
           #:convert-symbol-cl-to-elisp
           #:load-elisp-graph
           #:save-for-elisp))
