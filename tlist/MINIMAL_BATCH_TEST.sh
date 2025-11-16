#!/bin/bash
# Minimal test without test framework dependencies

source ../../kklass/kklass.sh
source ../../kklass/kklib.sh
source tlist.sh

echo "=== Test 1: BatchInsert at beginning ==="
TList.new mylist
mylist.Add "item4"
mylist.Add "item5"
mylist.Add "item6"
echo "Initial: count=$(mylist.count), capacity=$(mylist.capacity)"

echo "Calling BatchInsert 0 item0 item1 item2 item3"
mylist.BatchInsert 0 "item0" "item1" "item2" "item3"
echo "After: count=$(mylist.count), capacity=$(mylist.capacity)"

items_var="mylist_items"
declare -n items_ref="$items_var"
echo "Items: ${items_ref[@]}"
echo ""

echo "=== Test 2: BatchDelete from middle ==="
TList.new mylist2
mylist2.Add "item0"
mylist2.Add "item1"
mylist2.Add "item2"
mylist2.Add "item3"
mylist2.Add "item4"
echo "Initial: count=$(mylist2.count)"

echo "Calling BatchDelete 1 2"
mylist2.BatchDelete 1 2
echo "After: count=$(mylist2.count)"

items_var="mylist2_items"
declare -n items_ref="$items_var"
echo "Items: ${items_ref[@]}"
echo ""

echo "SUCCESS!"
