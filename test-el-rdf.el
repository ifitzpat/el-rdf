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

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
