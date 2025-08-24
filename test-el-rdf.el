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

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
