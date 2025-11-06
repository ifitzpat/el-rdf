# Threading in cl-rdf

## Overview

cl-rdf uses **implementation-specific threading** to maximize performance while maintaining portability:

- **SBCL**: Parallel processing with `bordeaux-threads` for large datasets
- **ECL**: Sequential processing (no threading overhead)

This approach provides the best of both worlds:
- Fast parallel processing on SBCL (desktop/server)
- Portable sequential code on ECL (mobile: Android/iOS)

## Implementation

### Generic Functions

All core CRUD operations are implemented as **CLOS generic functions** to support multiple graph backends:

```lisp
(defgeneric add-triple (triple graph))
(defgeneric delete-triple (triple graph))
(defgeneric add-triples (triples graph))
(defgeneric delete-triples (triples graph))
```

### Reader Conditionals

Methods are specialized per implementation using reader conditionals:

```lisp
#+sbcl
(defmethod add-triple (triple (graph local-graph))
  ;; Thread-safe with mutex
  (with-lock-held ((graph-lock graph))
    ...))

#+ecl
(defmethod add-triple (triple (graph local-graph))
  ;; Simple direct updates
  ...)
```

## Performance Thresholds

### SBCL Parallel Processing

**Threshold**: 100+ items

When processing **100 or more items**, SBCL uses parallel processing:
- `add-triples` / `delete-triples`: 100+ triples → 4 threads
- `expand-duals`: 100+ alist entries → 4 threads

**Thread count**: `min(cpu-count, 4)` - capped at 4 threads for efficiency

**Why 100?**
- Threading overhead is significant for small datasets
- 100 items is the sweet spot where parallelization provides clear benefit
- Prevents over-threading on small operations

### ECL Sequential Processing

ECL always uses **sequential processing** regardless of dataset size:
- No threading overhead
- No locking overhead
- Simpler, more predictable behavior
- Better suited for resource-constrained mobile platforms

## Thread Safety

### SBCL

Each `local-graph` has a **mutex** (lock slot):

```lisp
#+sbcl
(lock :initform (make-lock "graph-lock")
      :reader graph-lock)
```

All graph modifications are protected:
- `add-triple` / `delete-triple` wrap operations in `(with-lock-held ...)`
- Parallel `add-triples` / `delete-triples` call thread-safe single-triple operations
- Multiple threads can safely modify the same graph

### ECL

No locks needed - sequential execution guarantees safety.

## Mobile Considerations (ECL on Android/iOS)

Threading on mobile platforms has significant drawbacks:

1. **Limited threads** - Mobile OSes restrict thread count
2. **Battery drain** - Threading increases power consumption
3. **Memory pressure** - Each thread has memory overhead
4. **GC issues** - ECL's GC with threading can cause problems

**Solution**: ECL uses sequential processing, which is:
- More battery-efficient
- More memory-efficient
- More stable on mobile
- Still fast enough for typical mobile use cases

## Dependencies

### SBCL

```lisp
:depends-on (#:bordeaux-threads  ; Threading support
             ...)
```

### ECL

```lisp
:depends-on (;; No threading library needed
             ...)
```

The conditional dependency in `cl-rdf.asd`:

```lisp
#+sbcl #:bordeaux-threads  ; Only on SBCL
```

## Testing

CI tests run on **both implementations**:

```yaml
matrix:
  lisp:
    - sbcl  # Tests threading code
    - ecl   # Tests sequential code
```

This ensures:
- SBCL threading works correctly
- ECL sequential code works correctly
- Both produce identical results
- No regressions in either implementation

## Future Work

Possible enhancements:

1. **Tunable thresholds**: Allow users to configure the 100-item threshold
2. **More implementations**: Add CCL, ABCL support with appropriate threading strategies
3. **Adaptive threading**: Dynamically adjust thread count based on system load
4. **Mobile flag**: Explicit `:mobile t` flag to disable threading even on SBCL

## Summary

| Feature | SBCL | ECL |
|---------|------|-----|
| Generics | ✅ Yes | ✅ Yes |
| Threading | ✅ Yes (100+ items) | ❌ No |
| Locking | ✅ Yes | ❌ No overhead |
| Thread count | 4 max | N/A |
| Use case | Desktop/Server | Mobile/Embedded |
| Performance | **Fastest** for large data | **Most efficient** overall |

Both implementations pass the same test suite and produce identical results.
