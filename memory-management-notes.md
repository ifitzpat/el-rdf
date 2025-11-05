# Memory Management Notes for cl-rdf

This document discusses memory management strategies for cl-rdf graphs, particularly relevant for remote graphs and large datasets.

## Context

cl-rdf loads everything into RAM with disk checkpointing. For large graphs or many graphs, this can be wasteful of memory. This document explores Common Lisp's memory management capabilities and strategies for better memory efficiency.

## Common Lisp Memory Management Features

### 1. Garbage Collection (Automatic)

**What CL provides:**
- Automatic generational GC (SBCL, CCL)
- Objects become eligible for GC when unreachable
- Implementation-specific GC tuning

**The problem:**
```lisp
;; Even after this, memory may not return to OS
(setf *graph* nil)  ; Removes reference
(sb-ext:gc :full t) ; Forces GC
;; → Memory reclaimed from Lisp's perspective
;; → But heap stays large, OS doesn't get it back
```

**CL implementations tend to:**
- Grow heaps aggressively
- Rarely shrink heaps or return memory to OS
- Keep memory for future allocations (performance trade-off)

### 2. Explicit Memory Control (Limited)

**What you CAN do:**
```lisp
;; Clear hash table contents (makes data GC-eligible)
(clrhash (graph-spo graph))
(clrhash (graph-osp graph))
(clrhash (graph-pos graph))

;; Trigger GC
#+sbcl (sb-ext:gc :full t)

;; Inspect memory usage
#+sbcl (room t)
```

**What you CANNOT easily do:**
- Force heap to shrink
- Return specific memory ranges to OS
- Manual malloc/free like C

### 3. Implementation-Specific Features

#### SBCL:
```lisp
;; Weak pointers (value can be GC'd)
(sb-ext:make-weak-pointer object)

;; Weak hash tables
(make-hash-table :weakness :key)    ; Keys can be GC'd
(make-hash-table :weakness :value)  ; Values can be GC'd

;; Memory-mapped files
(sb-posix:mmap ...)

;; Heap size limits
--dynamic-space-size 4096  ; MB limit
```

#### CCL:
```lisp
(ccl:gc)
(ccl:room)
(make-hash-table :weak :key)
```

## Strategies for cl-rdf Memory Management

### Strategy 1: Graph Lifecycle Management (Easy - RECOMMENDED)

**Implement explicit unload/reload:**

```lisp
(defun clear-graph (graph)
  "Clear all triples from GRAPH, freeing memory.

  This makes the triple data eligible for garbage collection,
  but doesn't force the OS to reclaim memory immediately."
  (clrhash (graph-spo graph))
  (clrhash (graph-osp graph))
  (clrhash (graph-pos graph))

  ;; Clear hooks (break circular references)
  (setf (graph-add-hooks graph) nil)
  (setf (graph-delete-hooks graph) nil)
  (setf (graph-query-hooks graph) nil)

  ;; Suggest GC
  #+sbcl (sb-ext:gc)
  #+ccl (ccl:gc))

(defun unload-graph (graph &optional checkpoint-path)
  "Save GRAPH to disk and free memory.

  Returns checkpoint path for later reloading.

  Example:
    (unload-graph *graph* \"/data/graph.checkpoint\")
    ;; ... do other work ...
    (reload-graph *graph* \"/data/graph.checkpoint\")"
  (let ((path (or checkpoint-path
                  (checkpoint-file-path (graph-name graph)))))
    ;; Save to disk
    (save-graph graph path)

    ;; Clear from memory
    (clear-graph graph)

    path))

(defun reload-graph (graph checkpoint-path)
  "Reload GRAPH from disk checkpoint.

  Example:
    (reload-graph *graph* \"/data/graph.checkpoint\")"
  (load-graph graph checkpoint-path))
```

**Usage:**
```lisp
;; Work with graph
(add-triples lots-of-data *graph*)
(query-graph ...)

;; Done for now, free memory
(unload-graph *graph* "/tmp/graph.checkpoint")

;; Memory is now available for other work

;; Later, need it again
(reload-graph *graph* "/tmp/graph.checkpoint")
```

**Pros:**
- ✅ Simple to implement
- ✅ Explicit control over memory
- ✅ Works with existing checkpoint system
- ✅ No additional dependencies

**Cons:**
- ❌ Manual - user must call unload/reload
- ❌ Full graph must be reloaded (no partial loading)
- ❌ I/O cost for unload/reload cycle

### Strategy 2: Lazy-Loading Graph (Medium Complexity)

**Implement on-demand loading:**

