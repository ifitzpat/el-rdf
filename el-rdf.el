;;; el-rdf --- in-memory triple store for Emacs lisp  -*- lexical-binding: t -*-

;; Copyright (C) 2025 Ian FitzPatrick

;; Author: Ian FitzPatrick ian@ianfitzpatrick.eu
;; URL: codeberg.org/ifitzpat/el-rdf
;; Version: 0.0.1-alpha
;; Package-Requires: ((emacs "27.1")(request))
;; Keywords: rdf triple-store

;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Placeholder

;;; Code:

  (defun update-dual (key val orig)
    ;; orig is ((a (foo:bar baz:guuq))(frob:nix ("1")))
    (let* ((oldval (cdr (assoc key orig)))) ; '(val1 val2 val3)
      (if oldval
  	(progn
  	  (setf (cdr (assoc key orig)) (unless (member val oldval)(cons val oldval)))
  	  orig)
        (append `((,key . ,(list val))) orig))
      ))

  (defun add-triple (triple graph)
    (let* ((newsub (nth 0 triple))
  	 (newpred (nth 1 triple))
  	 (newobj (nth 2 triple))
  	 (spo (cdr (assoc 'spo graph)))
  	 (osp (cdr (assoc 'osp graph)))
  	 (pos (cdr (assoc 'pos graph)))
  	 (po (gethash newsub spo)) ; alist ((p . (o1 o2 o3)))
  	 (sp (gethash newobj osp)) ; alist ((s . (p1 p2 p3)))
  	 (os (gethash newpred pos))) ; alist ((o . (s1 s2 s3)))
      (if po ; a triple with that subject exists
          (puthash newsub (update-dual newpred newobj po) spo)
        (puthash newsub `((,newpred . ,(list newobj))) spo))
      (if sp
          (puthash newobj (update-dual newsub newpred sp) osp)
        (puthash newobj `((,newsub . ,(list newpred))) osp))
      (if os
          (puthash newpred (update-dual newobj newsub os) pos)
        (puthash newpred `((,newobj . ,(list newsub))) pos))
      ;; maybe refactor into cond
      ))

  (defun variable? (x)
    "Check if x is a variable (starts with $)."
    (and (symbolp x)
         (string-prefix-p "$" (symbol-name x))))

  (defun var-or-wild? (x)
    (or (eq x t) (variable? x)))

  (defun namespace (x)
    (car (split-string (symbol-name x) ":")))

  (defun expand-duals (duals element &optional reorder)
    ;;  ((baz:bak foo:quix) (foo:bar foo:quix foo:baz) (a frob:niz schema:thing))
    (mapcan
     (lambda (x)
      ; (if (listp (cdr x))
	   (mapcar (lambda (y)
  	       (cond
  		((and (boundp 'reorder) (eq reorder 'pos))
  		 (list  y element (car x))
  		 )
  		((and (boundp 'reorder) (eq reorder 'osp))
  		 (list (car x) y element)
  		 )
  		(t
                   (list element (car x) y))
  		)
  	       ) (cdr x))
	 ;(list element (car x) (cdr x))
	; )
       ) duals)
    )


  ;; From ht.el -- Author: Wilfred Hughes <me@wilfred.me.uk>
  (defun ht-map (function table)
    "Apply FUNCTION to each key-value pair of TABLE, and make a list of the results.
  FUNCTION is called with two arguments, KEY and VALUE."
    (let (results)
      (maphash
       (lambda (key value)
         (push (funcall function key value) results))
       table)
      results))


