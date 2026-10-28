#!/usr/bin/env bash
# gnu_helper.sh — the shared GNU-tool test helpers of the TUtil wrapper family
# (launch L3.4, design docs/dev/launch/L3_4_design.md §2.5 T1, T2, T5).
#
# Sourced by the test files of TSed, TAwk, TGrep, TFind, THead and TTail after
# they have sourced their unit (hence kbool and, through tutil.sh, ktool):
#
#     source "$UNIT_DIR/../tutil/tests/gnu_helper.sh" || exit 1
#
# It lives with the family's base class, not in ktests: ktests is the framework
# of every repo and must not depend on a kkore unit.
#
# This file is deliberately not named NNN_*.sh: the ktests runner collects
# `[0-9][0-9][0-9]_*.sh` only (ktests/ktest_runner.sh, kt_runner_find_tests),
# so it is a library, not a test file — the precedent is
# kcl/tdirectory/tests/symlink_helper.sh. It is sourced, never executed.
#
#   kt_gnu_gate FAMILY VAR       one test case: does ktool find a GNU FAMILY?
#                                VAR = its path, GNU_OK / GNU_WHY (T2)
#   kt_gnu_stub FAMILY DIR VAR   a fake GNU FAMILY in DIR (absolute: starts
#                                with `/`, no `:`), selected through the
#                                shell variable KCL_GNU_<FAMILY> (not
#                                exported); VAR = its path (T5)
#
# FAMILY is ktool's: sed awk grep find head tail (TAwk's is `awk`).
# Every local is __ktg_*; the globals are GNU_OK and GNU_WHY (T2) and the
# variables the caller names.

kk.uses ktool || return 1

# kt_gnu_gate FAMILY VAR — replaces a test file's banner gate (T2). ONE test
# case, "GNU FAMILY: ktool resolves it", run in the test's MAIN shell so the
# ktool cache is warm for every later `.new` of the file (G8).
#   found:  VAR = the absolute path ktool answered, GNU_OK=1, GNU_WHY='',
#           the case passes "PATH — BANNER" (the first line of `--version`);
#   none:   VAR = '', GNU_OK=0, GNU_WHY = ktool.lastError's text, the case
#           passes "SKIP: GNU_WHY" — the file's `tcase` then passes every later
#           case as `SKIP: $GNU_WHY`, so the case count is the same either way;
#   rc 2 from ktool (an unknown FAMILY — a typo in the test — or ktool not
#           loaded): the case FAILS (never a silent SKIP of a whole file),
#           GNU_OK=0 and GNU_WHY set as above.
# rc 0 always.
kt_gnu_gate() {
    local __ktg_f=${1-} __ktg_var=${2-} __ktg_p __ktg_b='' __ktg_rc=0
    kt_test_start "GNU $__ktg_f: ktool resolves it"
    ktool.gnu "$__ktg_f" || __ktg_rc=$?
    if (( __ktg_rc == 0 )); then
        __ktg_p=$RESULT
        printf -v "$__ktg_var" '%s' "$__ktg_p"
        GNU_OK=1
        GNU_WHY=''
        __ktg_b=$(LC_ALL=C "$__ktg_p" --version </dev/null 2>/dev/null) || :
        __ktg_b=${__ktg_b//$'\r'/}
        __ktg_b=${__ktg_b%%$'\n'*}
        kt_test_pass "$__ktg_p — $__ktg_b"
    else
        ktool.lastError
        printf -v "$__ktg_var" '%s' ''
        GNU_OK=0
        GNU_WHY=$RESULT
        if (( __ktg_rc == 2 )); then
            kt_test_fail "ktool.gnu '$__ktg_f' rc 2: $GNU_WHY"
        else
            kt_test_pass "SKIP: $GNU_WHY"
        fi
    fi
    return 0
}

# kt_gnu_stub FAMILY DIR VAR — the argv-pin stub (T5, D-L34-7): writes
# DIR/FAMILY, a `#!/bin/sh` script that answers `--version` with a GNU banner
# and anything else with `.:DIR/share/awk` (TAwk's default-AWKPATH probe),
# creates an empty DIR/share/awk/inplace.awk, makes the script executable, sets
# the SHELL variable KCL_GNU_<FAMILY> to DIR/FAMILY (ktool reads it at call
# time; not exported) and VAR to the same path. A `.new` after it resolves the
# stub — the real tool never runs, and the argv pins are the same on every box.
# The stub never runs a tool. KCL_GNU_<FAMILY> is a shell variable, NOT
# exported: `$( )` sees the stub, a child PROCESS (`bash -c`, `timeout bash
# child.sh`) resolves the real tool.
# DIR must be ABSOLUTE (start with `/`) and hold no `:` — a relative DIR would
# make VAR differ from the $PWD-absolute path ktool answers, and a `C:/…` DIR
# would break the `.:DIR/share/awk` AWKPATH answer (`:` is its separator).
# rc 0; rc 1 (nothing written) for an unknown FAMILY, an empty VAR, or a DIR
# that breaks that rule.
kt_gnu_stub() {
    local __ktg_f=${1-} __ktg_d=${2-} __ktg_var=${3-} __ktg_env __ktg_ban __ktg_p __ktg_q
    case $__ktg_f in
        sed)  __ktg_env=KCL_GNU_SED  __ktg_ban='sed (GNU sed) 4.9' ;;
        awk)  __ktg_env=KCL_GNU_AWK  __ktg_ban='GNU Awk 5.3.0' ;;
        grep) __ktg_env=KCL_GNU_GREP __ktg_ban='grep (GNU grep) 3.11' ;;
        find) __ktg_env=KCL_GNU_FIND __ktg_ban='find (GNU findutils) 4.10.0' ;;
        head) __ktg_env=KCL_GNU_HEAD __ktg_ban='head (GNU coreutils) 9.4' ;;
        tail) __ktg_env=KCL_GNU_TAIL __ktg_ban='tail (GNU coreutils) 9.4' ;;
        *)    return 1 ;;
    esac
    if [[ -z $__ktg_var || $__ktg_d != /* || $__ktg_d == *:* ]]; then
        return 1
    fi
    __ktg_p=$__ktg_d/$__ktg_f
    __ktg_q=${__ktg_d//\'/\'\\\'\'}         # DIR inside the stub's single quotes
    mkdir -p -- "$__ktg_d/share/awk" || return 1
    : > "$__ktg_d/share/awk/inplace.awk" || return 1
    printf '%s\n' '#!/bin/sh' \
        "case \$1 in --version) printf '%s\\n' '$__ktg_ban';; *) printf '%s\\n' '.:$__ktg_q/share/awk';; esac" \
        > "$__ktg_p" || return 1
    # (`printf '%s\n'`, never `echo`: dash's echo interprets backslashes.)
    # No `--` here: BSD chmod stops option parsing at the MODE word, so a `--`
    # after it is a file operand (measured on kb-freebsd: `chmod: --: No such
    # file or directory`); the path starts with `/` (the DIR rule), never `-`
    chmod +x "$__ktg_p" || return 1
    printf -v "$__ktg_env" '%s' "$__ktg_p"
    printf -v "$__ktg_var" '%s' "$__ktg_p"
    return 0
}