```lisp
(defclass lazy-graph (graph)
  ((backing-file :initarg :file
                 :accessor graph-backing-file
                 :documentation "Path to checkpoint file on disk")
   (loaded-p :initform nil
             :accessor graph-loaded-p
             :documentation "T if graph is currently loaded in memory")
   (spo :initform nil)  ; Starts empty
   (osp :initform nil)
   (pos :initform nil))
  (:documentation "Graph that loads from disk on first access.

  The graph stays on disk until a method requires it, then
  automatically loads. Useful when managing many graphs where
  only a subset are actively used.

  Example:
    (defvar *lazy* (make-instance 'lazy-graph
                                  :file \"/data/big-graph.rdf\"))
    ;; Graph not loaded yet
    (triples '(alice t t) *lazy*)
    ;; Now loaded automatically"))

(defmethod triples :before (pattern (graph lazy-graph))
  "Ensure graph is loaded before querying."
  (unless (graph-loaded-p graph)
    (load-graph graph (graph-backing-file graph))
    (setf (graph-loaded-p graph) t)))

(defmethod add-triple :before (triple (graph lazy-graph))
  "Ensure graph is loaded before adding."
  (unless (graph-loaded-p graph)
    (load-graph graph (graph-backing-file graph))
    (setf (graph-loaded-p graph) t)))

;; Similar :before methods for delete-triple, graph-query, etc.

(defun unload-lazy-graph (graph)
  "Unload a lazy-graph from memory (saves to backing file first)."
  (when (graph-loaded-p graph)
    (save-graph graph (graph-backing-file graph))
    (clear-graph graph)
    (setf (graph-loaded-p graph) nil)))
```

**Benefits:**
- Graphs stay on disk until accessed
- Multiple graphs, only active ones in memory
- Transparent to users (automatic loading)
- Can explicitly unload when memory pressure increases

**Use case:**
```lisp
;; Managing 50 graphs, but only using 3 at a time
(defvar *graphs*
  (loop for i from 1 to 50
        collect (make-instance 'lazy-graph
                              :file (format nil "/data/graph-~A.rdf" i))))

;; Only accessed graphs are loaded
(triples '(t t t) (nth 5 *graphs*))   ; Loads graph 5
(triples '(t t t) (nth 12 *graphs*))  ; Loads graph 12
;; Other 48 graphs still on disk
```

### Strategy 3: Partitioned Graphs (Higher Complexity)

**Split large graphs by namespace or subject prefix:**

```lisp
(defclass partitioned-graph (graph)
  ((partitions :initform (make-hash-table :test 'eq)
               :accessor graph-partitions
               :documentation "namespace -> local-graph")
   (loaded-partitions :initform nil
                      :accessor graph-loaded-partitions
                      :documentation "List of currently loaded namespaces")
   (max-loaded-partitions :initarg :max-loaded
                          :initform 5
                          :accessor graph-max-loaded-partitions
                          :documentation "Maximum partitions in memory"))
  (:documentation "Graph split into namespace-based partitions.

  Each namespace (e.g., foaf@, schema@, dbpedia@) is a separate
  partition stored on disk. Partitions are loaded on-demand and
  evicted using LRU policy when memory pressure increases.

  Example:
    ;; Large knowledge base split by domain
    foaf:*    → partition-foaf.rdf
    schema:*  → partition-schema.rdf
    dbpedia:* → partition-dbpedia.rdf

    ;; Only load partitions as queries need them
    (triples '($s foaf@name $n) *kb*)  ; Loads foaf partition only"))

(defmethod triples (pattern (graph partitioned-graph))
  "Query across partitions, loading as needed."
  (let ((required-ns (infer-namespace-from-pattern pattern)))
    ;; Load partition if not already loaded
    (ensure-partition-loaded graph required-ns)

    ;; Query the partition
    (let ((partition (gethash required-ns (graph-partitions graph))))
      (triples pattern partition))))

(defun infer-namespace-from-pattern (pattern)
  "Extract namespace from pattern elements.

  Examples:
    (foaf@name t t) => foaf
    (t schema@birthDate t) => schema"
  (dolist (elem pattern)
    (when (and (symbolp elem) (not (var-or-wildp elem)))
      (let ((name (symbol-name elem)))
        (let ((pos (position #\@ name)))
          (when pos
            (return-from infer-namespace-from-pattern
              (intern (subseq name 0 pos)))))))))

(defun ensure-partition-loaded (graph namespace)
  "Load partition for NAMESPACE if not already in memory.

  Uses LRU policy to unload cold partitions when max is reached."
  (unless (member namespace (graph-loaded-partitions graph))
    ;; Check memory pressure, unload LRU partition if needed
    (when (>= (length (graph-loaded-partitions graph))
              (graph-max-loaded-partitions graph))
      (unload-lru-partition graph))

    ;; Load requested partition
    (load-partition graph namespace)
    (push namespace (graph-loaded-partitions graph))))

(defun unload-lru-partition (graph)
  "Unload least-recently-used partition."
  (let ((lru (car (last (graph-loaded-partitions graph)))))
    (save-partition graph lru)
    (remhash lru (graph-partitions graph))
    (setf (graph-loaded-partitions graph)
          (remove lru (graph-loaded-partitions graph)))))

(defun load-partition (graph namespace)
  "Load partition from disk."
  (let ((partition (make-graph))
        (path (partition-file-path graph namespace)))
    (load-graph partition path)
    (setf (gethash namespace (graph-partitions graph)) partition)))

(defun save-partition (graph namespace)
  "Save partition to disk."
  (let ((partition (gethash namespace (graph-partitions graph)))
        (path (partition-file-path graph namespace)))
    (save-graph partition path)))
```

