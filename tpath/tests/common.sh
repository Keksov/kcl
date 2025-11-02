#!/bin/bash
# common.sh - Shared setup code for kcl tests

# Get script directory (only if not already set)
if [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == *"/tpath" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
KCL_DIR="$SCRIPT_DIR/.."
TPATH_SCRIPT="$KCL_DIR/tpath.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global array for selected tests
TESTS_TO_RUN=()

# Parse test selection string into TESTS_TO_RUN array
parse_test_selection() {
    local selection="$1"
    TESTS_TO_RUN=()
    IFS=',' read -ra parts <<< "$selection"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                TESTS_TO_RUN+=("$i")
            done
        else
            TESTS_TO_RUN+=("$part")
        fi
    done
}

# Parse command line arguments
parse_args() {
    # If VERBOSITY is already set (e.g., from runner), use it
    if [[ -n "$VERBOSITY" ]]; then
        return
    fi
    VERBOSITY="error"
    TEST_SELECTION=""
    MODE="threaded"
    WORKERS=8
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbosity|--verbosity=*)
                if [[ $1 == --verbosity=* ]]; then
                    VERBOSITY="${1#*=}"
                else
                    VERBOSITY="$2"
                    shift
                fi
                ;;
            -v)
                VERBOSITY="$2"
                shift
                ;;
            -n|--tests)
                TEST_SELECTION="$2"
                shift
                ;;
            -m|--mode)
                MODE="$2"
                shift
                ;;
            -w)
                WORKERS="$2"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [-v|--verbosity info|error] [-n|--tests SELECTION] [-m|--mode threaded|single] [-w WORKERS]"
                echo "  -n SELECTION: Run specific tests (e.g., 1, 1-3, 1,3,5-7)"
                echo "  -m MODE: Execution mode, 'threaded' or 'single' (default: threaded)"
                echo "  -w WORKERS: Number of workers for threaded mode (default: 8)"
                exit 1
                ;;
        esac
        shift
    done

    # Validate verbosity
    if [[ "$VERBOSITY" != "info" && "$VERBOSITY" != "error" ]]; then
        echo "Error: verbosity must be 'info' or 'error'"
        exit 1
    fi

    # Validate mode
    if [[ "$MODE" != "threaded" && "$MODE" != "single" ]]; then
        echo "Error: mode must be 'threaded' or 'single'"
        exit 1
    fi

    # Validate workers
    if ! [[ "$WORKERS" =~ ^[0-9]+$ ]] || [[ "$WORKERS" -le 0 ]]; then
        echo "Error: workers must be a positive integer"
        exit 1
    fi

    # Parse test selection if provided
    if [[ -n "$TEST_SELECTION" ]]; then
        parse_test_selection "$TEST_SELECTION"
    fi

    export MODE WORKERS
}

# Test result functions
test_start() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${BLUE}[TEST]${NC} $1"
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

test_pass() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${GREEN}[PASS]${NC} $1"
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_info() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${YELLOW}[INFO]${NC} $1"
    fi
}

test_section() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}$1${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo ""
    fi
}

# Cleanup function
cleanup() {
    # Clean up test files
    rm -f test_*.tmp 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT
trap 'echo "Error occurred at line $LINENO: $BASH_COMMAND"' ERR

# Source the tpath script if not already sourced
if ! declare -F | grep -q "tpath.combine"; then
    source "$TPATH_SCRIPT"
fi
