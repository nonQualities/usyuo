# 04: Inverted Index & Query Complexity

## 1. The $O(K)$ Algorithmic Mandate

The SRS Non-Functional Requirements establish:
> *"Startup Phase: File ingestion and parsing must complete in $O(N)$ time, where $N$ is the total file size in bytes.*  
> *Temporal Queries: $O(K)$, where $K$ is the number of matching tasks, circumventing $O(N)$ date-string comparisons.*  
> *Tag Queries: $O(K)$ lookup via the inverted index."*

### Why Linear Scanning Fails at Scale
In a naive task engine with $M$ tasks:
* Finding tasks tagged with `@backend` requires iterating through all $M$ tasks and checking every tag on every task ($O(M)$ time).
* Finding tasks due today requires iterating through all $M$ tasks ($O(M)$ time).

When datasets grow to tens or hundreds of thousands of tasks (e.g. archived project histories), linear scans introduce noticeable latency in the interactive REPL. An indexing engine circumvents this by paying a small, one-time $O(1)$ indexing cost during insertion to enable $O(K)$ lookups, where $K$ is strictly the count of matching items ($K \ll M$).

---

## 2. Inverted Tag Index with `PostingNode` Lists

An **Inverted Index** maps distinct tokens (contexts `@Context`, projects `+Project`, metadata `key:value`) to matching tasks.

Rather than allocating a dynamically resizing array (`List{Task*}`) for every unique tag, the engine uses **arena-backed singly linked posting lists**:

```
[Inverted Index: HashMap{String, PostingNode*}]
Key (String slice)   -> Head Pointer (PostingNode*)
------------------------------------------------------------------
"@backend"           -> [ Node: task_id=9 ] -> [ Node: task_id=3 ] -> [ Node: task_id=1 ] -> null
"+c3engine"          -> [ Node: task_id=1 ] -> null
"+docs"              -> [ Node: task_id=8 ] -> [ Node: task_id=6 ] -> null
```

### Why Arena-Backed `PostingNode` Lists are Superior:
1. **$O(1)$ Prepend Insertion**: Inserting a new task ID into an existing tag's posting list is a simple head-pointer swap:
   ```c3
   PostingNode* node = (PostingNode*)arena.alloc_bytes(PostingNode::size);
   node.task_id = task_id;
   node.next = self.map.get(tag) ?? null;
   self.map[tag] = node;
   ```
2. **Zero Heap Reallocations**: No dynamic array growth (`realloc`), buffer copying, or capacity over-allocation.
3. **Zero Heap Fragmentation**: All posting nodes are bump-allocated sequentially in the workspace arena.
4. **$O(K)$ Traversal**: The query engine simply walks the pointer chain `node = node.next`, visiting all $K$ matching tasks without examining non-matching tasks.

---

## 3. Temporal Index Architecture

To achieve $O(K)$ temporal lookups for queries such as `today` without scanning all tasks, the engine maintains a `TemporalIndex` mapping integer Julian Day Numbers directly to posting lists of task IDs:

```
[Temporal Index: HashMap{int, PostingNode*}]
Key (int JDN)        -> Head Pointer (PostingNode*)
------------------------------------------------------------------
2461297 (2026-09-13) -> [ Node: task_id=8 ] -> [ Node: task_id=1 ] -> null
2461298 (2026-09-14) -> [ Node: task_id=2 ] -> null
2461299 (2026-09-15) -> [ Node: task_id=4 ] -> null
```

### Querying "Today":
1. Calculate today's system JDN (e.g. `2461297`).
2. Query `temporal_index.lookup(2461297)`.
3. In $O(1)$ average time, the hash table locates the head `PostingNode*`.
4. The REPL directly traverses the $K$ nodes and renders matching tasks from `tasks[node.task_id - 1]`. Time complexity: strictly $O(K)$.

---

## 4. Complexity Comparison Matrix

Let $M$ = total tasks in workspace, $K$ = matching tasks ($K \ll M$).

| Operation | Naive Scanner | usyuo Indexed Engine | Advantage |
| :--- | :--- | :--- | :--- |
| **Startup Ingestion** | $O(N)$ byte scan | $O(N)$ byte scan + index population | Identical asymptotic order |
| **Query `today`** | $O(M)$ linear scan | $O(1)$ lookup + $O(K)$ rendering | Orders of magnitude faster |
| **Query Tag (`@work`)** | $O(M \times T)$ token comparisons | $O(1)$ lookup + $O(K)$ rendering | Instant response |
| **Insert Task (`add`)** | $O(1)$ append | $O(1)$ arena append + $O(1)$ posting prepend | Bounded insertion time |
| **Memory Footprint** | Dynamic strings + headers | Arena buffer + 16B posting nodes | Minimal cache overhead |
