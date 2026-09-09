#!/usr/bin/env bash
# kcl/fpjson — P0 measurement probe (decision D8).
#
# Question: which tokenizer idiom can a pure-bash JSON lexer afford?
#   1. bytes     — the classic `${s:i:1}` scan over the WHOLE document string.
#                  On a large string this is O(n) per access in bash, so the
#                  scan is O(n^2). This is the idiom the original fpjson DRAFT
#                  plan assumed and the reason that plan had to be rewritten.
#   2. winbytes  — the same character scan, but over a 2 KB window sliced out of
#                  the document. Isolates how much of `bytes` is pure slicing cost.
#   3. regex     — the D8 candidate: `[[ $window =~ ^(token) ]]` over a sliding
#                  window, advancing by ${#BASH_REMATCH[0]}. Yields WHOLE tokens,
#                  not characters. ONE regex covers every token kind.
#   4. hybrid    — the shape P1 will actually implement: same window, but the
#                  token kind comes from a `case` on the first byte and the
#                  regex engine is entered only for strings and numbers.
#
# All four run with `local LC_ALL=C` (byte semantics; verified to also put the
# [[ =~ ]] engine into byte mode on 5.2.37 and 5.3.9 — see PLAN.md §4.2) and all
# four count the same token set, so the token counts must agree; the script
# fails loudly if they do not.
#
# Self-contained: no fpjson code exists yet, nothing is sourced.
#
# Usage:  bash lexer_probe.sh [KB ...]            # default: 2 20 96
#         bash lexer_probe.sh --no-slow 2 20 96   # skip `bytes` above 32 KB
#
# Gate (kcl/PLAN.md P10): windowed lexer parses 20 KB in <= 1 s on bash 5.2.37.

set -eu

WINSZ=${FPJSON_WIN:-2048}          # window refilled out of the document string
MINFILL=${FPJSON_MINFILL:-256}     # refill once the window has shrunk below this
NO_SLOW=0
SWEEP=0
SLOW_LIMIT_KB=32    # `bytes` above this is skipped when --no-slow is given

SIZES=()
for a in "$@"; do
    case $a in
        --no-slow) NO_SLOW=1 ;;
        --sweep)   SWEEP=1 ;;
        *[!0-9]*)  printf 'lexer_probe: bad argument: %s\n' "$a" >&2; exit 2 ;;
        *)         SIZES+=("$a") ;;
    esac
