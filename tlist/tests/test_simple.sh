#!/bin/bash

# Simple test to check property persistence

source "../tlist.sh"

defineClass SimpleTest "" \
    property counter \
    constructor '{
        counter=0
    }' \
    method Inc '{
        counter=$((counter + 1))
        echo "Counter is now $counter"
    }' \
    method Get '{
        echo "$counter"
    }'

SimpleTest.new test
echo "Initial: $(test.Get)"
test.Inc
echo "After Inc: $(test.Get)"
test.Inc
echo "After second Inc: $(test.Get)"