**Pros:**
- ✅ Fine-grained memory control
- ✅ Automatic LRU eviction
- ✅ Can handle very large graphs
- ✅ Good for multi-domain knowledge bases

**Cons:**
- ❌ Complex implementation
- ❌ Requires partitioning strategy
- ❌ Queries spanning namespaces may need multiple partitions
- ❌ More disk I/O

### Strategy 4: External Storage Backend (Most Complex)

**Implement graph protocol over persistent storage (SQLite, LMDB, RocksDB):**

```lisp
(defclass sqlite-graph (graph)
  ((db-path :initarg :path
            :accessor graph-db-path
            :documentation "Path to SQLite database file")
   (db-connection :initform nil
                  :accessor graph-db-connection)
   (cache :initform (make-lru-cache :size 10000)
          :accessor graph-cache
          :documentation "LRU cache for hot triples"))
  (:documentation "Graph stored in SQLite, queried on demand.

  All triples stored in SQLite database with indices on S, P, O.
  Queries hit the database directly with optional LRU caching.

  Pros:
    - Minimal memory footprint (only cache in RAM)
    - Can handle graphs larger than RAM
    - ACID transactions
    - Concurrent access (with appropriate locking)

  Cons:
    - Slower queries (disk I/O)
    - Adds external dependency
    - More complex setup

  Example:
    (defvar *big* (make-instance 'sqlite-graph
                                 :path \"/data/huge-graph.db\"))
    (triples '(alice t t) *big*)  ; Query hits SQLite"))

(defmethod triples (pattern (graph sqlite-graph))
  "Query SQLite database, cache results."
  (or (check-cache graph pattern)
      (let ((results (query-sqlite graph pattern)))
        (cache-results graph pattern results)
        results)))

(defun query-sqlite (graph pattern)
  "Execute SQL query for pattern."
  (destructuring-bind (s p o) pattern
    (let ((sql (build-query-sql s p o)))
      (execute-sql (graph-db-connection graph) sql))))

;; Schema:
;; CREATE TABLE triples (
;;   subject TEXT NOT NULL,
;;   predicate TEXT NOT NULL,
;;   object TEXT NOT NULL
;; );
;; CREATE INDEX idx_spo ON triples(subject, predicate, object);
;; CREATE INDEX idx_pos ON triples(predicate, object, subject);
;; CREATE INDEX idx_osp ON triples(object, subject, predicate);
```

**Trade-offs:**
- ✅ Minimal memory footprint
- ✅ Can handle graphs larger than RAM
- ✅ ACID properties
- ✅ Proven technology
- ❌ Slower queries (disk I/O)
- ❌ Adds external dependency
- ❌ More setup complexity

**When to use:**
- Graphs that truly won't fit in RAM
- Need ACID transactions
- Multiple processes accessing same graph
- Long-term persistence more important than speed

### Strategy 5: Aggressive Content References (Already Partially Implemented!)

**Lower the threshold for externalizing data:**

cl-rdf already has content reference system (`el-rdf-max-string-length`). This can be tuned for more aggressive externalization.

```lisp
;; Current default: 1000 chars → file reference
(defparameter *el-rdf-max-string-length* 1000)

;; More aggressive: 100 chars
(setf *el-rdf-max-string-length* 100)

;; Externalize all literals:
(setf *el-rdf-max-string-length* 0)

;; Or use compression for external storage:
(defun store-compressed-content (content)
  "Store content compressed on disk."
  (let ((hash (content-hash content))
        (compressed (chipz:compress 'chipz:gzip
                                    (babel:string-to-octets content))))
    (store-to-file compressed hash)
    (format nil "file:content-~A.gz" hash)))
```

