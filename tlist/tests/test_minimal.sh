#!/bin/bash

# Minimal TList test

# source "../tlist.sh"

source "../tlist.sh"

defineClass TestList "" \
    property capacity \
    property item_count \
    constructor '{
        capacity=0
        item_count=0
        eval "${this}_items=()"
    }' \
    method Add '{
        if (( item_count >= capacity )); then
            capacity=$((capacity + 4))
        fi
        local items_var="${this}_items"
        declare -n items_ref="$items_var"
        items_ref[$item_count]="item"
        item_count=$((item_count + 1))
        echo "$((item_count - 1))"
    }' \
    method Count '{
        echo "$item_count"
    }' \
    method Capacity '{
        echo "$capacity"
    }'

TestList.new mlist
echo "Initial count: $(mlist.Count)"
mlist.Add
echo "After add: $(mlist.Count)"
mlist.Add
echo "After second add: $(mlist.Count)"
