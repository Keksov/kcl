#!/bin/bash
# Kklass static compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KklassStaticCompatibility" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

kt_test_start "TDirectory methods are registered as kklass static methods"
expected_methods=(createDirectory delete exists copy move isEmpty getDirectories getFiles getAttributes setAttributes getCreationTime setLastWriteTime)
missing_methods=()

for expected_method in "${expected_methods[@]}"; do
    found=false
    for registered_method in "${tdirectory_class_static_methods[@]}"; do
        if [[ "$registered_method" == "$expected_method" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != "true" ]]; then
        missing_methods+=("$expected_method")
    fi
done

if (( ${#tdirectory_class_static_methods[@]} > 0 && ${#missing_methods[@]} == 0 )); then
    kt_test_pass "TDirectory methods are registered as kklass static methods"
else
    kt_test_fail "TDirectory kklass metadata missing methods: ${missing_methods[*]:-(none)}; registered count: ${#tdirectory_class_static_methods[@]}"
fi

kt_test_start "TDirectory public methods preserve failure status after kklass registration"
if tdirectory.setAttributes "$SCRIPT_DIR/.tmp/no-such-directory" "faReadOnly" >/dev/null 2>&1; then
    kt_test_fail "TDirectory public methods preserve failure status after kklass registration"
else
    kt_test_pass "TDirectory public methods preserve failure status after kklass registration"
fi

kt_test_start "TDirectory internal recursive helpers stay namespaced"
get_dirs_recursive() { :; }
get_files_recursive() { :; }
get_entries_recursive() { :; }
source "$TDIRECTORY_DIR/tdirectory.sh"

leaked_helpers=()
for helper_name in get_dirs_recursive get_files_recursive get_entries_recursive; do
    if declare -F "$helper_name" >/dev/null; then
        leaked_helpers+=("$helper_name")
    fi
done

if (( ${#leaked_helpers[@]} == 0 )); then
    kt_test_pass "TDirectory internal recursive helpers stay namespaced"
else
    kt_test_fail "TDirectory internal recursive helpers stay namespaced (leaked: ${leaked_helpers[*]})"
fi