**Benefits:**
- ✅ Already implemented infrastructure
- ✅ Just tune parameters
- ✅ Transparent to queries (automatic resolution)
- ✅ Deduplicates repeated content

**When to tune:**
- Many large literal values (descriptions, documents, etc.)
- Memory pressure from object storage
- Want to keep indices in memory but externalize data

### Strategy 6: Weak-Referenced Query Cache

**Cache query results without preventing GC:**

```lisp
(defclass cached-graph (graph)
  ((delegate :initarg :delegate
             :accessor graph-delegate
             :documentation "Underlying graph")
   (query-cache :initform (make-hash-table :test 'equal
                                            #+sbcl :weakness #+sbcl :value)
                :accessor graph-query-cache
                :documentation "Weak-referenced query result cache"))
  (:documentation "Graph wrapper with weak-referenced cache.

  Caches query results for performance, but uses weak references
  so cached results can be GC'd under memory pressure.

  Example:
    (defvar *cached* (make-instance 'cached-graph
                                    :delegate *original-graph*))
    (triples '(alice t t) *cached*)  ; Query and cache
    (triples '(alice t t) *cached*)  ; Served from cache
    ;; Under memory pressure, cache entries can be GC'd"))

(defmethod triples (pattern (graph cached-graph))
  "Query with caching; results can be GC'd under memory pressure."
  (or (gethash pattern (graph-query-cache graph))
      (let ((results (triples pattern (graph-delegate graph))))
        (setf (gethash pattern (graph-query-cache graph)) results)
        results)))
```

**Benefits:**
- ✅ Cache speeds up repeated queries
- ✅ Weak references allow GC under pressure
- ✅ Automatic memory management
- ✅ No manual cache invalidation needed

**Limitations:**
- Only on SBCL/CCL (implementation-specific)
- Cache behavior is non-deterministic
- May not work as expected with conservative GC

## The Hard Truth About CL Memory Management

**You cannot reliably force Common Lisp to return memory to the OS.**

This is by design - CL runtimes prioritize:

1. **Performance** - Keeping allocated memory avoids future allocation overhead
2. **GC efficiency** - Large heaps reduce GC frequency (generational GC works better)
3. **Simplicity** - Automatic memory management abstracts OS interaction

### Why CL Doesn't Return Memory

```lisp
;; Starting with 100MB heap
(defvar *big-data* (make-array 100000000))  ; Allocates, heap grows to 500MB

;; Clear reference and force GC
(setf *big-data* nil)
(sb-ext:gc :full t)

;; Data is collected, but heap still 500MB!
;; CL keeps it for future allocations
```

The heap is a **high-water mark** - it grows but rarely shrinks.

### Workarounds

1. **Run multiple CL processes** (each with bounded heap)
   ```bash
   sbcl --dynamic-space-size 2048  # Max 2GB heap
   ```

2. **Use external storage** for cold data (SQLite, LMDB)

3. **Accept that CL will hold memory** once allocated

4. **Restart process periodically** if needed (e.g., in containers)
   ```bash
   # Container with memory limit
   docker run --memory=4g my-cl-rdf-server
   # CL process killed if exceeds 4GB
   ```

5. **Profile and optimize** data structures themselves
   ```lisp
   ;; Better: specialized data structure
   (make-array 1000 :element-type '(unsigned-byte 8))

   ;; Worse: generic array
   (make-array 1000)  ; Each element is a pointer
   ```

## Practical Recommendations for cl-rdf

### Immediate (Easy Wins)

1. **Implement `clear-graph` and `unload-graph` functions**
   - Easy to implement
   - Gives users explicit control
   - Works with existing checkpoint system

2. **Tune content reference threshold**
   - Already implemented!
   - Just adjust `*el-rdf-max-string-length*`
   - Consider per-graph tuning

3. **Document memory behavior**
   - Explain CL memory characteristics
   - Provide guidance on when to unload graphs
   - Show container memory limit patterns

### Medium Term (If Needed)

4. **Implement `lazy-graph` class**
   - For managing many graphs
   - Automatic load-on-demand
   - Explicit unload when needed

5. **Add memory profiling utilities**
   ```lisp
   (defun graph-memory-usage (graph)
     "Estimate memory usage of GRAPH in bytes."
     (+ (hash-table-size (graph-spo graph))
        (hash-table-size (graph-osp graph))
        (hash-table-size (graph-pos graph))))

   (defun list-graphs-by-memory ()
     "List all named graphs sorted by memory usage."
     ...)
   ```

