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

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
