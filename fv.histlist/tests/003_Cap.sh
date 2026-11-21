#!/usr/bin/env bash
# 003_Cap.sh - the store's size cap (FV HistorySize, FV_UNICODE's records):
#   * a record = the string's UTF-8 bytes + the ULEB128 bytes of that length
#     + 2; the store starts at 1 byte used (FV's HistoryUsed): ASCII,
#     Cyrillic (2 bytes), CJK (3), emoji (4); 127 / 128 bytes (1 / 2 length
#     bytes), 16383 / 16384 (2 / 3);
#   * a string that does not fit drops the OLDEST strings of the WHOLE store
#     (any id), and only as many as needed; a string moved to the front is
#     young again; a string whose record alone exceeds the store is not added
#     (and its old copy stays);
#   * FV_HISTORY_SIZE: read at each add; not digits -> 65536; a smaller value
#     set later trims at the next add;
#   * against the model (fvh_madd: FV's block as one record list): seeded
#     random adds over 4 ids, repeats and a small cap, each list and the
#     bytes used equal the model's after every step (also in a C-locale
#     caller, where the same bytes are the strings).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvh_testlib.sh"
fvh_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: the size cap"

kt_test_start "record sizes: bytes + ULEB length bytes + 2 (ASCII 1, Cyrillic 2, CJK 3, emoji 4 bytes a character)"
fv.histlist.clearHistory
r=''
for t in a ab жж 中 '👍' "$(printf 'x%.0s' {1..127})" "$(printf 'x%.0s' {1..128})"; do
    u=$__FV_HL_USED; fv.histlist.historyAdd 1 "$t"; r+="$(( __FV_HL_USED - u )) "
done
if [[ $r == '4 5 7 6 7 130 132 ' ]]; then kt_test_pass "$r"; else kt_test_fail "[$r]"; fi