done
(( ${#SIZES[@]} )) || SIZES=(2 20 96)

# ---------------------------------------------------------------- clock ------
# EPOCHREALTIME split by hand: no fork, no awk, works in both locales.
NOW_US=0
now_us() {
    local t=${EPOCHREALTIME/,/.}
    NOW_US=$(( ${t%.*} * 1000000 + 10#${t#*.} ))
}

# ------------------------------------------------------------ generator ------
# A realistic small-payload document: nested object + array, strings with
# escapes, negative/exponent numbers, true/false/null, an inner array.
JSON=''
gen() {
    local LC_ALL=C           # byte semantics, so the document is identical
                             # whatever locale the caller runs in
    local kb=$1 target=$(( $1 * 1024 )) i=0 j='{"items":['
    while (( ${#j} < target )); do
        j+='{"id":'"$i"',"name":"user '"$i"'","tag":"a\"b\\cé","score":-1.5e3,"ok":true,"nil":null,"list":[1,2,3]},'
        i=$(( i + 1 ))
    done
    j=${j%,}
    j+=']}'
    JSON=$j
}

# ------------------------------------------------------- tokenizer: bytes ----
# Whole-document `${s:i:1}` scan. Counts one token per punctuator, string,
# number and literal; whitespace is not a token.
TOKENS=0
tok_bytes() {
    local LC_ALL=C
    local s=$1
    local n=${#s} i=0 c cnt=0
    while (( i < n )); do
        c=${s:i:1}
        case $c in
            ' '|$'\t'|$'\n'|$'\r') i=$(( i + 1 )) ;;
            '{'|'}'|'['|']'|':'|',') i=$(( i + 1 )); cnt=$(( cnt + 1 )) ;;
            '"')
                i=$(( i + 1 ))
                while (( i < n )); do
                    c=${s:i:1}
                    if [[ $c == '\' ]]; then i=$(( i + 2 )); continue; fi
                    i=$(( i + 1 ))
                    [[ $c == '"' ]] && break
                done
                cnt=$(( cnt + 1 )) ;;
            t) i=$(( i + 4 )); cnt=$(( cnt + 1 )) ;;
            f) i=$(( i + 5 )); cnt=$(( cnt + 1 )) ;;
            n) i=$(( i + 4 )); cnt=$(( cnt + 1 )) ;;
            *)
                while (( i < n )); do
                    c=${s:i:1}
                    case $c in
                        [-+.0-9eE]) i=$(( i + 1 )) ;;
                        *) break ;;
                    esac
                done
                cnt=$(( cnt + 1 )) ;;
        esac
    done
    TOKENS=$cnt
}

# --------------------------------------------------- tokenizer: winbytes ----
# Same scan, but the character comes out of a 2 KB window. A token may straddle
# a window edge, so the window is refilled from the current absolute position
# whenever fewer than MINFILL bytes are left in it.
tok_winbytes() {
    local LC_ALL=C
    local s=$1
    local n=${#s} p=0 c cnt=0 w='' q=0 wl=0
    while (( p < n )); do
        if (( q >= wl - MINFILL )); then
            w=${s:p+q:WINSZ}
            p=$(( p + q )); q=0; wl=${#w}
            (( wl )) || break
        fi
        c=${w:q:1}
        case $c in
            ' '|$'\t'|$'\n'|$'\r') q=$(( q + 1 )) ;;
            '{'|'}'|'['|']'|':'|',') q=$(( q + 1 )); cnt=$(( cnt + 1 )) ;;
            '"')
                q=$(( q + 1 ))
                while :; do
                    if (( q >= wl )); then
                        w=${s:p+q:WINSZ}; p=$(( p + q )); q=0; wl=${#w}
                        (( wl )) || break
                    fi
                    c=${w:q:1}
                    if [[ $c == '\' ]]; then q=$(( q + 2 )); continue; fi
                    q=$(( q + 1 ))
                    [[ $c == '"' ]] && break
                done
                cnt=$(( cnt + 1 )) ;;
            t) q=$(( q + 4 )); cnt=$(( cnt + 1 )) ;;
            f) q=$(( q + 5 )); cnt=$(( cnt + 1 )) ;;
            n) q=$(( q + 4 )); cnt=$(( cnt + 1 )) ;;
            *)
                while :; do
                    if (( q >= wl )); then
                        w=${s:p+q:WINSZ}; p=$(( p + q )); q=0; wl=${#w}
                        (( wl )) || break
                    fi
                    c=${w:q:1}
                    case $c in
                        [-+.0-9eE]) q=$(( q + 1 )) ;;
                        *) break ;;
                    esac
                done
                cnt=$(( cnt + 1 )) ;;
        esac
        (( p + q <= n )) || break
    done
    TOKENS=$cnt
}

