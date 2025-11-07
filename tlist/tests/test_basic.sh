#!/bin/bash

# Basic test for TList functionality

# Source the TList class
source "../../kklass/kklass.sh"
source "$PWD/../tlist.sh"

echo "Testing TList basic functionality..."

# Create a TList instance
echo "Creating TList instance..."
TList.new mylist
echo "Instance created"

# Check initial state
echo "Initial count: $(mylist.Count)"
echo "Initial capacity: $(mylist.Capacity)"

# Test Add
echo "Testing Add method..."
index=$(mylist.Add "item1")
echo "Added item1 at index: $index"
echo "Count after first add: $(mylist.Count)"

index=$(mylist.Add "item2")
echo "Added item2 at index: $index"
echo "Count after second add: $(mylist.Count)"

index=$(mylist.Add "item3")
echo "Added item3 at index: $index"
echo "Count after third add: $(mylist.Count)"

# Debug: check what happens to count
echo "Count after adding: $(mylist.Count)"
echo "Capacity after adding: $(mylist.Capacity)"

# Test First/Last
first=$(mylist.First)
echo "First item: $first"

last=$(mylist.Last)
echo "Last item: $last"

# Test Insert
echo "Testing Insert..."
mylist.Insert 1 "inserted"
count=$(mylist.Count)
echo "Count after insert: $count"

# Test Delete
echo "Testing Delete..."
mylist.Delete 1
count=$(mylist.Count)
echo "Count after delete: $count"

# Test Clear
echo "Testing Clear..."
mylist.Clear
count=$(mylist.Count)
capacity=$(mylist.Capacity)
echo "Count after clear: $count, Capacity: $capacity"

echo "Basic TList tests completed successfully!"
