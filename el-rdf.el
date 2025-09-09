;;; el-rdf --- in-memory triple store for Emacs lisp  -*- lexical-binding: t -*-

;; Copyright (C) 2025 Ian FitzPatrick

;; Author: Ian FitzPatrick ian@ianfitzpatrick.eu
;; URL: codeberg.org/ifitzpat/el-rdf
;; Version: 0.1.2
;; Package-Requires: ((emacs "27.1")(request)(dash "20250312.1307"))
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
(require 'dash)
(require 'cl-seq)

(defvar el-rdf-debug nil
  "When non-nil, enable debug output for el-rdf operations.")

(defun make-graph ()
`((spo . ,(make-hash-table :test 'eq))
  	(osp . ,(make-hash-table :test 'equal))
  	(pos . ,(make-hash-table :test 'eq))))

  (defun update-dual (key val orig)
    ;; orig is ((a (foo:bar baz:guuq))(frob:nix ("1")))
    (let* ((oldval (cdr (assoc key orig)))) ; '(val1 val2 val3)
      (if oldval
  	(progn
  	  (setf (cdr (assoc key orig)) (unless (member val oldval)(cons val oldval)))
  	  orig)
        (append `((,key . ,(list val))) orig))
      ))

  (defun remove-dual (key val orig)
    "Remove VAL from the list associated with KEY in ORIG. Returns updated alist.
    If the resulting list is empty, removes the KEY entry entirely.
    ORIG structure: ((key1 . (val1 val2)) (key2 . (val3 val4)))"
    (let* ((entry (assoc key orig))
           (oldvals (cdr entry)))
      (if entry
          (let ((newvals (remove val oldvals)))
            (if newvals
                ;; Update the entry with remaining values
                (progn
                  (setf (cdr entry) newvals)
                  orig)
              ;; No values left, remove the entire key entry
              (remove entry orig)))
        ;; Key not found, return original unchanged
        orig)))

  (defun add-triple (triple graph)
    (let* ((newsub (nth 0 triple))
  	 (newpred (if (eq (nth 1 triple) 'rdf:type) 'a (nth 1 triple))) ; Normalize rdf:type to 'a'
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

  (defun delete-triple (triple graph)
    "Remove a triple from the graph, updating all three indices (SPO, OSP, POS).
    Automatically cleans up empty entries using remhash when no triples remain."
    (let* ((sub (nth 0 triple))
  	 (pred (if (eq (nth 1 triple) 'rdf:type) 'a (nth 1 triple))) ; Normalize rdf:type to 'a'
  	 (obj (nth 2 triple))
  	 (spo (cdr (assoc 'spo graph)))
  	 (osp (cdr (assoc 'osp graph)))
  	 (pos (cdr (assoc 'pos graph)))
  	 (po (gethash sub spo))   ; alist ((p . (o1 o2 o3)))
  	 (sp (gethash obj osp))   ; alist ((s . (p1 p2 p3)))
  	 (os (gethash pred pos))) ; alist ((o . (s1 s2 s3)))

      ;; Remove from SPO index: sub -> ((pred . (obj1 obj2...)))
      (when po
        (let ((updated-po (remove-dual pred obj po)))
          (if updated-po
              (puthash sub updated-po spo)
            ;; No predicates left for this subject, remove entirely
            (remhash sub spo))))

      ;; Remove from OSP index: obj -> ((sub1 . (pred1 pred2...)))
      (when sp
        (let ((updated-sp (remove-dual sub pred sp)))
          (if updated-sp
              (puthash obj updated-sp osp)
            ;; No subjects left for this object, remove entirely
            (remhash obj osp))))

      ;; Remove from POS index: pred -> ((obj1 . (sub1 sub2...)))
      (when os
        (let ((updated-os (remove-dual obj sub os)))
          (if updated-os
              (puthash pred updated-os pos)
            ;; No objects left for this predicate, remove entirely
            (remhash pred pos))))))




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
  		((and 'reorder (eq reorder 'pos))
  		 (list  y element (car x))
  		 )
  		((and 'reorder (eq reorder 'osp))
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


(defun transform-a-results-to-rdf-type (triples)
(let ((transformed-results
                     (mapcar (lambda (triple)
                              (list (nth 0 triple) 'rdf:type (nth 2 triple)))
                            triples)))
		transformed-results))

  (defun triples (pattern graph) ;; doesn't do pattern matching just retrieves the right index
    (let ((s (nth 0 pattern))
  	(p (nth 1 pattern))
  	(o (nth 2 pattern)))
      ; (princ (format "DEBUG triples: pattern=%s, s=%s p=%s o=%s\n" pattern s p o))
      (cond
       ((not (var-or-wild? s))
        ; (princ (format "DEBUG triples: using SPO index for subject %s\n" s))
	(let ((results (expand-duals (gethash s (cdr (assoc 'spo graph))) s)))
	  (if (eq p 'rdf:type)
(transform-a-results-to-rdf-type results)
	   results   )

	  )
        )
       ((not (var-or-wild? p))
        ;; Handle a/rdf:type equivalence when querying by predicate
        (if (eq p 'rdf:type)
            ;; Query for rdf:type but only 'a' exists in storage, so look up 'a' and transform results
            (let ((a-results (expand-duals (gethash 'a (cdr (assoc 'pos graph))) 'a 'pos)))
              ;; Transform to rdf:type and filter by object if specified
	      (transform-a-results-to-rdf-type a-results))
          ;; Normal predicate lookup
	  (expand-duals (gethash p (cdr (assoc 'pos graph))) p 'pos)))
       ((not (var-or-wild? o))
        ; (princ (format "DEBUG triples: using OSP index for object %s\n" o))
	(let ((results (expand-duals (gethash o (cdr (assoc 'osp graph))) o 'osp)))
	  (if (eq p 'rdf:type)
(transform-a-results-to-rdf-type results)
	      results)

	  ))
       (t
        ; (princ "DEBUG triples: using universal pattern - all triples\n")
        (apply #'append
               (ht-map (lambda (key value)
                        (expand-duals value key))
                      (cdr (assoc 'spo graph)))))
       )))

(defun triples-to-string (trips)
  "Convert a list of TRIPS to string while preserving nil values and empty strings."
  (concat
   "("
   (mapconcat
    (lambda (trip)
      (concat "("
              (mapconcat
               (lambda (element)
                 (cond
                  ((stringp element) (format "%S" element))
                  ((null element) "nil")
                  (t (format "%s" element))))
               trip
               " ")
              ")"))
    trips
    "\n ")
   ")"))

(defun save-graph (graph filename)
  (let
      ((full-graph (triples '(t t t) graph)))
    (with-current-buffer
	(get-buffer-create (find-file-noselect filename))
        (erase-buffer)
        (insert (triples-to-string full-graph))
	(save-buffer))))

(defun load-graph (graph filename)
  (add-triples (with-current-buffer (get-buffer-create (find-file-noselect filename))
        (read (buffer-string))) graph))

  (defun printgindex (index)
    (when el-rdf-debug
      (maphash (lambda (key value)
  	       (princ (format "key: %s, value: %s" key value) )
  	       (princ "\n")
  	       ) index)))

  (defun variable? (x)
    "Check if x is a variable (starts with $)."
    (and (symbolp x)
         (string-prefix-p "$" (symbol-name x))))

  (defun optional-clause? (clause)
    "Check if clause is wrapped with optional."
    (and (listp clause)
         (eq (car clause) 'optional)))

  (defun unwrap-optional (clause)
    "Extract the pattern from an optional clause."
    (if (optional-clause? clause)
        (cadr clause)
      clause))

  (defun normalize-pattern (pattern)
    "Normalize rdf:type to 'a' in a pattern for consistent matching.
     Only normalize if the pattern contains NO variables, since triples()
     already handles equivalence by transforming results."
    (if (and (listp pattern)
             (>= (length pattern) 3)
             (eq (nth 1 pattern) 'rdf:type)
             ;; Only normalize if ALL parts are concrete (no variables anywhere)
             (not (var-or-wild? (nth 0 pattern)))
             (not (var-or-wild? (nth 2 pattern))))
        (list (nth 0 pattern) 'a (nth 2 pattern))
      pattern))


(defun augmented-eq (pattern input)
  (cond ((symbolp pattern) (eq pattern input))
	((stringp pattern) (string= pattern input))
	((numberp pattern) (eql pattern input))))

  (defun pat-match (pattern input)
    ;; Note: if done on triples retrieved from an index one third of the comparisons might be redundant
    (when (not pattern)
      nil)
    (if (variable? pattern) (list (cons pattern input))
      (if (and (atom pattern)(atom input))
          (if (augmented-eq pattern input)
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
    "Add multiple triples to the graph."
    (mapc (lambda (x) (add-triple x graph)) triplist))

  (defun delete-triples (triplist graph)
    "Delete multiple triples from the graph."
    (mapc (lambda (x) (delete-triple x graph)) triplist))


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
    (when el-rdf-debug
      (princ (format "comparing %s with %s\n" newbindings oldbindings)))
    (-every
     'identity
     (mapcar (lambda (x)
  	     (let ((oldval (cdr (assoc (car x) (car oldbindings)))) ; FIXME deal with multiple bindings
  		   (newval (cdr (assoc (car x) (list x))))
  		   )

  (when el-rdf-debug
    (princ
  	      (format "comparing %s with %s\n" newval oldval)))
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
  	;(when el-rdf-debug (princ (format "try to add %s to %s \n" newbindings oldbindings)))
  	(mapcan  (lambda (x)
  		   (if (not (compatible-bindings? x oldbindings))
  		       (progn
  			 (when el-rdf-debug
  			   (princ (format "Conflicing bindings %s and %s\n" x oldbindings)))
  			 nil)
  		       (clean-bindings (list (-uniq (append x (car oldbindings))))) )) newbindings))))
    )

  (defun graph-query (clauses graph &optional bindings)
    "Execute a SPARQL-like query against a graph, supporting OPTIONAL clauses.

CLAUSES is a list of triple patterns, e.g., '(($s rdf:type foaf:Person) ($s foaf:name $name))
GRAPH is the RDF graph created with make-graph
BINDINGS is the current variable bindings (used for recursive calls)

OPTIONAL SYNTAX:
  Use (optional PATTERN) to mark optional clauses, e.g.,
  '(($s rdf:type foaf:Person) (optional ($s foaf:name $name)))

BINDING STRUCTURE:
  The function maintains a triple-nested binding structure throughout execution:
  - Level 1: List of binding sets (one per solution)
  - Level 2: List of binding branches within each solution
  - Level 3: Individual variable bindings as (var . value) pairs

EXAMPLES OF DATA FLOW:

1. FIRST CALL (no bindings):
   Input:   clauses='(($s rdf:type foaf:Person) ($s foaf:name $name))
            bindings=nil

   After first pattern match:
   bindings='((($s . alice)) (($s . bob)))

   Wrapped for consistency:
   bindings='(((($s . alice))) ((($s . bob))))

2. MULTIPLE BINDINGS (length > 1):
   Input:   clauses='(($s foaf:name $name))
            bindings='(((($s . alice))) ((($s . bob))))

   For each binding branch:
   - alice: pattern becomes '(alice foaf:name $name)
   - bob: pattern becomes '(bob foaf:name $name)

   Results might be:
   - alice: newbindings='((($name . \"Alice Smith\")))
   - bob: newbindings='() (no name found)

   Final result:
   '(((($s . alice) ($name . \"Alice Smith\"))))

3. SINGLE BINDING BRANCH:
   Input:   clauses='(($s foaf:email $email))
            bindings='((($s . alice) ($name . \"Alice Smith\")))

   Substituted pattern: '(alice foaf:email $email)
   If match found: newbindings='((($email . \"alice@example.com\")))
   Final: '((($s . alice) ($name . \"Alice Smith\") ($email . \"alice@example.com\")))

4. OPTIONAL CLAUSES:
   When is-optional=t and a clause fails to match:
   - Instead of returning nil (which would fail the entire query)
   - Continue with existing bindings to next clause
   - This implements SPARQL OPTIONAL left-join semantics

EXECUTION PATHS:
  1. Base case: No more clauses or malformed pattern -> return current bindings
  2. First call: No existing bindings -> match first pattern, recurse with results
  3. Multiple branches: Split execution per binding branch, combine results
  4. Single branch: Apply pattern to current bindings, recurse with updated bindings"
    (let*  ((bindings (or bindings '()))
  					;(bindings (mapcar (lambda (y) (-remove (lambda (x) (eq t (car x))) y)) bindings))
  	  (pattern (car clauses))
  	  (is-optional (optional-clause? pattern))
  	  (unwrapped-pattern (if is-optional (unwrap-optional pattern) pattern)))
      (when el-rdf-debug
        (princ (format "new call; bidings are now %s with length %s \n" bindings (length bindings))))
      ; (princ (format "DEBUG graph-query: clauses=%s, pattern=%s, bindings=%s\n" clauses pattern bindings))

      (cond ((or (not clauses) (< (length unwrapped-pattern) 3)) ; we're at the end of the list of clauses
  	   bindings)
  	  ((not bindings) ; this is the first invocation
  	   (let ((bindings (traverse-graph
			    ;(normalize-pattern unwrapped-pattern)
			    unwrapped-pattern
			    (triples unwrapped-pattern graph))))
  	     (when el-rdf-debug
  	       (princ "first call\n"))
  	     (if (and (not bindings) (not is-optional))
  		 (error (format "The graph pattern %s doesn't match" unwrapped-pattern))
  	       (if (cdr clauses)
  		   ;; More clauses to process
  		   (graph-query (cdr clauses) graph (update-bindings nil (or bindings '())))
  		 ;; Single clause - wrap each binding in a list for consistency
  		 (if bindings (mapcar #'list bindings) '())))))
  	  ;; MULTIPLE BINDING BRANCHES: Split execution per branch, combine results
	  ((> (length bindings) 1)
  	   (mapcar
  	    (lambda (binding-branch)
  	      (let*
  		  ((newbindings (traverse-graph
  				 ;(normalize-pattern (cl-sublis binding-branch unwrapped-pattern))
				 (cl-sublis binding-branch unwrapped-pattern)
  				 (triples unwrapped-pattern graph)))
  		   (updated-bindings (update-bindings newbindings (list binding-branch)))
  					;(newbindings (mapcar (lambda (y) (-remove (lambda (x) (eq t (car x))) y)) newbindings))
  		   )
                  (when el-rdf-debug
                    (princ (format "current clause %s \n" unwrapped-pattern))
                    (princ (format "with bindings %s \n" (cl-sublis binding-branch unwrapped-pattern)))
                    (princ (format "yielded bindings %s \n" newbindings))
  		    (princ (format "rest of the claues %s \n" (cl-sublis binding-branch (cdr clauses))))
  		    (princ (format "maybe add found bindings to current bindings %s \n"  (update-bindings newbindings (list binding-branch )))))
  		(if (or (not newbindings)(not updated-bindings))
  		    (if is-optional
			;; For optional clauses that fail, continue with existing bindings
			(graph-query (cdr clauses) graph (list binding-branch))
		      nil)
  		  (graph-query
  		   (cl-sublis updated-bindings (cdr clauses))
  		   graph
  		   updated-bindings)
  		  )
  		)
  	      )
  	    bindings)

  	   )
  	  ;; SINGLE BINDING BRANCH: Apply pattern to current bindings
	  (t
  	   (let* ((newbindings
  		   (traverse-graph
		    ;(normalize-pattern (cl-sublis bindings unwrapped-pattern))
		    (cl-sublis bindings unwrapped-pattern)
  				   (triples unwrapped-pattern graph)))
   		  (updated-bindings (update-bindings newbindings bindings)))
  	     (if (or (not newbindings)(not updated-bindings) )
  		 (if is-optional
		     ;; For optional clauses that fail, continue with existing bindings
		     (graph-query (cdr clauses) graph bindings)
		   nil) 	   ; if nil then return nil
  	       (let ((result (graph-query (cl-sublis updated-bindings (cdr clauses)) graph updated-bindings)))
  		 ;; For single-branch queries, ensure result has same structure as single-clause queries
  		 ;; Single-clause queries return: (((bindings)))
  		 ;; But single-branch multi-clause can return: ((bindings))
  		 ;; Check if result needs one more level of wrapping
  		 (if (and result
  			  (= 1 (length result))
  			  (= 1 (length updated-bindings))
  			  (consp (car result))
  			  (consp (caar result))
  			  ;; Check if (caaar result) is a symbol (binding pair key)
  			  (symbolp (caaar result)))
  		     ;; This looks like ((bindings)) but should be (((bindings)))
  		     (list result)
  		   result)))
  	     ) ;take the next clause
  					; get bindings associated with it

  	   )


  	  )))

;; TODO where could be a function that wraps around graph-query
;; maybe it returns a lambda that can be applied to graph
;; and maybe it takes an optional FILTER function that is applied to the result of the graph-query
;; the construct, select, ask functions should then apply the where function to the graph

(defalias 'where 'graph-query)

(defun binding-val (b res)
  (cdr (assoc b res)))


(defun bindings-from-row (bs row)
  (mapcar (lambda (r) (mapcar (lambda (b) (binding-val b r)) bs)) row))

(defun ask (where graph)
  (condition-case nil
      (>= (length (remove nil (graph-query where graph) ) ) 1)
     (error nil)))

;; TODO refactor this so that where is a function
(defun select (binding-list where)
  (mapcan (lambda (r)
	    (if (symbolp (car r)) ; not a nested list
		(list r)
		r))
          (mapcar (lambda (r) (bindings-from-row binding-list r)) where)))


      ;; I want to return a list of triples
        (defun terse-to-triples (terse)
          (let ((subject (car terse))
      	  (predobj (maybe-relist-obj (cdr terse) )))
            (expand-duals predobj subject)))

(defun delete-data (where graph)
  "Delete all triples matching the WHERE pattern from GRAPH.
WHERE is a list of triple patterns that may include variables and OPTIONAL clauses.
Returns t if deletion succeeded, nil if no matches found or query failed.

Examples:
  (delete-data '(($s rdf:type foaf:Person)) graph)  ; Delete all people
  (delete-data '(($p foaf:age $age)) graph)        ; Delete all age properties"
  (condition-case nil
      (let* ((bindings (graph-query where graph))
             (triples-to-delete (construct where bindings)))
        (when triples-to-delete
          (delete-triples triples-to-delete graph)
          t))
    (error nil)))

(defun construct (clauses where)
  (mapcan (lambda (l)
	    (mapcan (lambda (r)
		      (expand-list-bindings (cl-sublis r clauses))
		      ) l)
	    ) where))

(defun expand-list-bindings (triples)
  "Expand triples containing list values into multiple triples"
  (mapcan (lambda (triple)
            (let ((subject (nth 0 triple))
                  (predicate (nth 1 triple))
                  (object (nth 2 triple)))
              ;; Check if object is a list
              (if (listp object)
                  ;; Expand list into multiple triples
                  (mapcar (lambda (obj) (list subject predicate obj)) object)
                ;; Single triple
                (list triple))))
          triples))

;; NOTE this is possible resource intensive for large graphs
(defun graph-union (&rest args)
  (let ((tempgraph (make-graph)))
    (mapc (lambda (g)
		(add-triples (triples '($s $p $o) g) tempgraph)
		) args)
    tempgraph))

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

(defun eval-with-bindings (thelist thefun)
  "Bind keys in THELIST to their values and execute THEFUN."
  (let ((bindings (mapcar (lambda (pair)
			    (let ((mycar (car pair))
				  (mycdr (cdr pair)))
			      (when (and (symbolp mycdr) (not (boundp mycdr)) )
				(setq mycdr `',mycdr))
                               `(,mycar ,mycdr)))
                           (cl-remove-if (lambda (pair) (eq (car pair) t)) thelist))))
    (eval
     `(let ,bindings
             (funcall ,thefun)))))

(defun filter (predicate bindinglist)
  ;; for each list of bindings in bindinglist
  ;; bind all the variables then execute the predicate
  (-filter (lambda (l)
	    (-any (lambda (b) (eval-with-bindings b predicate)) l)) ;; check if any binding in the list satisfies predicate
	   bindinglist))


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

(provide 'el-rdf)
;;; el-rdf.el ends here
