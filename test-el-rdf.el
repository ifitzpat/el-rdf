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

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
