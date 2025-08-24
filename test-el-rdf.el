(require 'ert)
(load-file "el-rdf.el")
(require 'el-rdf)


(setq test-graph (make-graph))

(add-triples '((alice friend bob)
	       (bob friend alice)
	       (bob friend charlie)
	       (alice friend charlie)) test-graph)


(ert-deftest test-ask-query()
  (should
   (ask '((alice friend bob)) test-graph)
   ))

(ert-deftest test-select-query ()
  "Test the select function with mutual friendship query"
  (let ((result (select '($x $y) (graph-query '(($x friend $y)($y friend $x)) test-graph))))
    (should
     (-any
      (lambda (x)
	(and
	 (member 'alice x)
	 (member 'bob x)))
      result))))

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
