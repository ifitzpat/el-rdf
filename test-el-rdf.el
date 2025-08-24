(require 'ert)
(load-file "el-rdf.el")
(require 'el-rdf)


(setq test-graph (make-graph))

(add-triples '((alice friend bob)
	       (bob friend alice)
	       (bob friend charlie)
	       (alice friend charlie)) test-graph)

(ert-deftest test-select-query ()
  "Test the select function with mutual friendship query"
  (let ((result (select '($x $y) (graph-query '(($x friend $y)($y friend $x)) test-graph))))
    (should
     (member '((alice . bob)) result))))

(provide 'test-el-rdf)
;;; test-el-rdf.el ends here