# ------------------------------------------------------ tokenizer: regex ----
# The D8 candidate. One `[[ =~ ]]` per TOKEN, not per character; the matched
# prefix is dropped from the window, and the window is refilled out of the big
# string only about once per (WINSZ - MINFILL) bytes consumed.
#
# The string alternative is written unrolled — `"[^"\]*(\\.[^"\]*)*"` — rather
# than `"([^"\]|\\.)*"`, which backtracks catastrophically on long strings.
LEXERR=''
tok_regex() {
    local LC_ALL=C
    local s=$1
    local ws=$' \t\n\r'
    local re='^['"$ws"']*([][{}:,]|"[^"\]*(\\.[^"\]*)*"|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)'
    local n=${#s} p=0 cnt=0 m win=$WINSZ w=''
    LEXERR=''
    w=${s:0:win}
    while :; do
        if (( ${#w} < MINFILL && p + ${#w} < n )); then
            w=${s:p:win}
        fi
        [[ -n $w ]] || break
        if [[ $w =~ $re ]]; then
            m=${#BASH_REMATCH[0]}
            p=$(( p + m )); w=${w:m}; cnt=$(( cnt + 1 ))
            (( win == WINSZ )) || { win=$WINSZ; w=${s:p:win}; }
        elif (( p + ${#w} < n )); then
            win=$(( win * 4 ))          # a token longer than the window
            w=${s:p:win}
        elif [[ $w =~ ^["$ws"]+$ ]]; then
            p=$(( p + ${#w} )); w=''    # trailing whitespace
        else
            LEXERR="unexpected byte at offset $p"
            break
        fi
    done
    TOKENS=$cnt
}

# ----------------------------------------------------- tokenizer: hybrid ----
# What the P1 lexer is actually meant to look like: the same sliding window,
# but the token kind is decided from its FIRST BYTE with a `case`, and the
# regex engine is entered only for the two kinds whose length is not obvious —
# strings and numbers. Punctuation (about half of all tokens in real payloads)
# and the three literals never touch it.
tok_hybrid() {
    local LC_ALL=C
    local s=$1
    local ws=$' \t\n\r'
    local rews='^['"$ws"']+'
    local restr='^"[^"\]*(\\.[^"\]*)*"'
    local renum='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?'
    local n=${#s} p=0 cnt=0 m win=$WINSZ w='' c re=''
    LEXERR=''
    w=${s:0:win}
    while :; do
        if (( ${#w} < MINFILL && p + ${#w} < n )); then
            w=${s:p:win}
            (( win == WINSZ )) || win=$WINSZ
        fi
        [[ -n $w ]] || break
        c=${w:0:1}
        m=0
        case $c in
            ' '|$'\t'|$'\n'|$'\r')
                [[ $w =~ $rews ]] && m=${#BASH_REMATCH[0]}
                p=$(( p + m )); w=${w:m}
                continue ;;
            '{'|'}'|'['|']'|':'|',') m=1 ;;
            '"')  re=$restr ;;
            t)    [[ ${w:0:4} == true  ]] && m=4 ;;
            f)    [[ ${w:0:5} == false ]] && m=5 ;;
            n)    [[ ${w:0:4} == null  ]] && m=4 ;;
            *)    re=$renum ;;
        esac
        if (( m == 0 )); then
            if [[ ${c} == '"' || ${c} == [-0-9] ]] && [[ $w =~ $re ]]; then
                m=${#BASH_REMATCH[0]}
            elif (( p + ${#w} < n )); then
                win=$(( win * 4 )); w=${s:p:win}   # token longer than the window
                continue
            else
                LEXERR="unexpected byte at offset $p"
                break
            fi
        fi
        p=$(( p + m )); w=${w:m}; cnt=$(( cnt + 1 ))
    done
    TOKENS=$cnt
}

# ------------------------------------------------------------- driver -------
printf 'lexer_probe — bash %s   LC_ALL=%s   window=%s refill<%s\n' \
       "$BASH_VERSION" "${LC_ALL:-<unset>}" "$WINSZ" "$MINFILL"
printf '%9s  %-9s %8s %10s %9s\n' bytes impl tokens ms KB/s
printf '%9s  %-9s %8s %10s %9s\n' --------- --------- -------- ---------- ---------

run_one() {                    # $1 = impl, $2 = json
    local impl=$1 s=$2 t0 t1 us ms rate
    now_us; t0=$NOW_US
    "tok_$impl" "$s"
    now_us; t1=$NOW_US
    us=$(( t1 - t0 )); (( us > 0 )) || us=1
    ms=$(( us / 1000 ))
    rate=$(( ${#s} * 1000000 / us / 1024 ))
    printf '%9s  %-9s %8s %10s %9s\n' "${#s}" "$impl" "$TOKENS" "$ms" "$rate"
    LAST_MS=$ms; LAST_TOKENS=$TOKENS
}

LAST_MS=0; LAST_TOKENS=0
rc=0
for kb in "${SIZES[@]}"; do
    gen "$kb"
    ref=0
    if (( NO_SLOW && kb > SLOW_LIMIT_KB )); then
        printf '%9s  %-9s %8s %10s %9s\n' "${#JSON}" bytes - skipped -
    else
        run_one bytes "$JSON"; ref=$LAST_TOKENS
    fi
    run_one winbytes "$JSON"
    (( ref )) || ref=$LAST_TOKENS
    if (( LAST_TOKENS != ref )); then
        printf 'MISMATCH: winbytes %s tokens vs bytes %s\n' "$LAST_TOKENS" "$ref" >&2; rc=1
    fi
    gate_ms=0
    for impl in regex hybrid; do
        run_one "$impl" "$JSON"
        [[ $impl == hybrid ]] && gate_ms=$LAST_MS
        if [[ -n $LEXERR ]]; then
            printf 'LEX ERROR (%s): %s\n' "$impl" "$LEXERR" >&2; rc=1
        fi
        if (( LAST_TOKENS != ref )); then
            printf 'MISMATCH: %s %s tokens vs %s\n' "$impl" "$LAST_TOKENS" "$ref" >&2; rc=1
        fi
    done
    if (( kb == 20 )); then
        if (( gate_ms <= 1000 )); then
            printf 'GATE 20 KB <= 1000 ms (hybrid): PASS (%s ms)\n' "$gate_ms"
        else
            printf 'GATE 20 KB <= 1000 ms (hybrid): FAIL (%s ms)\n' "$gate_ms"; rc=1
        fi
    fi
    printf '\n'
done

# ----------------------------------------------------------- window sweep ---
# The per-token cost of the regex lexer is one [[ =~ ]] plus one `w=${w:m}`
# shift of the window, and the shift is O(window) — so the window wants to be
# SMALL, not large. --sweep measures where the optimum sits on this machine.
if (( SWEEP )); then
    gen 20
    printf 'window sweep on %s bytes\n' "${#JSON}"
    printf '%9s %12s %12s %12s\n' window 'regex ms' 'hybrid ms' 'winbytes ms'
    for WINSZ in 128 256 512 1024 2048 4096; do
        MINFILL=$(( WINSZ / 8 )); (( MINFILL >= 64 )) || MINFILL=64
        now_us; t0=$NOW_US
        tok_regex "$JSON"
        now_us; t1=$NOW_US
        tok_hybrid "$JSON"
        now_us; t2=$NOW_US
        tok_winbytes "$JSON"
        now_us
        printf '%9s %12s %12s %12s\n' "$WINSZ" \
               "$(( (t1 - t0) / 1000 ))" "$(( (t2 - t1) / 1000 ))" \
               "$(( (NOW_US - t2) / 1000 ))"
    done
    WINSZ=${FPJSON_WIN:-2048}; MINFILL=${FPJSON_MINFILL:-256}
    printf '\n'
fi

# -------------------------------------------------------------- selftest ----
# Correctness of the window machinery, not speed: the three tokenizers must
# agree on documents that exercise the edges (a token longer than the window,
# escapes, multi-byte UTF-8, whitespace runs, an empty container).
selftest() {
    local name doc bad=0
    local -a names docs
    names=(long-string escapes utf8 whitespace empty-containers deep)
    docs=(
        ''
        '{"a":"x\"y\\zé\n","b":"\\"}'
        '{"ключ":"значение é 中 😀","n":[-0,1E400,9223372036854775807]}'
        $'{\n\t"a"  :\r\n  1 ,\n"b":[ ]\n}'
        '{"a":{},"b":[],"c":[{}],"d":[[]]}'
        '[[[[[[[[[[1]]]]]]]]]]'
    )
    local big=''
    while (( ${#big} < 5000 )); do big+='abcdefghij'; done
    docs[0]='{"s":"'$big'","t":1}'

    local i ref
    for i in "${!names[@]}"; do
        name=${names[i]}; doc=${docs[i]}
        tok_bytes    "$doc"; ref=$TOKENS
        tok_winbytes "$doc"
        if (( TOKENS != ref )); then
            printf 'SELFTEST %-17s winbytes %s != bytes %s\n' "$name" "$TOKENS" "$ref" >&2; bad=1; continue
        fi
        local impl fail=0
        for impl in regex hybrid; do
            "tok_$impl" "$doc"
            if [[ -n $LEXERR ]]; then
                printf 'SELFTEST %-17s %s lex error: %s\n' "$name" "$impl" "$LEXERR" >&2
                bad=1; fail=1; continue
            fi
            if (( TOKENS != ref )); then
                printf 'SELFTEST %-17s %s %s != bytes %s\n' "$name" "$impl" "$TOKENS" "$ref" >&2
                bad=1; fail=1
            fi
        done
        if (( fail )); then continue; fi
        printf 'SELFTEST %-17s ok (%s tokens)\n' "$name" "$TOKENS"
    done
    return "$bad"
}
selftest || rc=1

exit "$rc"
