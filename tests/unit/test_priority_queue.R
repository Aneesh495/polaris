# Unit Tests: Priority Queue (Binary Heap, D-ary Heap, Indexed Decrease-Key)

# Test 1: Basic Push and Pop in sorted order
pq <- polaris_indexed_pq(initial_capacity = 16L)
assert_true(pq$is_empty(), "Queue must initially be empty")

items <- c("node_c" = 30.0, "node_a" = 10.0, "node_d" = 40.0, "node_b" = 20.0)
for (nm in names(items)) {
  pq$push(nm, items[[nm]])
}

assert_equal(pq$length(), 4L, "Queue length must be 4")
assert_equal(pq$peek()$element, "node_a", "Min element must be node_a")
assert_equal(pq$peek()$priority, 10.0, "Min priority must be 10.0")

p1 <- pq$pop()
assert_equal(p1$element, "node_a", "First popped must be node_a")
p2 <- pq$pop()
assert_equal(p2$element, "node_b", "Second popped must be node_b")
p3 <- pq$pop()
assert_equal(p3$element, "node_c", "Third popped must be node_c")
p4 <- pq$pop()
assert_equal(p4$element, "node_d", "Fourth popped must be node_d")
assert_true(pq$is_empty(), "Queue must be empty after popping all")

# Test 2: Addressable Decrease-Key
pq2 <- polaris_indexed_pq(initial_capacity = 16L)
pq2$push("u", 100.0)
pq2$push("v", 200.0)
pq2$push("w", 300.0)

pq2$decrease_key("w", 50.0) # w becomes the minimum
assert_equal(pq2$peek()$element, "w", "w must become min after decrease-key to 50.0")
assert_equal(pq2$peek()$priority, 50.0, "w priority must be 50.0")

# Re-insert with lower priority triggers decrease_key automatically
pq2$push("v", 25.0) # v becomes new minimum
assert_equal(pq2$peek()$element, "v", "v must become min after push with lower priority")

# Test 3: Structural Invariant Verification across 200 elements
pq_stress <- polaris_indexed_pq(initial_capacity = 32L)
set.seed(42)
random_prios <- runif(200, 1.0, 1000.0)
for (i in 1:200) {
  pq_stress$push(paste0("e_", i), random_prios[i])
}
assert_true(pq_verify_invariants(pq_stress), "Heap structural invariants must hold after 200 pushes")

# Perform decrease-keys
for (i in 1:50) {
  elem <- paste0("e_", i)
  pq_stress$decrease_key(elem, runif(1, 0.1, 0.9))
}
assert_true(pq_verify_invariants(pq_stress), "Heap invariants must hold after 50 decrease-keys")

# Pop all and ensure monotonic non-decreasing order
prev_prio <- -1.0
while (!pq_stress$is_empty()) {
  item <- pq_stress$pop()
  assert_true(item$priority >= prev_prio, "Extracted priorities must be monotonically non-decreasing")
  prev_prio <- item$priority
}

# Test 4: 4-Ary (D-Ary) Priority Queue
d_pq <- polaris_dary_pq(d = 4L, initial_capacity = 16L)
for (nm in names(items)) {
  d_pq$push(nm, items[[nm]])
}
assert_equal(d_pq$pop()$element, "node_a", "D-ary first popped is node_a")
assert_equal(d_pq$pop()$element, "node_b", "D-ary second popped is node_b")
d_pq$decrease_key("node_d", 5.0)
assert_equal(d_pq$pop()$element, "node_d", "D-ary decrease_key popped node_d")
assert_equal(d_pq$pop()$element, "node_c", "D-ary last popped is node_c")