kt_test_start "16383 / 16384 bytes: 2 / 3 length bytes"
fv.histlist.clearHistory
printf -v t '%16383s' ''; u=$__FV_HL_USED; fv.histlist.historyAdd 2 "${t// /y}"; a=$(( __FV_HL_USED - u ))
printf -v t '%16384s' ''; u=$__FV_HL_USED; fv.histlist.historyAdd 2 "${t// /z}"; b=$(( __FV_HL_USED - u ))
if [[ $a == 16387 && $b == 16389 ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi

kt_test_start "full: the oldest strings of the whole store go (any id), only as many as needed"
fv.histlist.clearHistory
FV_HISTORY_SIZE=30
fv.histlist.historyAdd 1 aaaa     # 7 -> 8
fv.histlist.historyAdd 2 bbbb     # 7 -> 15
fv.histlist.historyAdd 1 cccc     # 7 -> 22
fv.histlist.historyAdd 3 dddd     # 7 -> 29
fv.histlist.historyAdd 2 eeeeeeee # 11: aaaa and bbbb go -> 29
fvh_list 1; l1=$REPLY; fvh_list 2; l2=$REPLY; fvh_list 3; l3=$REPLY
if [[ $l1 == $'cccc\x1f' && $l2 == $'eeeeeeee\x1f' && $l3 == $'dddd\x1f' && $__FV_HL_USED == 26 ]]; then kt_test_pass ok
else kt_test_fail "[$l1] [$l2] [$l3] used $__FV_HL_USED"; fi

kt_test_start "a string moved to the front is young again: the next to go is the one after it"
fv.histlist.historyAdd 1 cccc_new
fv.histlist.historyAdd 1 cccc      # back to the front of list 1, younger than dddd
fv.histlist.historyAdd 4 ffffffff  # 11 more: the oldest now are dddd, eeeeeeee
fvh_list 1; l1=$REPLY; fvh_list 3; l3=$REPLY; fvh_list 2; l2=$REPLY
if [[ $l1 == $'cccc\x1fcccc_new\x1f' && -z $l3 && -z $l2 ]]; then kt_test_pass ok; else kt_test_fail "[$l1] [$l3] [$l2]"; fi

kt_test_start "a list's newest string added again is the store's youngest record (FV: deleted + inserted)"
fv.histlist.clearHistory
fv.histlist.historyAdd 6 aaaa; fv.histlist.historyAdd 7 bbbb; fv.histlist.historyAdd 6 aaaa   # 22
fv.histlist.historyAdd 8 "$(printf 'q%.0s' {1..14})"                                        # 17: bbbb goes
fvh_list 6; l6=$REPLY; fvh_list 7; l7=$REPLY
if [[ $l6 == $'aaaa\x1f' && -z $l7 && $__FV_HL_USED == 25 ]]; then kt_test_pass ok; else kt_test_fail "[$l6] [$l7] used $__FV_HL_USED"; fi
fv.histlist.historyAdd 1 cccc; fv.histlist.historyAdd 1 cccc_new; fv.histlist.historyAdd 1 cccc

kt_test_start "a string whose record alone exceeds the store is not added; its old copy stays"
fv.histlist.historyAdd 1 "$(printf 'w%.0s' {1..27})"   # 30 > 29
fvh_list 1
if [[ $REPLY == $'cccc\x1fcccc_new\x1f' ]]; then kt_test_pass ok; else kt_test_fail "[$REPLY]"; fi

kt_test_start "FV_HISTORY_SIZE not digits -> 65536; a smaller value later trims at the next add"
FV_HISTORY_SIZE=lots
fv.histlist.clearHistory
for i in {1..20}; do fv.histlist.historyAdd 5 "entry $i"; done
fv.histlist.historyCount 5; a=$RESULT
FV_HISTORY_SIZE=40
fv.histlist.historyAdd 5 last
fv.histlist.historyCount 5; b=$RESULT; fv.histlist.historyStr 5 0; c=$RESULT
FV_HISTORY_SIZE=65536
if [[ $a == 20 && $b -lt 5 && $c == last && $__FV_HL_USED -le 40 ]]; then kt_test_pass "20 -> $b"; else kt_test_fail "$a $b $c used $__FV_HL_USED"; fi

# the model run: STEPS random adds (seeded); words from a small pool so that
# repeats happen, some of them Cyrillic / CJK / emoji
model_run() {
    local seed=$1 steps=$2 cap=$3 i id w bad='' j
    local -a pool=(a bb ccc dddd жук 中文 '👍' 'x y' eeeee ffffff ggggggg жжжжж '中文字符' 'ok ok ok')
    RANDOM=$seed
    fv.histlist.clearHistory
    FV_HISTORY_SIZE=$cap
    fvh_mreset "$cap"
    for (( i = 0; i < steps; i++ )); do
        id=$(( RANDOM % 4 )) w=${pool[RANDOM % ${#pool[@]}]}
        if (( RANDOM % 7 == 0 )); then w="$w$(( RANDOM % 50 ))"; fi
        fv.histlist.historyAdd "$id" "$w"
        fvh_madd "$id" "$w"
        if (( __FV_HL_USED != FVH_MU )); then bad+=" step $i used $__FV_HL_USED/$FVH_MU"; break; fi
        for j in 0 1 2 3; do
            fvh_list "$j"; local got=$REPLY
            fvh_mlist "$j"
            if ! [ "$got" = "$REPLY" ]; then bad+=" step $i id $j"; break 2; fi
        done
    done
    FV_HISTORY_SIZE=65536
    MODEL_BAD=$bad
}
kt_test_start "against the model: 300 seeded adds over 4 ids, cap 60"
model_run 4242 300 60
if [[ -z $MODEL_BAD ]]; then kt_test_pass ok; else kt_test_fail "$MODEL_BAD"; fi
kt_test_start "against the model: 300 seeded adds over 4 ids, cap 200"
model_run 77 300 200
if [[ -z $MODEL_BAD ]]; then kt_test_pass ok; else kt_test_fail "$MODEL_BAD"; fi
kt_test_start "against the model in a C-locale caller (bytes are the strings): 200 adds, cap 80"
LC_ALL=C model_run 9 200 80
if [[ -z $MODEL_BAD ]]; then kt_test_pass ok; else kt_test_fail "$MODEL_BAD"; fi

kt_test_start "the store's bookkeeping after the runs: live sequence numbers == the strings of all lists"
n=0; for id in 0 1 2 3; do fv.histlist.historyCount $id; n=$(( n + RESULT )); done
if (( ${#__FV_HL_ID[@]} - 1 == n && ${#__FV_HL_SZ[@]} - 1 == n )); then kt_test_pass "$n"; else kt_test_fail "${#__FV_HL_ID[@]} ${#__FV_HL_SZ[@]} $n"; fi

kt_test_log "003_Cap.sh completed"
