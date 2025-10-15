(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(require 'ert)
(load-file "el-rdf.el")
(require 'el-rdf)

(ert-deftest test-ask-query()
  (let ((test-graph (make-graph)))
    (add-triples '((alice friend bob)
		   (bob friend alice)
		   (bob friend charlie)
		   (alice friend charlie)) test-graph)
    (should
     (ask '((alice friend bob)) test-graph))))

(ert-deftest test-select-query ()
  "Test the select function with mutual friendship query"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((alice friend bob)
		   (bob friend alice)
		   (bob friend charlie)
		   (alice friend charlie)) test-graph))
	 (result (select '($x $y) (graph-query '(($x friend $y)($y friend $x)) test-graph))))
    (should
     (-any
      (lambda (x)
	(and
	 (member 'alice x)
	 (member 'bob x)))
      result))))

(ert-deftest test-select-multiple-bindings-query ()
  "Test the select function with multiple bindings of $b"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((alice a foaf:Person)
		   (alice friend bob)
		   (alice friend charlie)
		   (alice address "10 Downing Street")) test-graph))
	 (result (select '($b) (graph-query '(($a a foaf:Person)($a friend $b)($a address $add)) test-graph))))
    (should
	(and
	 (member (list 'charlie) result)
	 (member (list 'bob) result))
      )))

;; Hook test helpers
(defvar test-hook-calls nil "Track hook calls for testing")

(defun test-add-hook (graph operation data)
  "Test hook that records add operations"
  (push (list :add operation (length data)) test-hook-calls))

(defun test-delete-hook (graph operation data)
  "Test hook that records delete operations"
  (push (list :delete operation (length data)) test-hook-calls))

(defun test-query-hook (graph operation data)
  "Test hook that records query operations"
  (push (list :query operation (length data)) test-hook-calls))

(ert-deftest test-hook-management ()
  "Test adding and removing hooks from graphs"
  (let ((test-graph (make-graph)))
    ;; Initially no hooks
    (should (null (get-graph-hooks test-graph 'add-hooks)))
    (should (null (get-graph-hooks test-graph 'delete-hooks)))
    (should (null (get-graph-hooks test-graph 'query-hooks)))
    
    ;; Add hooks
    (add-hook-to-graph test-graph 'add-hooks #'test-add-hook)
    (add-hook-to-graph test-graph 'delete-hooks #'test-delete-hook)
    (add-hook-to-graph test-graph 'query-hooks #'test-query-hook)
    
    ;; Verify hooks were added
    (should (member #'test-add-hook (get-graph-hooks test-graph 'add-hooks)))
    (should (member #'test-delete-hook (get-graph-hooks test-graph 'delete-hooks)))
    (should (member #'test-query-hook (get-graph-hooks test-graph 'query-hooks)))
    
    ;; Remove hooks
    (remove-hook-from-graph test-graph 'add-hooks #'test-add-hook)
    (remove-hook-from-graph test-graph 'delete-hooks #'test-delete-hook)
    (remove-hook-from-graph test-graph 'query-hooks #'test-query-hook)
    
    ;; Verify hooks were removed
    (should (null (get-graph-hooks test-graph 'add-hooks)))
    (should (null (get-graph-hooks test-graph 'delete-hooks)))
    (should (null (get-graph-hooks test-graph 'query-hooks)))))

(ert-deftest test-add-hooks-execution ()
  "Test that add-hooks are called during add-triples operations"
  (setq test-hook-calls nil)
  (let ((test-graph (make-graph)))
    ;; Add hook
    (add-hook-to-graph test-graph 'add-hooks #'test-add-hook)
    
    ;; Perform add-triples operation
    (add-triples '((alice friend bob) (bob friend charlie)) test-graph)
    
    ;; Verify hook was called
    (should (equal test-hook-calls '((:add add-triples 2))))
    
    ;; Add more triples
    (setq test-hook-calls nil)
    (add-triples '((charlie friend alice)) test-graph)
    
    ;; Verify hook was called again
    (should (equal test-hook-calls '((:add add-triples 1))))))

(ert-deftest test-delete-hooks-execution ()
  "Test that delete-hooks are called during delete-triples operations"
  (setq test-hook-calls nil)
  (let ((test-graph (make-graph)))
    ;; Add some data first
    (add-triples '((alice friend bob) (bob friend charlie)) test-graph)
    
    ;; Add hook
    (add-hook-to-graph test-graph 'delete-hooks #'test-delete-hook)
    
    ;; Perform delete-triples operation
    (delete-triples '((alice friend bob)) test-graph)
    
    ;; Verify hook was called
    (should (equal test-hook-calls '((:delete delete-triples 1))))))

(ert-deftest test-query-hooks-execution ()
  "Test that query-hooks are called during graph-query operations"
  (setq test-hook-calls nil)
  (let ((test-graph (make-graph)))
    ;; Add some data
    (add-triples '((alice friend bob) (bob friend charlie)) test-graph)
    
    ;; Add hook
    (add-hook-to-graph test-graph 'query-hooks #'test-query-hook)
    
    ;; Perform query operation
    (graph-query '(($x friend $y)) test-graph)
    
    ;; Verify hook was called
    (should (equal test-hook-calls '((:query graph-query 1))))))

(ert-deftest test-multiple-hooks-same-type ()
  "Test that multiple hooks of the same type are all executed"
  (setq test-hook-calls nil)
  (let ((test-graph (make-graph))
        (hook2-calls nil))
    ;; Define second hook that uses local variable
    (let ((local-hook2-calls hook2-calls))
      (fset 'test-add-hook2 
            (lambda (graph operation data)
              (setq local-hook2-calls (cons (list :add2 operation (length data)) local-hook2-calls))))
      
      ;; Add both hooks
      (add-hook-to-graph test-graph 'add-hooks #'test-add-hook)
      (add-hook-to-graph test-graph 'add-hooks #'test-add-hook2)
      
      ;; Perform operation
      (add-triples '((alice friend bob)) test-graph)
      
      ;; Verify both hooks were called
      (should (equal test-hook-calls '((:add add-triples 1))))
      (should (equal local-hook2-calls '((:add2 add-triples 1))))
      
      ;; Clean up the global function
      (fmakunbound 'test-add-hook2))))

(ert-deftest test-hooks-do-not-affect-individual-operations ()
  "Test that individual add-triple and delete-triple do not call hooks"
  (setq test-hook-calls nil)
  (let ((test-graph (make-graph)))
    ;; Add hooks
    (add-hook-to-graph test-graph 'add-hooks #'test-add-hook)
    (add-hook-to-graph test-graph 'delete-hooks #'test-delete-hook)
    
    ;; Perform individual operations
    (add-triple '(alice friend bob) test-graph)
    (delete-triple '(alice friend bob) test-graph)
    
    ;; Verify hooks were NOT called
    (should (null test-hook-calls))))

(ert-deftest test-hook-prevents-duplicates ()
  "Test that adding the same hook twice doesn't create duplicates"
  (let ((test-graph (make-graph)))
    ;; Add same hook twice
    (add-hook-to-graph test-graph 'add-hooks #'test-add-hook)
    (add-hook-to-graph test-graph 'add-hooks #'test-add-hook)
    
    ;; Should only appear once
    (should (= 1 (length (get-graph-hooks test-graph 'add-hooks))))
    (should (member #'test-add-hook (get-graph-hooks test-graph 'add-hooks)))))

;; Checkpointing tests
(defvar test-checkpoint-dir "/tmp/test-el-rdf-checkpoints"
  "Test directory for checkpoints.")

(defun test-cleanup-checkpoints ()
  "Clean up test checkpoint files."
  (when (file-exists-p test-checkpoint-dir)
    (delete-directory test-checkpoint-dir t)))

(ert-deftest test-checkpoint-directory ()
  "Test XDG cache directory creation and usage."
  (let ((el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    ;; Directory should be created when first accessed
    (should-not (file-exists-p test-checkpoint-dir))
    (let ((dir (el-rdf--get-checkpoint-dir)))
      (should (string= dir test-checkpoint-dir))
      (should (file-exists-p test-checkpoint-dir)))
    
    ;; Clean up
    (test-cleanup-checkpoints)))

(ert-deftest test-checkpoint-registration ()
  "Test graph registration for checkpointing."
  (let ((test-graph (make-graph))
        (el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    ;; Register graph for checkpointing
    (el-rdf-register-graph-for-checkpointing test-graph "test-graph")
    
    ;; Check that graph is registered
    (should (gethash test-graph el-rdf-graph-checkpoints))
    (should (string= "test-graph" (car (gethash test-graph el-rdf-graph-checkpoints))))
    
    ;; Check that checkpoint hook was added
    (should (member #'el-rdf-checkpoint-hook (get-graph-hooks test-graph 'add-hooks)))
    
    ;; Clean up
    (test-cleanup-checkpoints)
    (remhash test-graph el-rdf-graph-checkpoints)))

(ert-deftest test-automatic-checkpointing ()
  "Test that graphs are automatically checkpointed on add-triples."
  (let ((test-graph (make-graph))
        (el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    ;; Register graph for checkpointing
    (el-rdf-register-graph-for-checkpointing test-graph "test-auto-checkpoint")
    
    ;; Add triples (should trigger checkpoint)
    (add-triples '((alice friend bob) (bob friend charlie)) test-graph)
    
    ;; Check that checkpoint file was created
    (should (file-exists-p (el-rdf-checkpoint-file-path "test-auto-checkpoint")))
    
    ;; Clean up
    (test-cleanup-checkpoints)
    (remhash test-graph el-rdf-graph-checkpoints)))

(ert-deftest test-checkpoint-recovery ()
  "Test recovering graphs from checkpoints."
  (let ((test-graph (make-graph))
        (el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    ;; Create and checkpoint a graph with data
    (add-triples '((alice friend bob) (bob friend charlie) (alice age 30)) test-graph)
    (el-rdf-register-graph-for-checkpointing test-graph "test-recovery")
    (add-triples '((charlie friend alice)) test-graph) ; This triggers checkpoint
    
    ;; Recover the graph
    (let ((recovered-graph (el-rdf-recover-from-checkpoint "test-recovery")))
      ;; Check that all data was recovered
      (should (= 4 (length (triples '(t t t) recovered-graph))))
      ;; Check that each expected triple exists
      (let ((recovered-triples (triples '(t t t) recovered-graph)))
        (should (member '(alice friend bob) recovered-triples))
        (should (member '(bob friend charlie) recovered-triples))
        (should (member '(alice age 30) recovered-triples))
        (should (member '(charlie friend alice) recovered-triples))))
    
    ;; Clean up
    (test-cleanup-checkpoints)
    (remhash test-graph el-rdf-graph-checkpoints)))

(ert-deftest test-checkpoint-file-path ()
  "Test checkpoint file path generation."
  (let ((el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    (let ((path (el-rdf-checkpoint-file-path "my-graph")))
      (should (string-suffix-p "/my-graph.checkpoint" path))
      (should (string-prefix-p test-checkpoint-dir path)))
    
    (test-cleanup-checkpoints)))

(ert-deftest test-list-checkpoints ()
  "Test listing available checkpoint files."
  (let ((el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    ;; Initially no checkpoints
    (should (null (el-rdf-list-checkpoints)))
    
    ;; Create some test graphs and checkpoints
    (let ((graph1 (make-graph))
          (graph2 (make-graph)))
      (add-triples '((alice friend bob)) graph1)
      (add-triples '((charlie friend dave)) graph2)
      
      (el-rdf-register-graph-for-checkpointing graph1 "graph-one")
      (el-rdf-register-graph-for-checkpointing graph2 "graph-two")
      
      ;; Trigger checkpoints
      (add-triples '((bob friend charlie)) graph1)
      (add-triples '((dave friend alice)) graph2)
      
      ;; List checkpoints
      (let ((checkpoints (el-rdf-list-checkpoints)))
        (should (= 2 (length checkpoints)))
        (should (member "graph-one.checkpoint" checkpoints))
        (should (member "graph-two.checkpoint" checkpoints)))
      
      ;; Clean up
      (remhash graph1 el-rdf-graph-checkpoints)
      (remhash graph2 el-rdf-graph-checkpoints))
    
    (test-cleanup-checkpoints)))

(ert-deftest test-checkpoint-no-hooks-without-registration ()
  "Test that graphs without checkpoint registration don't get checkpointed."
  (let ((test-graph (make-graph))
        (el-rdf-checkpoint-dir test-checkpoint-dir))
    (test-cleanup-checkpoints)
    
    ;; Add triples without registering for checkpointing
    (add-triples '((alice friend bob) (bob friend charlie)) test-graph)
    
    ;; No checkpoint should be created
    (should (null (el-rdf-list-checkpoints)))
    
    (test-cleanup-checkpoints)))

(ert-deftest test-filter ()
  "Test the filter function with multiple bindings of $b"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((alice a foaf:Person)
		   (alice friend bob)
		   (alice friend charlie)
		   (alice address "10 Downing Street")) test-graph))
	 (query-result (graph-query '(($a a foaf:Person)($a friend $b)($a address $add)) test-graph))
	 (filtered-result (filter (lambda () (eq $b 'bob)) query-result))
	 (result (select '($b) filtered-result)))
    (should
	(and
	 (not (member (list 'charlie) result) )
	 (member (list 'bob) result))
      )))

(ert-deftest test-construct ()
  "Test the construct function with multiple bindings"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((alice a foaf:Person)
		   (alice friend bob)
		   (alice friend charlie)
		   (alice address "10 Downing Street")) test-graph))
	 (query-result (graph-query '(($a a foaf:Person)($a friend $b)($a address $add)) test-graph))
	 (result (construct '(($a knows $b)) query-result)))
    (should
	(and
	 (member '(alice knows bob) result)
	 (member '(alice knows charlie) result)
	 (= 2 (length result))))))

(ert-deftest test-optional-basic ()
  "Test basic OPTIONAL functionality with some entities having optional properties"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((person1 rdf:type schema:Person)
          (person1 rdfs:label "John")
          (person2 rdf:type schema:Person)
          (person3 rdf:type schema:Person)
          (person3 rdfs:label "Alice")) test-graph))
	 (result (graph-query '(($p rdf:type schema:Person)
                               (optional ($p rdfs:label $name))) test-graph)))
    (should (= 3 (length result)))))

(ert-deftest test-optional-no-match ()
  "Test OPTIONAL with clause that never matches"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((person1 rdf:type schema:Person)
          (person2 rdf:type schema:Person)) test-graph))
	 (result (graph-query '(($p rdf:type schema:Person)
                               (optional ($p nonexistent:property $value))) test-graph)))
    (should (= 2 (length result)))))

(ert-deftest test-optional-with-select ()
  "Test OPTIONAL functionality works with SELECT"
  (let* ((test-graph (make-graph))
	 (side-effect-only (add-triples '((person1 rdf:type schema:Person)
          (person1 rdfs:label "John")
          (person2 rdf:type schema:Person)
          (person3 rdf:type schema:Person)
          (person3 rdfs:label "Alice")) test-graph))
	 (query-result (graph-query '(($p rdf:type schema:Person)
                                     (optional ($p rdfs:label $name))) test-graph))
	 (result (select '($p $name) query-result)))
    (should (= 3 (length result)))
    ;; Verify we get results for all persons, with nil for missing labels
    (should (-any (lambda (row) (and (eq (car row) 'person1) (string= (cadr row) "John"))) result))
    (should (-any (lambda (row) (and (eq (car row) 'person2) (eq (cadr row) nil))) result))
    (should (-any (lambda (row) (and (eq (car row) 'person3) (string= (cadr row) "Alice"))) result))))

(ert-deftest test-delete-triple-basic ()
  "Test basic triple deletion functionality"
  (let ((test-graph (make-graph)))
    ;; Add some triples
    (add-triples '((person1 rdf:type schema:Person)
                   (person1 rdfs:label "John")
                   (person1 foaf:age 30)) test-graph)

    ;; Verify triples exist using graph-query (proper pattern matching)
    (should (= 3 (length (graph-query '(($p $r $o)) test-graph))))
    (should (= 1 (length (graph-query '((person1 rdfs:label $name)) test-graph))))

    ;; Delete one triple
    (delete-triple '(person1 rdfs:label "John") test-graph)

    ;; Verify deletion using graph-query
    (should (= 2 (length (graph-query '(($p $r $o)) test-graph))))
    (should (not (ask '((person1 rdfs:label $name)) test-graph)))

    ;; Verify remaining triples still exist
    (should (= 1 (length (graph-query '((person1 rdf:type $type)) test-graph))))
    (should (= 1 (length (graph-query '((person1 foaf:age $age)) test-graph))))))

(ert-deftest test-delete-triple-cleanup ()
  "Test that DELETE properly cleans up empty hash entries"
  (let ((test-graph (make-graph)))
    ;; Add a single triple
    (add-triple '(person1 rdfs:label "John") test-graph)

    ;; Verify it exists in all indices
    (should (gethash 'person1 (cdr (assoc 'spo test-graph))))
    (should (gethash "John" (cdr (assoc 'osp test-graph))))
    (should (gethash 'rdfs:label (cdr (assoc 'pos test-graph))))

    ;; Delete the triple
    (delete-triple '(person1 rdfs:label "John") test-graph)

    ;; Verify complete cleanup - no entries should remain in hash tables
    (should-not (gethash 'person1 (cdr (assoc 'spo test-graph))))
    (should-not (gethash "John" (cdr (assoc 'osp test-graph))))
    (should-not (gethash 'rdfs:label (cdr (assoc 'pos test-graph))))))

(ert-deftest test-delete-triple-partial-cleanup ()
  "Test that DELETE only removes specific values, not entire entries when other values exist"
  (let ((test-graph (make-graph)))
    ;; Add multiple triples with same subject
    (add-triples '((person1 rdfs:label "John")
                   (person1 foaf:age 30)
                   (person1 rdf:type schema:Person)) test-graph)

    ;; Verify all exist using graph-query
    (should (= 3 (length (graph-query '((person1 $p $o)) test-graph))))

    ;; Delete one triple
    (delete-triple '(person1 rdfs:label "John") test-graph)

    ;; Verify person1 still has entry in SPO index (for other predicates)
    (should (gethash 'person1 (cdr (assoc 'spo test-graph))))
    ;; But rdfs:label should be gone - use graph-query for proper pattern matching
    (should (= 2 (length (graph-query '((person1 $p $o)) test-graph))))
    (should (not (ask '((person1 rdfs:label $name)) test-graph)))))

(ert-deftest test-delete-triples-bulk ()
  "Test bulk deletion with delete-triples function"
  (let ((test-graph (make-graph)))
    ;; Add multiple triples
    (add-triples '((person1 rdf:type schema:Person)
                   (person1 rdfs:label "John")
                   (person2 rdf:type schema:Person)
                   (person2 rdfs:label "Alice")) test-graph)

    ;; Verify initial state using graph-query
    (should (= 4 (length (graph-query '(($s $p $o)) test-graph))))

    ;; Bulk delete
    (delete-triples '((person1 rdfs:label "John")
                      (person2 rdfs:label "Alice")) test-graph)

    ;; Verify deletions using graph-query
    (should (= 2 (length (graph-query '(($s $p $o)) test-graph))))
    (should (not (ask '(($s rdfs:label $name)) test-graph)))
    (should (= 2 (length (graph-query '(($s rdf:type $type)) test-graph))))))

(ert-deftest test-delete-nonexistent-triple ()
  "Test that deleting non-existent triples doesn't break anything"
  (let ((test-graph (make-graph)))
    ;; Add one triple
    (add-triple '(person1 rdfs:label "John") test-graph)

    ;; Try to delete non-existent triple (should not error)
    (delete-triple '(person2 rdfs:label "Alice") test-graph)
    (delete-triple '(person1 foaf:name "John") test-graph)
    (delete-triple '(person1 rdfs:label "Alice") test-graph)

    ;; Original triple should still exist using graph-query
    (should (= 1 (length (graph-query '(($s $p $o)) test-graph))))
    (should (= 1 (length (graph-query '((person1 rdfs:label $name)) test-graph))))))

(ert-deftest test-delete-data-basic ()
  "Test basic delete-data functionality with pattern matching"
  (let ((test-graph (make-graph)))
    ;; Add test data
    (add-triples '((person1 rdf:type foaf:Person)
                   (person1 foaf:age 30)
                   (person2 rdf:type foaf:Person)
                   (person2 foaf:age 25)
                   (person3 rdf:type schema:Organization)) test-graph)

    ;; Verify initial state
    (should (= 5 (length (graph-query '(($s $p $o)) test-graph))))

    ;; Delete all ages
    (should (eq t (delete-data '(($person foaf:age $age)) test-graph)))

    ;; Verify deletion
    (should (= 3 (length (graph-query '(($s $p $o)) test-graph))))
    (should (not (ask '(($s foaf:age $age)) test-graph)))

    ;; Verify people still exist
    (should (= 2 (length (graph-query '(($s rdf:type foaf:Person)) test-graph))))))

(ert-deftest test-delete-data-no-matches ()
  "Test delete-data when no triples match the pattern"
  (let ((test-graph (make-graph)))
    ;; Add test data
    (add-triple '(person1 rdfs:label "John") test-graph)

    ;; Try to delete non-matching pattern
    (should-not (delete-data '(($s foaf:age $age)) test-graph))

    ;; Original data should still exist
    (should (= 1 (length (graph-query '(($s $p $o)) test-graph))))))

(ert-deftest test-delete-data-with-optional ()
  "Test delete-data with OPTIONAL clauses"
  (let ((test-graph (make-graph)))
    ;; Add test data - some people have optional properties
    (add-triples '((person1 rdf:type foaf:Person)
                   (person1 foaf:age 30)
                   (person2 rdf:type foaf:Person)
                   (person3 rdf:type foaf:Person)
                   (person3 foaf:age 25)) test-graph)

    ;; Delete using pattern with OPTIONAL
    (should (eq t (delete-data '(($p rdf:type foaf:Person)
                                (optional ($p foaf:age $age))) test-graph)))

    ;; Only the main pattern triples should be deleted (not the optional parts)
    (should (= 2 (length (graph-query '(($s $p $o)) test-graph))))
    ;; Verify the foaf:age triples remain (optional parts weren't deleted)
    (should (= 2 (length (graph-query '(($s foaf:age $age)) test-graph))))
    ;; Verify no rdf:type foaf:Person triples remain (main pattern was deleted)
    (should (not (ask '(($s rdf:type foaf:Person)) test-graph)))))

(ert-deftest test-delete-data-error-handling ()
  "Test delete-data error handling with malformed patterns"
  (let ((test-graph (make-graph)))
    ;; Add test data
    (add-triple '(person1 rdfs:label "John") test-graph)

    ;; Try delete with malformed pattern (should return nil, not error)
    (should-not (delete-data '((malformed)) test-graph))
    (should-not (delete-data '() test-graph))

    ;; Original data should still exist
    (should (= 1 (length (graph-query '(($s $p $o)) test-graph))))))

(ert-deftest test-graph-query-nesting-single-result ()
  "Test that graph-query returns consistent triple-nested structure for single results"
  (let ((test-graph (make-graph)))
    ;; Add single ontology entry
    (add-triples '((foo:Ontology a owl:Ontology)
                   (foo:Ontology rdfs:comment "Test ontology comment")) test-graph)

    ;; Query that returns single result
    (let ((result (graph-query '(($o a owl:Ontology) ($o rdfs:comment $c)) test-graph)))
      ;; Should be triple-nested: (((bindings)))
      (should (= 1 (length result)))
      (should (listp result))                    ; Level 1: list of solutions
      (should (listp (car result)))             ; Level 2: list of branches
      (should (listp (caar result)))            ; Level 3: list of bindings
      (should (consp (caaar result)))           ; Binding pair: ($var . value)

      ;; Verify actual content
      (let ((solution (car result))
            (branch (caar result)))
        (should (= 2 (length branch)))          ; Two bindings: $o and $c
        (should (assoc '$o branch))
        (should (assoc '$c branch))
        (should (eq (cdr (assoc '$o branch)) 'foo:Ontology))
        (should (string= (cdr (assoc '$c branch)) "Test ontology comment")))))
  )


;; NOTE this test fails, we should re-examine the test body
(ert-deftest test-graph-query-nesting-multiple-results ()
  "Test that graph-query returns consistent triple-nested structure for multiple results"
  (let ((test-graph (make-graph)))
    ;; Add multiple properties
    (add-triples '((prop1 a owl:Property)
                   (prop1 skos:definition "Property 1 definition")
                   (prop2 a owl:Property)
                   (prop2 skos:definition "Property 2 definition")
                   (prop3 a owl:Property)
                   (prop3 skos:definition "Property 3 definition")) test-graph)

    ;; Query that returns multiple results
    (let ((result (graph-query '(($p a owl:Property) ($p skos:definition $d)) test-graph)))
      ;; Should be triple-nested: (((bindings1)) ((bindings2)) ((bindings3)))
      (should (= 3 (length result)))
      (should (listp result))                    ; Level 1: list of solutions

      ;; Check each solution has proper structure
      (dolist (solution result)
        (should (listp solution))                ; Level 2: list of branches
        (should (= 1 (length solution)))         ; Single branch per solution
        (let ((branch (car solution)))
          (should (listp branch))                ; Level 3: list of bindings
          (should (= 2 (length branch)))         ; Two bindings: $p and $d
          (should (assoc '$p branch))
          (should (assoc '$d branch))
          (should (consp (assoc '$p branch)))    ; Binding pairs
          (should (consp (assoc '$d branch)))))

      ;; Verify we have all three properties
      (let ((property-names (mapcar (lambda (sol)
                                      (cdr (assoc '$p (car sol))))
                                    result)))
        (should (member 'prop1 property-names))
        (should (member 'prop2 property-names))
        (should (member 'prop3 property-names))))))

(ert-deftest test-graph-query-nesting-no-results ()
  "Test that graph-query returns consistent structure for queries with no results"
  (let ((test-graph (make-graph)))
    ;; Add some data
    (add-triple '(person1 rdfs:label "John") test-graph)

    ;; Query that finds no results (non-matching pattern)
    (let ((result (condition-case err
                      (graph-query '(($s rdf:type foaf:Person) ($s foaf:age $age)) test-graph)
                    (error nil))))
      ;; Should return nil (no solutions found)
      (should-not result))))

(ert-deftest test-graph-query-nesting-consistency-across-scenarios ()
  "Test that graph-query returns consistent nesting across different result counts"
  (let ((test-graph (make-graph)))
    ;; Add varied data
    (add-triples '((foo:Ontology a owl:Ontology)
                   (foo:Ontology rdfs:comment "Single ontology")
                   (prop1 a owl:Property)
                   (prop1 skos:definition "Property 1")
                   (prop2 a owl:Property)
                   (prop2 skos:definition "Property 2")) test-graph)

    ;; Test single result query structure
    (let ((single-result (graph-query '(($o a owl:Ontology) ($o rdfs:comment $c)) test-graph)))
      (should (= 1 (length single-result)))
      (should (listp (car single-result)))      ; Same structure pattern
      (should (listp (caar single-result))))

    ;; Test multiple result query structure
    (let ((multiple-results (graph-query '(($p a owl:Property) ($p skos:definition $d)) test-graph)))
      (should (= 2 (length multiple-results)))
      (should (listp (car multiple-results)))   ; Same structure pattern
      (should (listp (caar multiple-results))))

    ;; Both should have identical nesting structure
    (let ((single-result (graph-query '(($o a owl:Ontology) ($o rdfs:comment $c)) test-graph))
          (multiple-results (graph-query '(($p a owl:Property) ($p skos:definition $d)) test-graph)))
      ;; Same type structure for first element
      (should (eq (type-of (car single-result)) (type-of (car multiple-results))))
      (should (eq (type-of (caar single-result)) (type-of (caar multiple-results))))
      (should (eq (type-of (caaar single-result)) (type-of (caaar multiple-results)))))))

(ert-deftest test-graph-query-nesting-with-optional ()
  "Test that graph-query maintains consistent nesting with OPTIONAL clauses"
  (let ((test-graph (make-graph)))
    ;; Add data with some entities having optional properties
    (add-triples '((person1 rdf:type foaf:Person)
                   (person1 foaf:name "Alice")
                   (person2 rdf:type foaf:Person)  ; No name
                   (person3 rdf:type foaf:Person)
                   (person3 foaf:name "Bob")) test-graph)

    ;; Query with OPTIONAL should maintain consistent nesting
    (let ((result (graph-query '(($p rdf:type foaf:Person)
                                (optional ($p foaf:name $name))) test-graph)))
      ;; Should return 3 solutions with consistent structure
      (should (= 3 (length result)))

      ;; Each solution should have same nesting structure
      (dolist (solution result)
        (should (listp solution))                ; Level 2: list of branches
        (should (= 1 (length solution)))         ; Single branch
        (let ((branch (car solution)))
          (should (listp branch))                ; Level 3: list of bindings
          (should (>= (length branch) 1))        ; At least $p binding
          (should (assoc '$p branch))))

      ;; Verify nesting consistency across solutions with/without optional bindings
      (let ((first-solution (car result))
            (other-solutions (cdr result)))
        (dolist (other-solution other-solutions)
          (should (eq (type-of first-solution) (type-of other-solution)))
          (should (eq (type-of (car first-solution)) (type-of (car other-solution)))))))))

;;; a/rdf:type equivalence tests

(ert-deftest test-query-time-a-finds-rdf-type ()
  "Test that querying for 'a' also finds 'rdf:type' triples."
  (let ((graph (make-graph)))
    ;; Add only rdf:type triple
    (add-triple '(subject rdf:type foaf:Person) graph)
    ;; Query for 'a' should still find the rdf:type triple
    ;; Note this only tests retrieval and not matching
    (let ((results (triples '($s a foaf:Person) graph)))
      (should results)
      (should (= 1 (length results)))
      (should (equal (car results) '(subject a foaf:Person))))))

(ert-deftest test-query-time-rdf-type-finds-a ()
  "Test that querying for 'rdf:type' also finds 'a' triples."
  (let ((graph (make-graph)))
    ;; Add only 'a' triple
    (add-triple '(subject a foaf:Person) graph)
    ;; Query for rdf:type should still find the 'a' triple
    ;; Note this only tests retrieval and not matching
    (let ((results (triples '($s rdf:type foaf:Person) graph)))
      (should results)
      (should (= 1 (length results)))
      (should (equal (car results) '(subject rdf:type foaf:Person))))))

(ert-deftest test-query-time-mixed-equivalence ()
  "Test complex query mixing 'a' and 'rdf:type' triples."
  (let ((graph (make-graph)))
    ;; Add mixed triples
    (add-triples '((alice a foaf:Person)
                   (bob rdf:type foaf:Person)
                   (charlie a foaf:Organization)) graph)
    ;; Query for all foaf:Person using rdf:type should find both alice and bob
    (let ((results (graph-query '(($s rdf:type foaf:Person)) graph)))
      (should (= 2 (length results)))
      ;; Extract the $s bindings from the results
      (let ((subjects (mapcar (lambda (binding-set)
                               (cdr (assoc '$s (car binding-set))))
                             results)))
        (should (member 'alice subjects))
        (should (member 'bob subjects))))
    ;; Query for all foaf:Person using 'a' should also find both alice and bob
    (let ((results (graph-query '(($s a foaf:Person)) graph)))
      (should (= 2 (length results)))
      ;; Extract the $s bindings from the results
      (let ((subjects (mapcar (lambda (binding-set)
                               (cdr (assoc '$s (car binding-set))))
                             results)))
        (should (member 'alice subjects))
        (should (member 'bob subjects))))))

(ert-deftest test-graph-query-with-a-rdf-type-equivalence ()
  "Test that graph-query works with a/rdf:type equivalence."
  (let ((graph (make-graph)))
    ;; Add mixed data
    (add-triples '((alice a foaf:Person)
                   (bob rdf:type foaf:Person)
                   (alice foaf:name "Alice")
                   (bob foaf:name "Bob")) graph)
    ;; Query using rdf:type should find both alice and bob
    (let ((results (graph-query '(($s rdf:type foaf:Person) ($s foaf:name $name)) graph)))
      (should (= 2 (length results)))
      ;; Check that we got both names
      (let ((names (mapcar (lambda (binding-set)
                            (cdr (assoc '$name (car binding-set))))
                          results)))
        (should (member "Alice" names))
        (should (member "Bob" names))))))

;; Content Reference System Tests

(ert-deftest test-content-reference-large-content ()
  "Test that large content is stored as file reference and transparently retrieved"
  (let ((test-graph (make-graph))
        ;; Set threshold very low for testing
        (el-rdf-max-string-length 50)
        ;; Create large content that exceeds threshold
        (large-content (make-string 100 ?x)))

    ;; Add triple with large content
    (add-triple `(_:test rdfs:label ,large-content) test-graph)

    ;; Query back - should transparently resolve content reference
    (let ((retrieved-triples (triples '(_:test rdfs:label t) test-graph)))
      (should (= 1 (length retrieved-triples)))
      (let ((retrieved-content (nth 2 (car retrieved-triples))))
        (should (= (length large-content) (length retrieved-content)))
        (should (string= large-content retrieved-content))))))

(ert-deftest test-content-reference-small-content ()
  "Test that small content is NOT stored as file reference"
  (let ((test-graph (make-graph))
        ;; Set threshold higher than our test content
        (el-rdf-max-string-length 50)
        ;; Create small content under threshold
        (small-content "small"))

    ;; Add triple with small content
    (add-triple `(_:test2 rdfs:label ,small-content) test-graph)

    ;; Query back - should be stored and retrieved directly
    (let ((retrieved-triples (triples '(_:test2 rdfs:label t) test-graph)))
      (should (= 1 (length retrieved-triples)))
      (let ((retrieved-content (nth 2 (car retrieved-triples))))
        (should (string= small-content retrieved-content))))))

(ert-deftest test-content-reference-graph-query ()
  "Test that graph-query also resolves content references transparently"
  (let ((test-graph (make-graph))
        (el-rdf-max-string-length 30)
        (large-content (make-string 60 ?y)))

    ;; Add triple with large content
    (add-triple `(_:test rdfs:label ,large-content) test-graph)

    ;; Query using graph-query
    (let ((query-result (graph-query '((_:test rdfs:label $content)) test-graph)))
      (should (= 1 (length query-result)))
      (let* ((binding-branch (caar query-result))
             (content-binding (assoc '$content binding-branch))
             (resolved-content (cdr content-binding)))
        (should content-binding)
        (should (= (length large-content) (length resolved-content)))
        (should (string= large-content resolved-content))))))

(ert-deftest test-content-reference-disabled ()
  "Test that content reference system can be disabled"
  (let ((test-graph (make-graph))
        ;; Disable content reference system
        (el-rdf-max-string-length nil)
        (large-content (make-string 1000 ?z)))

    ;; Add triple with large content - should be stored directly
    (add-triple `(_:test rdfs:label ,large-content) test-graph)

    ;; Query back - should retrieve the same large content
    (let ((retrieved-triples (triples '(_:test rdfs:label t) test-graph)))
      (should (= 1 (length retrieved-triples)))
      (let ((retrieved-content (nth 2 (car retrieved-triples))))
        (should (= (length large-content) (length retrieved-content)))
        (should (string= large-content retrieved-content))))))

(ert-deftest test-content-reference-threshold-boundary ()
  "Test content reference behavior at the exact threshold boundary"
  (let ((test-graph (make-graph))
        (el-rdf-max-string-length 50))

    ;; Test content exactly at threshold (should NOT be stored as reference)
    (let ((exact-content (make-string 50 ?a)))
      (add-triple `(_:exact rdfs:label ,exact-content) test-graph)
      (let ((retrieved (nth 2 (car (triples '(_:exact rdfs:label t) test-graph)))))
        (should (string= exact-content retrieved))))

    ;; Test content one character over threshold (SHOULD be stored as reference)
    (let ((over-content (make-string 51 ?b)))
      (add-triple `(_:over rdfs:label ,over-content) test-graph)
      (let ((retrieved (nth 2 (car (triples '(_:over rdfs:label t) test-graph)))))
        (should (string= over-content retrieved))))))

(ert-deftest test-content-reference-multiple-large-objects ()
  "Test multiple large content objects are handled independently"
  (let ((test-graph (make-graph))
        (el-rdf-max-string-length 40)
        (content1 (make-string 80 ?1))
        (content2 (make-string 90 ?2))
        (content3 (make-string 100 ?3)))

    ;; Add multiple triples with large content
    (add-triples `((_:test1 rdfs:label ,content1)
                   (_:test2 rdfs:comment ,content2)
                   (_:test3 rdfs:description ,content3)) test-graph)

    ;; Query all back
    (let ((results1 (triples '(_:test1 rdfs:label t) test-graph))
          (results2 (triples '(_:test2 rdfs:comment t) test-graph))
          (results3 (triples '(_:test3 rdfs:description t) test-graph)))

      (should (= 1 (length results1)))
      (should (= 1 (length results2)))
      (should (= 1 (length results3)))

      ;; Verify each content is correctly retrieved
      (should (string= content1 (nth 2 (car results1))))
      (should (string= content2 (nth 2 (car results2))))
      (should (string= content3 (nth 2 (car results3)))))))

(ert-deftest test-content-reference-with-construct ()
  "Test that CONSTRUCT queries also resolve content references"
  (let ((test-graph (make-graph))
        (el-rdf-max-string-length 25)
        (large-content (make-string 50 ?c)))

    ;; Add data
    (add-triples `((_:person rdf:type foaf:Person)
                   (_:person rdfs:comment ,large-content)) test-graph)

    ;; Use construct to create new triples
    (let* ((query-result (graph-query '((_:person rdf:type foaf:Person)
                                       (_:person rdfs:comment $comment)) test-graph))
           (constructed (construct '((_:person foaf:description $comment)) query-result)))
      (should (= 1 (length constructed)))
      (let ((constructed-triple (car constructed)))
        ;; The constructed triple should have resolved content
        (should (string= large-content (nth 2 constructed-triple)))))))

;; TTL Import Tests

(ert-deftest test-ttl-import-basic ()
  "Test basic TTL file import functionality"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix schema: <https://schema.org/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

schema:Person rdf:type rdfs:Class .
schema:Person rdfs:label \"Person\" .
schema:name rdf:type rdf:Property .
schema:name rdfs:label \"name\" ."))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-import.ttl"
      (insert ttl-content))
    
    ;; Import the TTL file
    (import-ttl "/tmp/test-import.ttl" test-graph)
    
    ;; Verify the triples were imported
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 4 (length all-triples))))
    
    ;; Verify specific triples exist using graph-query
    (should (ask '((schema:Person rdf:type rdfs:Class)) test-graph))
    (should (ask '((schema:Person rdfs:label "Person")) test-graph))
    (should (ask '((schema:name rdf:type rdf:Property)) test-graph))
    (should (ask '((schema:name rdfs:label "name")) test-graph))
    
    ;; Clean up
    (delete-file "/tmp/test-import.ttl")))

(ert-deftest test-ttl-import-prefix-expansion ()
  "Test that TTL prefixes are properly expanded to full IRIs and stored as symbols"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:alice foaf:name \"Alice\" .
ex:bob foaf:knows ex:alice ."))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-prefixes.ttl"
      (insert ttl-content))
    
    ;; Import the TTL file
    (import-ttl "/tmp/test-prefixes.ttl" test-graph)
    
    ;; Verify prefixes were registered in the graph
    (let ((prefixes (cdr (assoc 'prefixes test-graph))))
      (should (string= "http://example.org/" (cdr (assoc "ex" prefixes))))
      (should (string= "http://xmlns.com/foaf/0.1/" (cdr (assoc "foaf" prefixes)))))
    
    ;; Verify triples were imported with expanded IRIs
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 2 (length all-triples))))
    
    ;; Verify specific expanded triples exist (now using prefixed forms)
    (should (ask '((ex:alice foaf:name "Alice")) test-graph))
    (should (ask '((ex:bob foaf:knows ex:alice)) test-graph))
    
    ;; Verify that symbols are properly interned
    (let ((alice-triple (car (triples '(ex:alice t t) test-graph))))
      (should (symbolp (nth 0 alice-triple)))  ; subject
      (should (symbolp (nth 1 alice-triple)))  ; predicate
      (should (stringp (nth 2 alice-triple)))) ; object (literal)
    
    ;; Clean up
    (delete-file "/tmp/test-prefixes.ttl")))

(ert-deftest test-ttl-import-literals-and-datatypes ()
  "Test TTL import handles various literal types correctly"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix ex: <http://example.org/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:person ex:name \"John Doe\" .
ex:person ex:age \"30\"^^<http://www.w3.org/2001/XMLSchema#integer> .
ex:person ex:description \"A person\"@en ."))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-literals.ttl"
      (insert ttl-content))
    
    ;; Import the TTL file
    (import-ttl "/tmp/test-literals.ttl" test-graph)
    
    ;; Verify string literal
    (should (ask '((ex:person ex:name "John Doe")) test-graph))
    
    ;; Verify integer literal is converted to number
    (should (ask '((ex:person ex:age 30)) test-graph))
    
    ;; Verify language-tagged literal (language tag is stripped for now)
    (should (ask '((ex:person ex:description "A person")) test-graph))
    
    ;; Clean up
    (delete-file "/tmp/test-literals.ttl")))

(ert-deftest test-ttl-import-blank-nodes ()
  "Test TTL import handles blank nodes correctly"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix ex: <http://example.org/> .

_:person1 ex:name \"Anonymous Person\" .
_:person2 ex:knows _:person1 ."))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-blanks.ttl"
      (insert ttl-content))
    
    ;; Import the TTL file
    (import-ttl "/tmp/test-blanks.ttl" test-graph)
    
    ;; Verify blank node triples were imported
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 2 (length all-triples))))
    
    ;; Verify blank nodes are properly represented as symbols with el-rdf format
    ;; el-rdf blank nodes have format _:G<number>, so we check for any blank node
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 2 (length all-triples)))
      ;; Check that subjects are symbols starting with "_:"
      (dolist (triple all-triples)
        (let ((subject (nth 0 triple)))
          (should (symbolp subject))
          (should (string-prefix-p "_:" (symbol-name subject))))))
    
    ;; Clean up
    (delete-file "/tmp/test-blanks.ttl")))

(ert-deftest test-ttl-import-comments-and-empty-lines ()
  "Test TTL import ignores comments and empty lines"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix ex: <http://example.org/> .

# This is a comment
ex:alice ex:name \"Alice\" .

# Another comment
# and another

ex:bob ex:name \"Bob\" .
"))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-comments.ttl"
      (insert ttl-content))
    
    ;; Import the TTL file
    (import-ttl "/tmp/test-comments.ttl" test-graph)
    
    ;; Should only have the two actual triples, comments ignored
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 2 (length all-triples))))
    
    ;; Verify the actual triples
    (should (ask '((ex:alice ex:name "Alice")) test-graph))
    (should (ask '((ex:bob ex:name "Bob")) test-graph))
    
    ;; Clean up
    (delete-file "/tmp/test-comments.ttl")))

(ert-deftest test-ttl-import-with-namespace ()
  "Test TTL import with optional namespace parameter for prefixing resources"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix schema: <https://schema.org/> .
schema:Person rdfs:label \"Person\" .
:hasOccupation rdfs:label \"has occupation\" .
someProperty rdfs:label \"some property\" ."))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-namespace.ttl"
      (insert ttl-content))
    
    ;; Import with namespace "myschema"
    (import-ttl "/tmp/test-namespace.ttl" test-graph "myschema")
    
    ;; Verify all triples were imported
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 3 (length all-triples))))
    
    ;; Verify that resources with existing prefixes are unchanged
    (should (ask '((schema:Person rdfs:label "Person")) test-graph))
    
    ;; Verify that resources starting with : get namespace prefix
    (should (ask '((myschema:hasOccupation rdfs:label "has occupation")) test-graph))
    
    ;; Verify that bare resources get namespace prefix
    (should (ask '((myschema:someProperty rdfs:label "some property")) test-graph))
    
    ;; Verify that the un-prefixed versions are NOT found
    (should-not (ask '((:hasOccupation rdfs:label "has occupation")) test-graph))
    (should-not (ask '((someProperty rdfs:label "some property")) test-graph))
    
    ;; Clean up
    (delete-file "/tmp/test-namespace.ttl")))

(ert-deftest test-ttl-import-nonexistent-file ()
  "Test TTL import handles nonexistent files gracefully"
  (let ((test-graph (make-graph)))
    
    ;; Import nonexistent file should not error, just do nothing
    (import-ttl "/nonexistent/file.ttl" test-graph)
    
    ;; Graph should remain empty
    (let ((all-triples (triples '(t t t) test-graph)))
      (should (= 0 (length all-triples))))))

(ert-deftest test-ttl-blank-node-bracket-notation ()
  "Test TTL parsing of blank nodes in bracket notation [ ... ]"
  (let ((test-graph (make-graph))
        (ttl-content "@prefix frame: <http://example.org/frame/> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix componency: <http://example.org/componency/> .

frame:Killing a owl:Class , frame:Frame ;
    rdfs:subClassOf frame:Transitive_action ;
    rdfs:subClassOf [ a owl:Restriction ;
                      owl:onProperty componency:hasComponent ;
                      owl:someValuesFrom frame:Execution ] ;
    rdfs:subClassOf [ a owl:Restriction ;
                      owl:onProperty componency:hasComponent ;
                      owl:someValuesFrom frame:Death ] ."))
    
    ;; Create temporary TTL file
    (with-temp-file "/tmp/test-blank-brackets.ttl"
      (insert ttl-content))
    
    ;; Import the TTL file
    (import-ttl "/tmp/test-blank-brackets.ttl" test-graph)
    
    ;; Get all triples
    (let ((all-triples (triples '(t t t) test-graph)))
      ;; Should parse all triples including blank node contents
      (should (= 11 (length all-triples)))
      
      ;; Check that we have proper blank nodes (symbols starting with _:)
      (let ((blank-node-triples (cl-remove-if-not 
                                 (lambda (triple)
                                   (or (and (symbolp (nth 0 triple))
                                            (string-prefix-p "_:" (symbol-name (nth 0 triple))))
                                       (and (symbolp (nth 2 triple))
                                            (string-prefix-p "_:" (symbol-name (nth 2 triple))))))
                                 all-triples)))
        (should (= 8 (length blank-node-triples))))
      
      ;; Check for malformed triples (should not contain "[" or "]")
      (let ((malformed-triples (cl-remove-if-not
                                (lambda (triple)
                                  (or (and (symbolp (nth 2 triple))
                                           (or (string-match "\\[" (symbol-name (nth 2 triple)))
                                               (string-match "\\]" (symbol-name (nth 2 triple)))))
                                      (and (symbolp (nth 0 triple))
                                           (or (string-match "\\[" (symbol-name (nth 0 triple)))
                                               (string-match "\\]" (symbol-name (nth 0 triple)))))))
                                all-triples)))
        ;; Should be no malformed triples with brackets
        (should (= 0 (length malformed-triples))))
      
      ;; Verify we have the expected structure - frame:Killing should have triples
      (let ((killing-triples (cl-remove-if-not
                              (lambda (triple)
                                (and (symbolp (nth 0 triple))
                                     (string= (symbol-name (nth 0 triple)) "frame:Killing")))
                              all-triples)))
        (should (= 5 (length killing-triples)))
        
        ;; Check for rdfs:subClassOf relationships with blank nodes
        (let ((subclass-blank-triples (cl-remove-if-not
                                       (lambda (triple)
                                         (and (symbolp (nth 0 triple))
                                              (string= (symbol-name (nth 0 triple)) "frame:Killing")
                                              (symbolp (nth 1 triple))
                                              (string= (symbol-name (nth 1 triple)) "rdfs:subClassOf")
                                              (symbolp (nth 2 triple))
                                              (string-prefix-p "_:" (symbol-name (nth 2 triple)))))
                                       all-triples)))
          ;; Should have 2 rdfs:subClassOf relationships with blank nodes
          (should (= 2 (length subclass-blank-triples))))))
    
    ;; Verify specific blank node triples exist
    ;; Each blank node should have the proper internal structure
    (should (ask '(($blank a owl:Restriction)) test-graph))
    (should (ask '(($blank owl:onProperty componency:hasComponent)) test-graph))
    (should (ask '(($blank owl:someValuesFrom frame:Execution)) test-graph))
    (should (ask '(($blank owl:someValuesFrom frame:Death)) test-graph))
    
    ;; Verify main triples exist
    (should (ask '((frame:Killing a owl:Class)) test-graph))
    (should (ask '((frame:Killing a frame:Frame)) test-graph))
    (should (ask '((frame:Killing rdfs:subClassOf frame:Transitive_action)) test-graph))
    
    ;; Clean up
    (delete-file "/tmp/test-blank-brackets.ttl")))

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
