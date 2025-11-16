#!/bin/bash
# 016_adaptive_growth.sh - Test Adaptive Capacity Growth optimization

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "016"

test_section "016: Adaptive Capacity Growth"

# Test 1: Small arrays (< 4) - should grow to 4
test_start "Small array growth (<4)"
TList.new small
# Add 1 item - capacity should be 4
small.Add "item1"
# We check through direct property access
capacity_direct=$(small.capacity)

if (( capacity_direct >= 4 )); then
    test_pass "Small array grows to at least 4 (actual: $capacity_direct)"
else
    test_fail "Small array should have capacity >= 4, got $capacity_direct"
fi

# Test 2: Medium arrays (4-16) - should use 2x multiplier
test_start "Medium array growth (2x multiplier)"
TList.new medium
medium.Add "a"
medium.Add "b"
medium.Add "c"
medium.Add "d"
# At this point capacity should be 4
# Add one more to trigger growth - should grow to 8 (4 * 2)
medium.Add "e"
capacity_after_grow=$(medium.capacity)

if (( capacity_after_grow == 8 )); then
    test_pass "Medium array grows by 2x multiplier (4 -> 8, actual: $capacity_after_grow)"
else
    test_fail "Medium array should grow to 8, got $capacity_after_grow"
fi

# Test 3: Large arrays (>= 16) - should use 1.5x multiplier
test_start "Large array growth (1.5x multiplier)"
TList.new large
# Fill to exactly 16 items
for i in {1..16}; do
    large.Add "item$i"
done
capacity_at_16=$(large.capacity)

# Add one more to trigger growth from 16 - should grow to 24 (16 + 8)
large.Add "item17"
capacity_after_grow_large=$(large.capacity)

expected_capacity=$((16 + 16 / 2))  # 16 + 8 = 24
if (( capacity_after_grow_large == expected_capacity )); then
    test_pass "Large array grows by 1.5x multiplier (16 -> 24, actual: $capacity_after_grow_large)"
else
    test_fail "Large array should grow to $expected_capacity, got $capacity_after_grow_large"
fi

# Test 4: Verify no duplicate capacity management
test_start "Capacity consistency (no duplicate growth)"
TList.new consistency
for i in {1..100}; do
    consistency.Add "val$i"
done
final_capacity=$(consistency.capacity)
final_count=$(consistency.count)

if (( final_capacity >= final_count )); then
    test_pass "Capacity >= Count after 100 adds (capacity: $final_capacity, count: $final_count)"
else
    test_fail "Capacity should be >= Count, got capacity=$final_capacity, count=$final_count"
fi

# Test 5: Memory efficiency check
test_start "Memory efficiency (1.5x vs fixed +16)"
TList.new efficiency
# Add 100 items and check final capacity
for i in {1..100}; do
    efficiency.Add "item$i"
done
final_cap=$(efficiency.capacity)

# With 1.5x growth: 4 -> 6 -> 9 -> 13 -> 19 -> 28 -> 42 -> 63 -> 94 -> 141
# Should end up around 141
# With fixed +16: 4 -> 8 -> 24 -> 40 -> 56 -> 72 -> 88 -> 104 (would be much higher)
if (( final_cap <= 150 )); then
    test_pass "Final capacity efficient with 1.5x growth (100 items -> capacity: $final_cap)"
else
    test_fail "Final capacity seems too high for 100 items: $final_cap"
fi

# Test 6: Growth pattern verification
test_start "Growth pattern follows strategy"
TList.new pattern
# Start: capacity 0 -> Add 1 item -> capacity 4
pattern.Add "a"
c1=$(pattern.capacity)

# Capacity 4, count 1 -> Add 4 more (count 5) -> capacity 8 (4*2)
for i in {2..5}; do
    pattern.Add "item$i"
done
c2=$(pattern.capacity)

# Capacity 8, count 5 -> Add 8 more (count 13) -> grows to 16 (8*2)
# This is still <16 range, so uses 2x multiplier
for i in {6..13}; do
    pattern.Add "item$i"
done
c3=$(pattern.capacity)

# Capacity 16, count 13 -> Add 1 more (count 14) -> still fits
# -> Add 2 more (count 16) -> still fits
# -> Add 1 more (count 17) -> grows to 24 (16 + 8, 1.5x)
for i in {14..17}; do
    pattern.Add "item$i"
done
c4=$(pattern.capacity)

if (( c1 == 4 && c2 == 8 && c3 == 16 && c4 == 24 )); then
    test_pass "Growth pattern correct: 0->4, 4->8 (2x), 8->16 (2x), 16->24 (1.5x)"
else
    test_fail "Growth pattern incorrect: got $c1, $c2, $c3, $c4 (expected 4, 8, 16, 24)"
fi

# Cleanup
small.delete
medium.delete
large.delete
consistency.delete
efficiency.delete
pattern.delete

test_info "016_adaptive_growth.sh completed"
