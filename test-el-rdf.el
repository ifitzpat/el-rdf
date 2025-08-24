(require 'ert)
(load-file "el-rdf.el")
(require 'el-rdf)


(setq test-graph (make-graph))

(add-triples '((alice friend bob)
	       (bob friend charlie)
	       (alice friend charlie)) test-graph)

(ert-deftest test-select-query ()
  "Test the select function"
  (should
   (eq (select '($x $y) (graph-query '(($x friend $y)($y friend $x)))) '(($x . alice)($y . bob)) ) ))

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