;; unused
  (defun test-expand ()
    (ht-map (lambda (key value)
  	    (expand-duals value key))
  	  (cdr (assoc 'spo graph-index))))

  (defun triples (pattern graph) ;; doesn't do pattern matching just retrieves the right index
    (let ((s (nth 0 pattern))
  	(p (nth 1 pattern))
  	(o (nth 2 pattern)))
      (cond
       ((not (var-or-wild? s))
        (expand-duals (gethash s (cdr (assoc 'spo graph))) s)
        )
       ((not (var-or-wild? p))
        (expand-duals (gethash p (cdr (assoc 'pos graph))) p 'pos)
        )
       ((not (var-or-wild? o))
        (expand-duals (gethash o (cdr (assoc 'osp graph))) o 'osp) ;; TODO reorder
        )
       (t
        (ht-map (lambda (key value)
  		(expand-duals value key))
  	      (cdr (assoc 'spo graph))))
       )))

  (defun printgindex (index)
    (maphash (lambda (key value)
  	     (princ (format "key: %s, value: %s" key value) )
  	     (princ "\n")
  	     ) index))

  (defun variable? (x)
    "Check if x is a variable (starts with $)."
    (and (symbolp x)
         (string-prefix-p "$" (symbol-name x))))

  (defun pat-match (pattern input)
    ;; Note: if done on triples retrieved from an index one third of the comparisons might be redundant
    (when (not pattern)
      nil)
    (if (variable? pattern) (list (cons pattern input))
      (if (and (atom pattern)(atom input))
          (if (eq pattern input)
  	    (list (cons t input))
  	  (list (cons nil nil)))
        (append (pat-match (car pattern)(car input))
  	      (pat-match (cdr pattern)(cdr input))))))

  (defun traverse-graph (pattern graph)
    (-remove (lambda (x)
  	     (member '(nil . nil) x))
             (mapcar (lambda (x)
                       (remove '(t) (pat-match pattern x))) ; (t) probabely gets added when comparing the last nil of the list
                     graph)))

 (defun filter-triples (pattern triples)
   (-filter
    (lambda (x)
      (not (member '(nil . nil) (pat-match pattern x)))
      )
    triples)
   )
  ;; traverse-graph yields a structure like
  ;; ((($a . rdf:type)
  ;;   ($b . schema:thing))
  ;;  (($a . rdfs:label)
  ;;   ($b . "foo")))

  (defun add-triples (triplist graph)
    (mapc (lambda (x) (add-triple x graph)) triplist))


  (defun apply-clauses (clauses graph)
    (mapcar (lambda (pattern)
  	    (traverse-graph pattern (triples pattern graph))
  	    ) clauses))

  (defun clean-bindings (bindings)
    (mapcar (lambda (y)
  	    (-remove (lambda (x)
  		       (eq t (car x))) y))
  		bindings))

  (defun compatible-bindings? (newbindings oldbindings)
    (princ (format "comparing %s with %s\n" newbindings oldbindings))
    (-every
     'identity
     (mapcar (lambda (x)
  	     (let ((oldval (cdr (assoc (car x) (car oldbindings))))
  		   (newval (cdr (assoc (car x) (list x))))
  		   )

  (princ
  	      (format "comparing %s with %s\n" newval oldval))
  	     (or (not oldval)(eq oldval newval))

  	       )
  	     	     ) newbindings)
     ))

  (defun update-bindings (newbindings oldbindings)
    ;; FIXME I need a way to deal with binding scenarios
    ;; certainly check whether the binding conflicts (i.e., $a is bound to different values in newbindings and oldbindings)
    (cond ((not newbindings) (clean-bindings oldbindings))
    (t
        (progn
  	;(princ (format "try to add %s to %s \n" newbindings oldbindings))
  	(mapcan  (lambda (x)
  		   (if (not (compatible-bindings? x oldbindings))
  		       (progn
  			 (princ (format "Conflicing bindings %s and %s\n" x oldbindings))
  			 nil)
  		       (clean-bindings (list (-uniq (append x (car oldbindings))))) )) newbindings))))
    )

  (defun graph-query (clauses graph &optional bindings)
    (let*  ((bindings (or bindings '()))
  					;(bindings (mapcar (lambda (y) (-remove (lambda (x) (eq t (car x))) y)) bindings))
  	  (pattern (car clauses)))
      (princ (format "new call; bidings are now %s with length %s \n" bindings (length bindings)))

      (cond ((or (not clauses) (< (length pattern) 3)) ; we're at the end of the list of clauses
  	   bindings)
  	  ((not bindings) ; this is the first invocation
  	   (let ((bindings (traverse-graph pattern (triples pattern graph))))
  	     (princ "first call\n")
  	     (if (not bindings)
  		 (error (format "The graph pattern %s doesn't match" pattern))
  	       (graph-query (cdr clauses) graph (update-bindings nil bindings)))))
  	  ((> (length bindings) 1)
  	   (mapcar
  	    (lambda (binding-branch)
  	      (let*
  		  ((newbindings (traverse-graph
  				 (cl-sublis binding-branch pattern)
  				 (triples pattern graph)))
  		   (updated-bindings (update-bindings newbindings (list binding-branch)))
  					;(newbindings (mapcar (lambda (y) (-remove (lambda (x) (eq t (car x))) y)) newbindings))
  		   )
                  (princ (format "current clause %s \n" pattern))
                  (princ (format "with bindings %s \n" (cl-sublis binding-branch pattern)))
                  (princ (format "yielded bindings %s \n" newbindings))
  		(princ (format "rest of the claues %s \n" (cl-sublis binding-branch (cdr clauses))))
  		(princ (format "maybe add found bindings to current bindings %s \n"  (update-bindings newbindings (list binding-branch ))))
  		(if (or (not newbindings)(not updated-bindings))
  		    nil
  		  (graph-query
  		   (cl-sublis updated-bindings (cdr clauses))
  		   graph
  		   updated-bindings)
  		  )
  		)
  	      )
  	    bindings)

  	   )
  	  (t
  	   (let* ((newbindings
  		   (traverse-graph (cl-sublis bindings pattern)
  				   (triples pattern graph)))
   		  (updated-bindings (update-bindings newbindings bindings)))
  	     (if (or (not newbindings)(not updated-bindings) )
  		 nil 	   ; if nil then return nil
  	       (graph-query (cl-sublis updated-bindings (cdr clauses)) graph updated-bindings))
  	     ) ;take the next clause
  					; get bindings associated with it

  	   )


  	  )))

      ;; I want to return a list of triples
        (defun terse-to-triples (terse)
          (let ((subject (car terse))
      	  (predobj (maybe-relist-obj (cdr terse) )))
            (expand-duals predobj subject)))

(defun maybe-relist-obj (predobj)
  ;; FIXME
  (mapcar
   (lambda (x)
     (if (listp (cdr x))
       x
       (cons (car x) (cons (cdr x) nil))
	 )
     )
predobj)

  )
(defun render-triple (triple)
  (if (symbolp (nth 2 triple))
      (concat (format "\"%s\" -> \"%s\" [label=\"%s\"];\n" (nth 0 triple) (nth 2 triple) (nth 1 triple)))
      (let ((g (gensym)))
          (concat (format "\"%s\" -> \"%s\" [label=\"%s\"];\n" (nth 0 triple) g (nth 1 triple))
		  (format "%s [label=\"%s\",shape=box];\n" g (nth 2 triple))
		  )
	)

    ))

(defun nodes (triples)
  (-uniq (append (mapcar (lambda (x) (nth 0 x)) triples)
	(mapcar (lambda (x) (nth 2 x)) triples)) ))

(defun literals (nodelist)
  (-remove #'symbolp
	     nodelist))

(defun apply-node-styles (triples &optional styles)
  (let* ((styles (or styles
		    '(("xsd" . (:color "blue" :fillcolor "blue" :fontcolor "white"))
		      ("rdf" . (:color "#ff0000" :fillcolor "#ff0000" :fontcolor "white"))
		      )
		    ))
	(all-vertices (nodes triples))
	(all-vertices (cl-set-difference all-vertices '(rdf:Property rdfs:Class skos:Concept)))
	(vertices (cl-set-difference all-vertices (literals all-vertices)))
	)
(mapconcat (lambda (n)
	       (let* ((style (cdr (assoc (namespace n) styles)))
		      (default (cdr (assoc "default" styles)))
		      (defaultcolor (plist-get default :color))
		      (defaultfillcolor (plist-get default :fillcolor))
		      (defaultfontcolor (plist-get default :fontcolor))
		      (color (plist-get style :color))
		      (fillcolor (plist-get style :fillcolor))
		      (fontcolor (plist-get style :fontcolor)))
 	         (if style
		   (format "\"%s\" [color=\"%s\",fillcolor=\"%s\",fontcolor=\"%s\"];\n"
			 n
			 color
			 fillcolor
			 fontcolor
			 )
		   (if default
                    (format "\"%s\" [color=\"%s\",fillcolor=\"%s\",fontcolor=\"%s\"];\n"
			 n
			 defaultcolor
			 defaultfillcolor
			 defaultfontcolor
			 )
		       "")
		   )

		 )

	       ) vertices)
    )
 )

(defun render-triples(triples &optional styles)
  (let* ((classes (filter-triples '($a a skos:Concept) triples))
	 (properties (filter-triples '($a a rdf:Property) triples))
	 (triples (cl-set-difference triples properties))
	 (triples (cl-set-difference triples classes))
	 (classstyle (or (cdr (assoc "class" styles)) '(("default" . (:color "#ffff00" :fillcolor "#00ff00" :fontcolor "white")))))
	 (propertystyle (or (cdr (assoc "property" styles)) '(("default" . (:color "#00ffff" :fillcolor "#00ffff" :fontcolor "white")))))
	)
(concat
   "digraph G {\noverlap=prism;\nnode[shape=circle,style=filled,fontcolor=\"black\",fillcolor=\"white\"];\nlayout=\"fdp\";\nbeautify=true;\nsep=\"2\";\n"
   (apply-node-styles triples styles)
   (apply-node-styles classes `(("default" . ,classstyle)))
   (apply-node-styles properties `(("default" . ,propertystyle)))
   (mapconcat #'render-triple triples)
   "}"
   )
      )
  )

(defun render-graph (triples filename &optional styles)
 (with-temp-file "/tmp/graph.dot"
    (insert (render-triples triples styles))
  )
 (shell-command (concat "dot /tmp/graph.dot -Tsvg > " filename))
 filename)

(defun render-graph-json (triples filename &optional styles)
 (with-temp-file "/tmp/graph.dot"
    (insert (render-triples triples styles))
  )
 (shell-command (concat "dot /tmp/graph.dot -Tjson > " filename))
 filename)


;;; el-rdf ends here
