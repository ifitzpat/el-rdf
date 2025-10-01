;;; el-rdf --- in-memory triple store for Emacs lisp  -*- lexical-binding: t -*-

;; Copyright (C) 2025 Ian FitzPatrick

;; Author: Ian FitzPatrick ian@ianfitzpatrick.eu
;; URL: codeberg.org/ifitzpat/el-rdf
;; Version: 0.2.1
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
;; (require 'uuidgen)  ; Commented out for testing

;; Increase macro expansion limits to handle large datasets
(setq max-lisp-eval-depth 5000)
(setq max-specpdl-size 10000)
;; Also increase macro expansion limits
(setq max-macroexpand-depth 5000)
(setq lisp-eval-depth-limit 5000)

(defvar el-rdf-debug nil
  "When non-nil, enable debug output for el-rdf operations.")

(defvar el-rdf-max-string-length 1000
  "Maximum string length before content is stored as file reference. Set to nil to disable.")

;; Checkpointing system for el-rdf
(defvar el-rdf-checkpoint-dir nil
  "Directory where graph checkpoints are stored. Defaults to XDG_CACHE_HOME/el-rdf/checkpoints/")

(defun el-rdf--get-checkpoint-dir ()
  "Get the checkpoint directory for el-rdf, creating it if necessary."
  (let ((checkpoint-dir (or el-rdf-checkpoint-dir
                           (let ((cache-dir (or (getenv "XDG_CACHE_HOME")
                                               (expand-file-name ".cache" (getenv "HOME")))))
                             (expand-file-name "el-rdf/checkpoints" cache-dir)))))
    (unless (file-directory-p checkpoint-dir)
      (make-directory checkpoint-dir t))
    checkpoint-dir))

(defvar el-rdf-graph-checkpoints (make-hash-table :test 'eq)
  "Hash table mapping graphs to their checkpoint information.
Each entry is (graph . (name . last-checkpoint-time)).")

(defun el-rdf--get-cache-dir ()
  "Get the cache directory for el-rdf, creating it if necessary."
  (let ((cache-dir (or (getenv "XDG_CACHE_HOME")
                       (expand-file-name ".cache" (getenv "HOME")))))
    (let ((el-rdf-cache-dir (expand-file-name "el-rdf" cache-dir)))
      (unless (file-directory-p el-rdf-cache-dir)
        (make-directory el-rdf-cache-dir t))
      el-rdf-cache-dir)))

(defun el-rdf--content-reference-p (obj)
  "Return t if OBJ is a file content reference."
  (and (stringp obj) (string-prefix-p "file:" obj)))

(defun el-rdf--store-large-content (content)
  "Store large CONTENT to cache file and return reference string.
Uses MD5 hash of content as filename for deduplication."
  (when (and el-rdf-max-string-length
             (stringp content)
             (> (length content) el-rdf-max-string-length))
    (let* ((content-hash (secure-hash 'md5 content))
           (filename (format "content-%s.txt" content-hash))
           (filepath (expand-file-name filename (el-rdf--get-cache-dir)))
           (reference (format "file:%s" filename)))
      ;; Only write file if it doesn't already exist (deduplication)
      (unless (file-exists-p filepath)
        (with-temp-file filepath
          (insert content)))
      reference)))

(defun el-rdf--resolve-content-reference (reference)
  "Resolve a file REFERENCE back to its original content."
  (if (el-rdf--content-reference-p reference)
      (let* ((filename (substring reference 5)) ; Remove "file:" prefix
             (filepath (expand-file-name filename (el-rdf--get-cache-dir))))
        (if (file-exists-p filepath)
            (with-temp-buffer
              (insert-file-contents filepath)
              (buffer-string))
          ;; File doesn't exist - return the reference as-is for graceful degradation
          reference))
    reference))

(defun el-rdf--process-triple-object (obj)
  "Process triple object, storing large content as reference if needed."
  (let ((stored-ref (el-rdf--store-large-content obj)))
    (or stored-ref obj)))

(defun el-rdf--resolve-triple-object (obj)
  "Resolve triple object, loading content from reference if needed."
  (el-rdf--resolve-content-reference obj))

(defun make-graph (&optional name)
  "Create a new RDF graph with optional NAME for checkpointing.
If NAME is provided, the graph can be easily saved/restored by name."
`((spo . ,(make-hash-table :test 'eq))
  	(osp . ,(make-hash-table :test 'equal))
  	(pos . ,(make-hash-table :test 'eq))
  	(hooks . ((add-hooks . ,(list))
  	          (delete-hooks . ,(list))
  	          (query-hooks . ,(list))))
  	(prefixes . ())
  	(name . ,name)))

;; Helper functions for hook management
(defun add-hook-to-graph (graph hook-type hook-function)
  "Add HOOK-FUNCTION to HOOK-TYPE hooks in GRAPH.
HOOK-TYPE should be 'add-hooks, 'delete-hooks, or 'query-hooks."
  (let* ((hooks (cdr (assoc 'hooks graph)))
         (hook-entry (assoc hook-type hooks))
         (hook-list (cdr hook-entry)))
    (unless (member hook-function hook-list)
      (setf (cdr hook-entry) (cons hook-function hook-list)))))

(defun remove-hook-from-graph (graph hook-type hook-function)
  "Remove HOOK-FUNCTION from HOOK-TYPE hooks in GRAPH."
  (let* ((hooks (cdr (assoc 'hooks graph)))
         (hook-list (cdr (assoc hook-type hooks))))
    (setf (cdr (assoc hook-type hooks))
          (remove hook-function hook-list))))

(defun get-graph-hooks (graph hook-type)
  "Get all hooks of HOOK-TYPE from GRAPH."
  (cdr (assoc hook-type (cdr (assoc 'hooks graph)))))

;; Checkpointing functions
(defun el-rdf-register-graph-for-checkpointing (graph graph-name)
  "Register a GRAPH for automatic checkpointing with GRAPH-NAME.
The graph will be checkpointed automatically when add-hooks are triggered."
  (puthash graph (cons graph-name (current-time)) el-rdf-graph-checkpoints)
  ;; Add the checkpoint hook to the graph
  (add-hook-to-graph graph 'add-hooks #'el-rdf-checkpoint-hook))

(defun el-rdf-checkpoint-hook (graph operation data)
  "Hook function that checkpoints registered graphs after add operations.
GRAPH is the graph being operated on, OPERATION is the operation type,
DATA is the operation data (triples list)."
  (let ((checkpoint-info (gethash graph el-rdf-graph-checkpoints))
        (graph-name (cdr (assoc 'name graph))))
    (when checkpoint-info
      (let* ((registered-name (car checkpoint-info))
             ;; Use graph's internal name if available, fall back to registered name
             (actual-name (or graph-name registered-name))
             (checkpoint-file (el-rdf-checkpoint-file-path actual-name)))
        (when el-rdf-debug
          (princ (format "DEBUG: Hook checkpointing %s to %s after %s\n"
                         graph-name checkpoint-file operation)))
        ;; Save the graph data
        (save-graph graph checkpoint-file)

        ;; Save metadata
        (el-rdf-save-checkpoint-metadata graph-name operation data)

        ;; Update last checkpoint time
        (puthash graph (cons graph-name (current-time)) el-rdf-graph-checkpoints)))))

(defun el-rdf-checkpoint-file-path (graph-name)
  "Generate checkpoint file path for a named graph."
  (let ((checkpoint-dir (el-rdf--get-checkpoint-dir)))
    (expand-file-name (format "%s.checkpoint" graph-name) checkpoint-dir)))

(defun el-rdf-recover-from-checkpoint (graph-name)
  "Recover a graph from checkpoint and return it.
GRAPH-NAME is the string name used in checkpoint files.
Also loads and displays metadata if available.
The recovered graph includes the name but is NOT automatically re-registered for checkpointing."
  (let ((checkpoint-file (el-rdf-checkpoint-file-path graph-name)))
    (if (file-exists-p checkpoint-file)
        (let ((recovered-graph (make-graph graph-name))
              (metadata (el-rdf-load-checkpoint-metadata graph-name)))
          (load-graph recovered-graph checkpoint-file)
          (message "Recovered %s with %d triples from checkpoint"
                   graph-name
                   (length (construct '(($s $p $o))
                                    (graph-query '(($s $p $o)) recovered-graph))))
          ;; Display metadata if available
          (when metadata
            (message "Last operation: %s, Data size: %d, Recursion depth: %d"
                     (plist-get metadata :last-operation)
                     (plist-get metadata :data-size)
                     (plist-get metadata :recursion-depth))
            (when (plist-get metadata :call-stack)
              (message "Call stack: %s" (plist-get metadata :call-stack))))
          recovered-graph)
      (error "No checkpoint file found for %s at %s" graph-name checkpoint-file))))

(defun bnode ()
   (intern (concat "_:" (symbol-name (gensym)))))

(defun el-rdf-recover-and-register (graph-name)
  "Recover a graph from checkpoint and automatically re-register it for checkpointing.
Returns the recovered graph ready for continued checkpointing."
  (let ((recovered-graph (el-rdf-recover-from-checkpoint graph-name)))
    (el-rdf-register-graph-for-checkpointing recovered-graph graph-name)
    (message "Graph %s recovered and re-registered for checkpointing" graph-name)
    recovered-graph))

(defun el-rdf-save-named-graph (graph)
  "Save a named graph to its checkpoint file immediately.
The graph must have been created with make-graph with a name parameter."
  (let ((graph-name (cdr (assoc 'name graph))))
    (if graph-name
        (progn
          (save-graph graph (el-rdf-checkpoint-file-path graph-name))
          (el-rdf-save-checkpoint-metadata graph-name 'manual-save '())
          (message "Saved graph %s to checkpoint" graph-name))
      (error "Graph has no name - cannot save by name"))))

(defun el-rdf-restore-named-graph (graph-name)
  "Convenience function combining recovery and registration.
Creates a named graph, recovers from checkpoint, and registers for checkpointing.
This is the recommended way to restore graphs for continued use."
  (el-rdf-recover-and-register graph-name))

(defun el-rdf-save-checkpoint-metadata (graph-name operation data)
  "Save checkpoint metadata for GRAPH-NAME after OPERATION with DATA.
Metadata includes operation type, data size, timestamp, and call stack information."
  (let ((metadata-file (expand-file-name
                        (format "%s.metadata" graph-name)
                        (el-rdf--get-checkpoint-dir)))
        (call-stack (when (boundp 'neurosymb-predicate-call-stack)
                      (symbol-value 'neurosymb-predicate-call-stack))))
    (with-temp-file metadata-file
      (prin1 (list :last-operation operation
                   :data-size (length data)
                   :timestamp (current-time)
                   :call-stack call-stack
                   :recursion-depth (length call-stack))
             (current-buffer)))))

(defun el-rdf-load-checkpoint-metadata (graph-name)
  "Load checkpoint metadata for GRAPH-NAME and return it as a plist.
Returns nil if metadata file doesn't exist."
  (let ((metadata-file (expand-file-name
                        (format "%s.metadata" graph-name)
                        (el-rdf--get-checkpoint-dir))))
    (when (file-exists-p metadata-file)
      (with-temp-buffer
        (insert-file-contents metadata-file)
        (read (current-buffer))))))

(defun el-rdf-list-checkpoints ()
  "List all available checkpoint files."
  (let ((checkpoint-dir (el-rdf--get-checkpoint-dir)))
    (when (file-exists-p checkpoint-dir)
      (directory-files checkpoint-dir nil "\\.checkpoint$"))))

  (defun update-dual (key val orig)
    ;; orig is ((a (foo:bar baz:guuq))(frob:nix ("1")))
    (let* ((oldval (cdr (assoc key orig)))) ; '(val1 val2 val3)
      (if oldval
  	(progn
	;  (princ (format "\noldval: %s\n\n" oldval))
	;  (princ (format "\nval: %s\n\n" val))
  	  (setf (cdr (assoc key orig)) ;; change the alist
		(if (member val oldval) oldval (cons val oldval)))
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
  	 (newobj (el-rdf--process-triple-object (nth 2 triple))) ; Store large content as reference
	 ;(for-debug (princ (format "\n\nadding %s %s %s\n\n" newsub newpred newobj)))
  	 (spo (cdr (assoc 'spo graph)))
  	 (osp (cdr (assoc 'osp graph)))
  	 (pos (cdr (assoc 'pos graph)))
  	 (po (gethash newsub spo)) ; alist ((p . (o1 o2 o3)))
  	 (sp (gethash newobj osp)) ; alist ((s . (p1 p2 p3)))
  	 (os (gethash newpred pos))) ; alist ((o . (s1 s2 s3)))
      (if po ; a triple with that subject exists
          (progn
	  ;  (princ (format "subject exists %s\n\n" newsub))
	    (puthash newsub (update-dual newpred newobj po) spo) )
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
    "Expand duals structure into triples with batched processing to avoid recursion limits."
    (if (not duals)
        '()
      (let ((result '())
            (value-batch-size 100))  ; Process values in batches to avoid deep recursion
        (while duals
          (let* ((dual (car duals))
                 (key (car dual))
                 (values (cdr dual))
                 (processed-values 0))
            ;; Process values in batches
            (while values
              (let ((batch-end (min value-batch-size (length values)))
                    (current-batch 0))
                (while (and values (< current-batch batch-end))
                  (let ((value (car values)))
                    (cond
                     ((eq reorder 'pos)
                      (setq result (cons (list value element key) result)))
                     ((eq reorder 'osp)
                      (setq result (cons (list key value element) result)))
                     (t
                      (setq result (cons (list element key value) result))))
                    (setq values (cdr values))
                    (setq current-batch (1+ current-batch))
                    (setq processed-values (1+ processed-values))))
                ;; Yield control after each batch to prevent recursion buildup
                (when values
                  (sit-for 0.001))))
            (setq duals (cdr duals))))
        (nreverse result))))


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

(defun el-rdf--resolve-triple-objects (triples)
  "Resolve content references in TRIPLES objects, returning triples with resolved content."
  (mapcar (lambda (triple)
            (list (nth 0 triple)
                  (nth 1 triple)
                  (el-rdf--resolve-content-reference (nth 2 triple))))
          triples))


(defun transform-a-results-to-rdf-type (triples)
(let ((transformed-results
                     (mapcar (lambda (triple)
			       (if (eq (nth 1 triple) 'a)
				   (list (nth 0 triple) 'rdf:type (nth 2 triple))
				   triple))
                            triples)))
		transformed-results))

  (defun triples (pattern graph) ;; doesn't do pattern matching just retrieves the right index
    (let ((s (nth 0 pattern))
  	(p (nth 1 pattern))
  	(o (nth 2 pattern)))
      ; (princ (format "DEBUG triples: pattern=%s, s=%s p=%s o=%s\n" pattern s p o))
      (let ((raw-results
             (cond
              ((not (var-or-wild? s))
               ; (princ (format "DEBUG triples: using SPO index for subject %s\n" s))
	       (let ((results (expand-duals (gethash s (cdr (assoc 'spo graph))) s)))
	         (if (eq p 'rdf:type)
                     (transform-a-results-to-rdf-type results)
	           results)))
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
	           results)))
              (t
               ; (princ "DEBUG triples: using universal pattern - all triples\n")
               (let ((result '())
                     (spo-table (cdr (assoc 'spo graph)))
                     (batch-size 50)  ; Process subjects in batches to avoid deep recursion
                     (processed-count 0))
                 ;; Use hash-table-keys if available, otherwise extract keys without closures
                 (if (fboundp 'hash-table-keys)
                     (let ((all-keys (hash-table-keys spo-table)))
                       (while all-keys
                         (let ((batch-keys (cl-subseq all-keys 0 (min batch-size (length all-keys)))))
                           (dolist (key batch-keys)
                             (let ((value (gethash key spo-table)))
                               (setq result (append (expand-duals value key) result))
                               (setq processed-count (1+ processed-count))))
                           ;; Remove processed keys from the list
                           (setq all-keys (nthcdr (min batch-size (length all-keys)) all-keys))
                           ;; Yield control every batch to prevent deep recursion buildup
                           (when all-keys
                             (sit-for 0.001)))))
                   ;; Fallback: extract keys without closures using temporary variables
                   (let ((all-keys '())
                         (temp-key nil)
                         (temp-value nil))
                     (maphash (lambda (k v)
                                (setq temp-key k)
                                (setq temp-value v)
                                (push temp-key all-keys))
                              spo-table)
                     (while all-keys
                       (let ((batch-keys (cl-subseq all-keys 0 (min batch-size (length all-keys)))))
                         (dolist (key batch-keys)
                           (let ((value (gethash key spo-table)))
                             (setq result (append (expand-duals value key) result))
                             (setq processed-count (1+ processed-count))))
                         ;; Remove processed keys from the list
                         (setq all-keys (nthcdr (min batch-size (length all-keys)) all-keys))
                         ;; Yield control every batch to prevent deep recursion buildup
                         (when all-keys
                           (sit-for 0.001))))))
                 result)))))
        ;; Resolve content references in all returned triples
        (el-rdf--resolve-triple-objects raw-results))))

(defun raw-triples (pattern graph)
  "Like triples, but returns raw data without resolving content references.
Used for checkpointing to preserve file references."
  (let ((s (nth 0 pattern))
	(p (nth 1 pattern))
	(o (nth 2 pattern)))
    (cond
     ((not (var-or-wild? s))
      (let ((results (expand-duals (gethash s (cdr (assoc 'spo graph))) s)))
	(if (eq p 'rdf:type)
            (transform-a-results-to-rdf-type results)
	  results)))
     ((not (var-or-wild? p))
      (if (eq p 'rdf:type)
          (let ((a-results (expand-duals (gethash 'a (cdr (assoc 'pos graph))) 'a 'pos)))
	    (transform-a-results-to-rdf-type a-results))
        (expand-duals (gethash p (cdr (assoc 'pos graph))) p 'pos)))
     ((not (var-or-wild? o))
      (let ((results (expand-duals (gethash o (cdr (assoc 'osp graph))) o 'osp)))
	(if (eq p 'rdf:type)
            (transform-a-results-to-rdf-type results)
	  results)))
     (t
      (let ((result '())
            (spo-table (cdr (assoc 'spo graph)))
            (batch-size 50)
            (processed-count 0))
        (if (fboundp 'hash-table-keys)
            (let ((all-keys (hash-table-keys spo-table)))
              (while all-keys
                (let ((batch-keys (cl-subseq all-keys 0 (min batch-size (length all-keys)))))
                  (dolist (key batch-keys)
                    (let ((value (gethash key spo-table)))
                      (setq result (append (expand-duals value key) result))
                      (setq processed-count (1+ processed-count))))
                  (setq all-keys (nthcdr (min batch-size (length all-keys)) all-keys))
                  (when all-keys
                    (sit-for 0.001)))))
          (let ((all-keys '())
                (temp-key nil)
                (temp-value nil))
            (maphash (lambda (k v)
                       (setq temp-key k)
                       (setq temp-value v)
                       (push temp-key all-keys))
                     spo-table)
            (while all-keys
              (let ((batch-keys (cl-subseq all-keys 0 (min batch-size (length all-keys)))))
                (dolist (key batch-keys)
                  (let ((value (gethash key spo-table)))
                    (setq result (append (expand-duals value key) result))
                    (setq processed-count (1+ processed-count))))
                (setq all-keys (nthcdr (min batch-size (length all-keys)) all-keys))
                (when all-keys
                  (sit-for 0.001))))))
        result)))))

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
  "Save GRAPH to FILENAME, preserving file references for large content."
  (let
      ((full-graph (raw-triples '(t t t) graph)))
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
	((stringp pattern) (and (stringp input) (string= pattern input)))
	((numberp pattern) (and (numberp input) (eql pattern input)))
	(t (equal pattern input))))

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
    (mapc (lambda (x) (add-triple x graph)) triplist)
    ;; Call add-hooks after bulk operation
    (let ((add-hooks (cdr (assoc 'add-hooks (cdr (assoc 'hooks graph))))))
      (mapc (lambda (hook) (funcall hook graph 'add-triples triplist))
            add-hooks)))

  (defun delete-triples (triplist graph)
    "Delete multiple triples from the graph."
    (mapc (lambda (x) (delete-triple x graph)) triplist)
    ;; Call delete-hooks after bulk operation
    (let ((delete-hooks (cdr (assoc 'delete-hooks (cdr (assoc 'hooks graph))))))
      (mapc (lambda (hook) (funcall hook graph 'delete-triples triplist))
            delete-hooks)))


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
    ;; Call query-hooks before processing
    (let ((query-hooks (cdr (assoc 'query-hooks (cdr (assoc 'hooks graph))))))
      (mapc (lambda (hook) (funcall hook graph 'graph-query clauses))
            query-hooks))
    ;; Normalize all results to ensure consistent binding structure
    (let ((raw-results (el-rdf--graph-query-internal clauses graph bindings)))
      (if raw-results
          (el-rdf--normalize-binding-results raw-results)
        raw-results)))

  (defun el-rdf--graph-query-internal (clauses graph &optional bindings)
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
  		   (el-rdf--graph-query-internal (cdr clauses) graph (update-bindings nil (or bindings '())))
  		 ;; Single clause - wrap each binding in a list for consistency
  		 (if bindings (mapcar #'list bindings) '())))))
  	  ;; MULTIPLE BINDING BRANCHES: Split execution per branch, combine results
	  ((> (length bindings) 1)
  	   (-remove #'null
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
			(el-rdf--graph-query-internal (cdr clauses) graph (list binding-branch))
		      nil)
  		  (el-rdf--graph-query-internal
  		   (cl-sublis updated-bindings (cdr clauses))
  		   graph
  		   updated-bindings)
  		  )
  		)
  	      )
  	    bindings))

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
		     (el-rdf--graph-query-internal (cdr clauses) graph bindings)
		   nil) 	   ; if nil then return nil
  	       (let ((result (el-rdf--graph-query-internal (cl-sublis updated-bindings (cdr clauses)) graph updated-bindings)))
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

;; Binding structure normalization utilities

(defun el-rdf--detect-binding-nesting-level (binding-structure)
  "Recursively detect how many levels of nesting exist before reaching a binding pair.
A binding pair is a cons cell where the car is a symbol (variable like $s).
Returns the nesting level as an integer."
  (cond
   ;; Base case 1: nil or empty
   ((null binding-structure) 0)
   ;; Base case 2: This is a binding pair ($var . value)
   ((and (consp binding-structure)
         (symbolp (car binding-structure))
         (not (listp (cdr binding-structure))))
    0)
   ;; Base case 3: This is a list of binding pairs (($var . value) ...)
   ((and (listp binding-structure)
         (consp (car binding-structure))
         (symbolp (caar binding-structure))
         (not (listp (cdar binding-structure))))
    0)
   ;; Recursive case: go one level deeper
   ((listp binding-structure)
    (1+ (el-rdf--detect-binding-nesting-level (car binding-structure))))
   ;; Fallback
   (t 0)))

(defun el-rdf--normalize-binding-structure (binding-structure target-level)
  "Normalize binding structure to the target nesting level.
TARGET-LEVEL 0 = binding pairs: (($s . value) ($p . value))
TARGET-LEVEL 1 = binding sets: ((($s . value) ($p . value)))
TARGET-LEVEL 2 = binding collections: (((($s . value) ($p . value))))
etc."
  (let ((current-level (el-rdf--detect-binding-nesting-level binding-structure)))
    (cond
     ;; Already at target level
     ((= current-level target-level)
      binding-structure)
     ;; Need to unwrap (current > target)
     ((> current-level target-level)
      (let ((unwrapped binding-structure))
        (dotimes (_ (- current-level target-level))
          (setq unwrapped (if (listp unwrapped) (car unwrapped) unwrapped)))
        unwrapped))
     ;; Need to wrap (current < target)
     ((< current-level target-level)
      (let ((wrapped binding-structure))
        (dotimes (_ (- target-level current-level))
          (setq wrapped (list wrapped)))
        wrapped))
     ;; Fallback
     (t binding-structure))))

(defun el-rdf--normalize-binding-results (binding-results)
  "Normalize all binding results to the expected level 1 format: (bindings).
This ensures consistent output from graph-query regardless of execution path."
  (mapcar (lambda (binding-result)
            (el-rdf--normalize-binding-structure binding-result 1))
          binding-results))

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
  "Execute a SELECT query with SPARQL semantics for failed matches.
BINDING-LIST is the list of variables to select.
WHERE should be the result of (graph-query clauses graph), but if the entire
WHERE clause fails to match, return nil values for all bindings."
  (if where
      (mapcan (lambda (r)
                (if (symbolp (car r)) ; not a nested list
                    (list r)
                  r))
              (mapcar (lambda (r) (bindings-from-row binding-list r)) where))
    ;; Return nil for all requested variables when WHERE is empty/nil
    (list (mapcar (lambda (var) nil) binding-list))))

(defun select-safe (binding-list clauses graph)
  "Execute a SELECT query that gracefully handles failed WHERE clauses.
BINDING-LIST is the list of variables to select.
CLAUSES is the list of query patterns.
GRAPH is the RDF graph to query.

This function implements SPARQL SELECT semantics: if the WHERE clause fails
to match entirely, return nil bindings for all requested variables instead
of throwing an error."
  (let ((where-result (condition-case nil
                          (graph-query clauses graph)
                        (error nil))))
    (select binding-list where-result)))


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

(defun el-rdf--register-prefix (graph prefix namespace)
  "Register PREFIX to expand to NAMESPACE in GRAPH."
  (let ((prefixes (cdr (assoc 'prefixes graph))))
    (setf (cdr (assoc 'prefixes graph))
          (cons (cons prefix namespace) prefixes))))

(defun el-rdf--expand-prefixed-iri (graph prefixed-iri)
  "Expand a prefixed IRI like 'schema:Person' to full IRI using GRAPH prefixes."
  (if (string-match "^\\([^:]+\\):\\(.+\\)$" prefixed-iri)
      (let* ((prefix (match-string 1 prefixed-iri))
             (local-part (match-string 2 prefixed-iri))
             (prefixes (cdr (assoc 'prefixes graph)))
             (namespace (cdr (assoc prefix prefixes))))
        (if namespace
            (concat namespace local-part)
          prefixed-iri))
    prefixed-iri))

(defun el-rdf--intern-rdf-resource (graph resource-string &optional namespace)
  "Convert RDF resource string to symbol, keeping prefixed form.
If NAMESPACE is provided, prefix the resource with it."
  (let ((final-resource-string
         (if namespace
             (if (string-prefix-p ":" resource-string)
                 ;; Handle cases like ":hasOccupation" -> "schema:hasOccupation"
                 (concat namespace resource-string)
               ;; Handle cases like "hasOccupation" -> "schema:hasOccupation"
               (if (string-match ":" resource-string)
                   resource-string  ; Already has namespace, keep as-is
                 (concat namespace ":" resource-string)))
           resource-string)))
    (intern final-resource-string)))

(defun el-rdf--parse-ttl-value (graph value-string &optional namespace)
  "Parse a TTL value (IRI, literal, blank node) into appropriate Lisp form.
If NAMESPACE is provided, prefix resources with it."
  (cond
   ;; Handle 'a' special case - it's rdf:type, don't add namespace
   ((string= value-string "a")
    'a)
   ;; Handle angle bracket IRIs
   ((string-prefix-p "<" value-string)
    (let ((iri (substring value-string 1 -1)))
      (intern iri)))
   ;; Handle quoted strings with proper unescaping
   ((string-prefix-p "\"" value-string)
    ;; Check if this is a triple-quoted string
    (if (and (>= (length value-string) 6)
             (string-prefix-p "\"\"\"" value-string)
             (string-suffix-p "\"\"\"" value-string))
        ;; Handle triple-quoted string - extract content between triple quotes
        (let ((literal-value (substring value-string 3 -3)))
          ;; Don't unescape triple-quoted strings - they preserve literal content including newlines
          literal-value)
      ;; Handle regular quoted string
      (if (string-match "\"\\(\\(?:[^\"\\\\]\\|\\\\.\\)*\\)\"\\(@\\([a-zA-Z-]+\\)\\|\\^\\^<\\(.+\\)>\\)?" value-string)
          (let ((literal-value (match-string 1 value-string))
                (lang (match-string 3 value-string))
                (datatype (match-string 4 value-string)))
            ;; Unescape the literal value
            (setq literal-value (replace-regexp-in-string "\\\\\\(.\\)" "\\1" literal-value))
            (cond
             (datatype
              (if (string= datatype "http://www.w3.org/2001/XMLSchema#integer")
                  (string-to-number literal-value)
                literal-value))
             (lang
              ;; TODO: Add proper language tag support to el-rdf
              ;; For now, strip language tags and return just the literal value
              literal-value)
             (t literal-value)))
        ;; Fallback for malformed quoted strings
        (substring value-string 1 -1))))
   ;; Handle blank nodes
   ((string-prefix-p "_:" value-string)
    ;; Use el-rdf's bnode function for consistent blank node format
    (bnode))
   ;; Handle URLs that look like http://... without angle brackets
   ((string-match "^https?://" value-string)
    (intern value-string))
   ;; Handle prefixed resources
   ((string-match ":" value-string)
    (el-rdf--intern-rdf-resource graph value-string namespace))
   ;; Handle bare resources
   (t
    (el-rdf--intern-rdf-resource graph value-string namespace))))

(defun el-rdf--simple-tokenize-ttl (content)
  "Simple tokenizer that handles quoted strings properly."
  (let ((tokens '())
        (pos 0)
        (len (length content)))
    (while (< pos len)
      (let ((char (aref content pos)))
        (cond
         ;; Skip whitespace and newlines
         ((memq char '(?\s ?\t ?\n ?\r))
          (setq pos (1+ pos)))
         ;; Handle quoted strings - both single and triple quotes
         ((eq char ?\")
          (let ((start pos))
            ;; Check if this is a triple quote
            (if (and (< (+ pos 2) len)
                     (eq (aref content (+ pos 1)) ?\")
                     (eq (aref content (+ pos 2)) ?\"))
                ;; Handle triple-quoted string
                (progn
                  (setq pos (+ pos 3)) ; Skip opening triple quotes
                  (while (and (< (+ pos 2) len)
                              (not (and (eq (aref content pos) ?\")
                                        (eq (aref content (+ pos 1)) ?\")
                                        (eq (aref content (+ pos 2)) ?\"))))
                    (setq pos (1+ pos)))
                  (when (< (+ pos 2) len) ; Include closing triple quotes
                    (setq pos (+ pos 3)))
                  (push (substring content start pos) tokens))
              ;; Handle single-quoted string
              (progn
                (setq pos (1+ pos)) ; Skip opening quote
                (while (and (< pos len)
                            (not (eq (aref content pos) ?\")))
                  (when (eq (aref content pos) ?\\) ; Handle escaped characters
                    (setq pos (1+ pos)))
                  (setq pos (1+ pos)))
                (when (< pos len) ; Include closing quote
                  (setq pos (1+ pos)))
                (push (substring content start pos) tokens)))))
         ;; Handle angle bracket IRIs
         ((eq char ?<)
          (let ((start pos))
            (while (and (< pos len) (not (eq (aref content pos) ?>)))
              (setq pos (1+ pos)))
            (when (< pos len) ; Include closing bracket
              (setq pos (1+ pos)))
            (push (substring content start pos) tokens)))
         ;; Handle special punctuation
         ((memq char '(?\; ?\. ?\,))
          (push (char-to-string char) tokens)
          (setq pos (1+ pos)))
         ;; Handle regular tokens
         (t
          (let ((start pos))
            (while (and (< pos len)
                        (not (memq (aref content pos) '(?\s ?\t ?\n ?\r ?\; ?\. ?\, ?< ?\"))))
              (setq pos (1+ pos)))
            (when (> pos start)
              (push (substring content start pos) tokens)))))))
    (nreverse tokens)))

(defun el-rdf--parse-simple-ttl-statement (tokens start-pos)
  "Parse a single TTL statement from TOKENS starting at START-POS.
Returns (triples . next-pos)."
  (let ((pos start-pos)
        (len (length tokens))
        (triples '())
        subject)
    (when (< pos len)
      ;; Get subject
      (setq subject (nth pos tokens))
      (setq pos (1+ pos))

      ;; Parse predicate-object pairs
      (while (and (< pos len)
                  (not (equal (nth pos tokens) ".")))
        (when (< (1+ pos) len) ; Need at least predicate and object
          (let ((predicate (nth pos tokens)))
            (setq pos (1+ pos))
            ;; Parse comma-separated objects for this predicate
            (while (and (< pos len)
                        (not (member (nth pos tokens) '(";" "."))))
              (let ((object (nth pos tokens)))
                (unless (equal object ",")
                  (push (list subject predicate object) triples))
                (setq pos (1+ pos))
                ;; Skip comma if present
                (when (and (< pos len) (equal (nth pos tokens) ","))
                  (setq pos (1+ pos)))))
            ;; Skip semicolon if present
            (when (and (< pos len) (equal (nth pos tokens) ";"))
              (setq pos (1+ pos))))))

      ;; Skip period if present
      (when (and (< pos len) (equal (nth pos tokens) "."))
        (setq pos (1+ pos))))

    (cons (nreverse triples) pos)))

(defun el-rdf--parse-ttl-content (graph content &optional namespace)
  "Parse TTL content string and add triples to GRAPH.
If NAMESPACE is provided, prefix all imported resources with it.
Properly handles semicolon syntax where multiple predicate-object pairs
can share the same subject, and periods terminate statements."
  ;; First pass: extract @prefix declarations using simple regex
  (let ((lines (split-string content "\n" t)))
    (dolist (line lines)
      (let ((line (string-trim line)))
        (when (string-prefix-p "@prefix" line)
          (when (string-match "@prefix\\s-+\\([^:]+\\):\\s-*<\\([^>]+\\)>" line)
            (let ((prefix (string-trim (match-string 1 line)))
                  (namespace-uri (match-string 2 line)))
              (el-rdf--register-prefix graph prefix namespace-uri)))))))

  ;; Second pass: parse triples using the new tokenizer
  (let* ((tokens (el-rdf--simple-tokenize-ttl content))
         (pos 0)
         (len (length tokens)))
    (while (< pos len)
      (let ((token (nth pos tokens)))
        (cond
         ;; Skip @prefix declarations
         ((equal token "@prefix")
          (while (and (< pos len) (not (equal (nth pos tokens) ".")))
            (setq pos (1+ pos)))
          (when (< pos len) (setq pos (1+ pos)))) ; Skip period
         ;; Skip comments
         ((and token (string-prefix-p "#" token))
          (setq pos (1+ pos)))
         ;; Parse statement
         (t
          (let ((result (el-rdf--parse-simple-ttl-statement tokens pos)))
            (let ((triples (car result))
                  (next-pos (cdr result)))
              (dolist (triple-tokens triples)
                (when (= (length triple-tokens) 3)
                  (let* ((subject-str (nth 0 triple-tokens))
                         (predicate-str (nth 1 triple-tokens))
                         (object-str (nth 2 triple-tokens)))
                    ;; Only process if this isn't a directive
                    (unless (string-prefix-p "@" subject-str)
                      (let* ((subject (el-rdf--parse-ttl-value graph subject-str namespace))
                             (predicate (el-rdf--parse-ttl-value graph predicate-str namespace))
                             (object (el-rdf--parse-ttl-value graph object-str namespace))
                             ;; Normalize rdf:type predicate
                             (predicate (if (and (symbolp predicate)
                                                 (string= (symbol-name predicate)
                                                          "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"))
                                            'rdf:type
                                          predicate)))
                        (add-triple (list subject predicate object) graph))))))
              (setq pos next-pos)))))))))

(defun import-ttl (filename graph &optional namespace)
  "Import TTL file FILENAME into GRAPH, expanding prefixes to symbols.
If NAMESPACE is provided, all imported resources will be prefixed with it.
For example, with NAMESPACE \"schema\", resources become schema:hasOccupation."
  (when (file-exists-p filename)
    (with-temp-buffer
      (insert-file-contents filename)
      (el-rdf--parse-ttl-content graph (buffer-string) namespace))
    (message "Imported TTL file: %s%s" filename
             (if namespace (format " with namespace %s" namespace) ""))
    graph))

(provide 'el-rdf)
;;; el-rdf.el ends here