### Long Term (If Needed)

6. **Partitioned graphs** for very large datasets

7. **External storage backend** (SQLite/LMDB) for graphs exceeding RAM

8. **Compressed external storage** for content references

## Memory Management for Remote Graphs

For remote graphs specifically:

### Server Side (cl-rdf HTTP server)

```lisp
;; Unload rarely-accessed graphs
(defun cleanup-idle-graphs ()
  "Unload graphs not accessed in last hour."
  (loop for (name . graph) in (list-registered-graphs)
        when (> (- (get-universal-time)
                   (graph-last-access-time graph))
                3600)
        do (unload-graph graph)
           (log:info "Unloaded idle graph: ~A" name)))

;; Periodic cleanup
(bt:make-thread
  (lambda ()
    (loop
      (sleep 600)  ; Every 10 minutes
      (cleanup-idle-graphs)))
  :name "graph-cleanup")
```

### Client Side (remote-graph)

```lisp
;; Client doesn't need to worry about server memory
;; But can cache results locally:

(defclass caching-remote-graph (remote-graph)
  ((local-cache :initform (make-instance 'lazy-graph
                                         :file "/tmp/cache.rdf")
                :accessor remote-graph-cache))
  (:documentation "Remote graph with local caching.

  Queries hit remote server but cache results locally.
  Reduces network traffic for repeated queries."))

(defmethod triples :around (pattern (graph caching-remote-graph))
  "Check local cache before hitting remote server."
  (or (triples pattern (remote-graph-cache graph))
      (let ((results (call-next-method)))
        ;; Cache locally
        (add-triples results (remote-graph-cache graph))
        results)))
```

## Testing Memory Management

### Utilities for Testing

```lisp
(defun stress-test-memory (graph-count triple-count)
  "Create many graphs, monitor memory."
  (let ((graphs nil))
    (dotimes (i graph-count)
      (let ((g (make-graph)))
        (add-triples (generate-random-triples triple-count) g)
        (push g graphs)
        (format t "Graph ~A: ~A MB~%"
                i
                (/ (sb-ext:dynamic-space-size) 1024 1024))))

    ;; Force GC and check
    (setf graphs nil)
    (sb-ext:gc :full t)
    (format t "After GC: ~A MB~%"
            (/ (sb-ext:dynamic-space-size) 1024 1024))))

(defun profile-graph-operations ()
  "Profile memory usage of graph operations."
  #+sbcl
  (sb-ext:gc :full t)
  (let ((before (sb-ext:dynamic-space-size)))
    ;; Do operations
    (let ((g (make-graph)))
      (add-triples (generate-random-triples 100000) g)
      (sb-ext:gc :full t)
      (let ((after (sb-ext:dynamic-space-size)))
        (format t "Added ~A triples: ~A MB increase~%"
                100000
                (/ (- after before) 1024 1024))))))
```

## References and Further Reading

- [SBCL User Manual: Efficiency](http://www.sbcl.org/manual/#Efficiency)
- [Practical Common Lisp: Collections](http://www.gigamonkeys.com/book/collections.html)
- [Memory Management in Lisp (Paper)](https://dl.acm.org/doi/10.1145/800055.802017)
- CLiki: [Garbage Collection](https://www.cliki.net/garbage%20collection)
- [SBCL Internals: Memory Management](http://sbcl.org/sbcl-internals/Memory-Management.html)

## Summary

**Key Takeaways:**

1. **CL won't return memory to OS** - by design, for performance
2. **You CAN make data GC-eligible** - `clrhash`, unreference objects
3. **Best strategy: Explicit lifecycle management** - `unload-graph`, `reload-graph`
4. **Already have infrastructure** - content references, checkpointing
5. **More complex strategies available** - lazy loading, partitioning, external storage
6. **Choose based on use case:**
   - Small graphs (< 1GB): No special handling needed
   - Medium graphs (1-10GB): Explicit unload/reload
   - Large graphs (> 10GB): Partitioning or external storage
   - Many graphs: Lazy loading with LRU eviction

**Recommended Implementation Priority:**

1. ✅ **Now**: `clear-graph`, `unload-graph`, `reload-graph` (easy win)
2. ⏳ **Soon**: Tune content reference threshold
3. 🔮 **Later**: `lazy-graph` if managing many graphs
4. 🔮 **Future**: External storage if exceeding RAM

The good news: cl-rdf already has most of the infrastructure (checkpointing, content references). Just need to expose explicit lifecycle controls and tune parameters!
