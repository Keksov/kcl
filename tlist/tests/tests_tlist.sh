#!/bin/bash
# test_tlist.sh - Comprehensive test suite for TList class
# Tests all TList functionality

set -e  # Exit on any error

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KCL_DIR="$SCRIPT_DIR/.."

# Source common.sh for shared code and parsing
source "$SCRIPT_DIR/common.sh"

# Parse command line arguments
parse_args "$@"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Normalize and deduplicate file list (Windows-safe, no external sort)
unique_and_clean() {
    local -n in_arr=$1
    local -n out_arr=$2
    declare -A seen=()
    local f
    for f in "${in_arr[@]}"; do
        f="${f%$'\r'}"
        if [[ -f "$f" && -z "${seen[$f]}" ]]; then
            out_arr+=("$f")
            seen[$f]=1
        fi
    done
}

# Function to find and execute test files
run_tests() {
    local test_files=()
    local pattern="*.sh"
    # Enable nullglob so unmatched globs expand to nothing
    shopt -s nullglob

    if [[ ${#TESTS_TO_RUN[@]} -gt 0 ]]; then
        # Verbose debug info
        if [[ "$VERBOSITY" == "info" ]]; then
            echo -e "${YELLOW}[INFO]${NC} TEST_SELECTION='$TEST_SELECTION' -> TESTS_TO_RUN=(${TESTS_TO_RUN[*]})"
        fi

        # For each selected test number
        for num in "${TESTS_TO_RUN[@]}"; do
            local patterns=()

            # Always include the raw prefix form like "X_*.sh"
            patterns+=("$SCRIPT_DIR/${num}_*.sh")

            # If the prefix is purely numeric, include zero-padded variants: 01_, 001_, 0001_
            if [[ "$num" =~ ^[0-9]+$ ]]; then
                patterns+=("$SCRIPT_DIR/0${num}_*.sh")
                patterns+=("$SCRIPT_DIR/00${num}_*.sh")
                patterns+=("$SCRIPT_DIR/000${num}_*.sh")
                # Also include explicit 3-digit pad (covers e.g. 1 -> 001_)
                patterns+=("$SCRIPT_DIR/$(printf '%03d' "$num")_*.sh")
            fi

            # Collect matching files using globbing
            for pat in "${patterns[@]}"; do
                for f in $pat; do
                    if [[ -f "$f" ]]; then
                        test_files+=("$f")
                    fi
                done
            done
        done

        if [[ "$VERBOSITY" == "info" ]]; then
            echo -e "${YELLOW}[INFO]${NC} Matched ${#test_files[@]} file(s):"
            for _m in "${test_files[@]}"; do echo " - ${_m}"; done
        fi
    else
        # Run all test files
        for f in "$SCRIPT_DIR"/[0-9][0-9][0-9]_*.sh; do
            if [[ -f "$f" ]]; then
                test_files+=("$f")
            fi
        done
    fi
    # Revert nullglob
    shopt -u nullglob

    # Normalize and deduplicate without relying on external sort (Windows-safe)
    local unique_files=()
    unique_and_clean test_files unique_files
    test_files=("${unique_files[@]}")

    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "No test files found matching criteria."
        exit 1
    fi

    if [[ "$VERBOSITY" == "info" ]]; then
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}Comprehensive TList Test Suite${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo "Running ${#test_files[@]} test file(s) in $MODE mode..."
        if [[ "$MODE" == "threaded" ]]; then
            echo "Using $WORKERS worker(s)..."
        fi
        echo ""
    fi

    if [[ "$MODE" == "single" ]]; then
        # Execute each test file sequentially in isolated bash, aggregate counters
        for test_file in "${test_files[@]}"; do
            if [[ "$VERBOSITY" == "info" ]]; then
                echo -e "${YELLOW}[EXEC]${NC} $(basename "$test_file")"
            fi
            local clean_file="${test_file%$'\r'}"
            local run_output counts_line __tag __t __p __f

            # Run the test in a separate bash process to avoid sourcing path issues on Windows
            run_output="$(
                bash -c "export VERBOSITY='$VERBOSITY'; source \"$clean_file\"; echo __COUNTS__:\$TESTS_TOTAL:\$TESTS_PASSED:\$TESTS_FAILED" 2>&1 || true
            )"

            # Parse counters first
            counts_line="$(printf '%s\n' "$run_output" | sed -e 's/\r$//' | grep '^__COUNTS__:' | tail -n 1)"
            if [[ -n "$counts_line" ]]; then
                IFS=':' read -r __tag __t __p __f <<<"$counts_line"
                __t=${__t:-0}; __p=${__p:-0}; __f=${__f:-0}
                TESTS_TOTAL=$((TESTS_TOTAL + __t))
                TESTS_PASSED=$((TESTS_PASSED + __p))
                TESTS_FAILED=$((TESTS_FAILED + __f))
            else
                # If no counters reported, assume the test file represents 1 test that failed hard
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                __f=1  # Mark as failed for output
                echo -e "${RED}[FAIL]${NC} $(basename "$test_file") (no counters reported)"
            fi

            # Show output except the counters line when verbose or for failed tests
            if [[ "$VERBOSITY" == "info" || $(( __f )) -gt 0 ]]; then
                if [[ -n "$counts_line" && $(( __f )) -gt 0 && "$VERBOSITY" == "error" ]]; then
                    echo -e "${RED}[FAIL]${NC} $(basename "$test_file")"
                fi
                echo "$run_output" | sed -e 's/\r$//' | grep -v '^__COUNTS__:' || true
            fi
        done
    else
        # Threaded execution
        local temp_dir="$(mktemp -d)"
        local temp_files=()

        for test_file in "${test_files[@]}"; do
            local clean_file="${test_file%$'\\r'}"
            local temp_file="$temp_dir/$(basename "$test_file").out"
            temp_files+=("$temp_file")

            if [[ "$VERBOSITY" == "info" ]]; then
                echo -e "${YELLOW}[EXEC]${NC} $(basename "$test_file")"
            fi

            # Run the test in background, output to temp file
            bash -c "export VERBOSITY='$VERBOSITY'; source \"$clean_file\"; echo __COUNTS__:\$TESTS_TOTAL:\$TESTS_PASSED:\$TESTS_FAILED" > "$temp_file" 2>&1 &

            # Limit concurrent jobs
            while [[ $(jobs -r | wc -l) -ge $WORKERS ]]; do
                wait $(jobs -r -p | head -1)
            done
        done

        # Wait for all remaining jobs
        wait

        # Collect results
        for temp_file in "${temp_files[@]}"; do
            local run_output counts_line __tag __t __p __f
            if [[ -f "$temp_file" ]]; then
                run_output="$(cat "$temp_file")"
            else
                run_output=""
            fi

            # Parse counters
            counts_line="$(printf '%s\n' "$run_output" | sed -e 's/\r$//' | grep '^__COUNTS__:' | tail -n 1)"
            local test_name="$(basename "${temp_file%.out}")"
            if [[ -n "$counts_line" ]]; then
                IFS=':' read -r __tag __t __p __f <<<"$counts_line"
                __t=${__t:-0}; __p=${__p:-0}; __f=${__f:-0}
                TESTS_TOTAL=$((TESTS_TOTAL + __t))
                TESTS_PASSED=$((TESTS_PASSED + __p))
                TESTS_FAILED=$((TESTS_FAILED + __f))
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                __f=1
                echo -e "${RED}[FAIL]${NC} $test_name (no counters reported)"
            fi

            # Show output
            if [[ "$VERBOSITY" == "info" || $(( __f )) -gt 0 ]]; then
                if [[ -n "$counts_line" && $(( __f )) -gt 0 && "$VERBOSITY" == "error" ]]; then
                    echo -e "${RED}[FAIL]${NC} $test_name"
                fi
                echo "$run_output" | sed -e 's/\r$//' | grep -v '^__COUNTS__:' || true
            fi
        done

        # Cleanup temp dir
        rm -rf "$temp_dir"
    fi
}

# Execute tests
run_tests

# =============================================================================
# FINAL RESULTS
# =============================================================================
total=$(cat <<-EOT
Total tests: $TESTS_TOTAL
Passed: ${GREEN}$TESTS_PASSED${NC}
Failed: ${RED}$TESTS_FAILED${NC}
EOT
)

if [[ "${VERBOSITY:-1}" == "info" ]]; then
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Test Results Summary${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "$total"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed.${NC}"
        exit 1
    fi
else
    echo -e $total
fi