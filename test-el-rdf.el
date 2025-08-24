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

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
