#!/bin/bash

# Basic test for TStringList functionality

# Source the classes
source "../tstringlist.sh"

echo "Testing TStringList basic functionality..."

# Create a TStringList instance
TStringList.new mylist

# Test Add
echo "Testing Add method..."
index=$(mylist.Add "hello")
echo "Added 'hello' at index: $index"

index=$(mylist.Add "world")
echo "Added 'world' at index: $index"

# Test Count
count=$(mylist.Count)
echo "List count: $count"

# Test Get
item=$(mylist.Get 0)
echo "Item at 0: $item"

item=$(mylist.Get 1)
echo "Item at 1: $item"

# Test IndexOf
index=$(mylist.IndexOf "hello")
echo "Index of 'hello': $index"

index=$(mylist.IndexOf "world")
echo "Index of 'world': $index"

index=$(mylist.IndexOf "notfound")
echo "Index of 'notfound': $index"

# Test CaseSensitive
echo "Testing case sensitivity..."
mylist.case_sensitive = false
index=$(mylist.IndexOf "HELLO")
echo "Index of 'HELLO' (case insensitive): $index"

mylist.case_sensitive = true
index=$(mylist.IndexOf "HELLO")
echo "Index of 'HELLO' (case sensitive): $index"

echo "TStringList basic tests completed!"
