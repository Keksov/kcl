#!/usr/bin/env bash
# 028_HotKey.sh - fv.views.hotKeyIs HOT [plain] [typed|base] (design P3 §14.4,
# D30): the one hot-key match of every widget, on the event record (FV_EV_*):
#   * Alt: the typed character without case first (legacy ESC f, kitty, a
#     Cyrillic ~Ф~ on its own key), then the base-layout key (FV_EV_BASE)
#     only for a typed character that is not ASCII (Russian / Greek / Hebrew
#     Alt+F match ~F~; AZERTY's typed a matches ~A~ and never ~Q~, its US
#     position);
#   * plain (only with `plain`): a kbChar whose character matches without
#     case, else (non-ASCII) its base key or the layout tables' (no FV_EV_BASE
#     from a legacy terminal: fv.keyboard.layoutBase);
#   * no match: Ctrl chords, Alt + a function key, other events, an empty HOT;
#   * the caller's state: a C locale (Cyrillic folded through fv.video's
#     guard), nocasematch, RESULT kept; a bad word (not plain / typed / base,
#     one twice, typed with base, PLAIN under nocasematch): rc 2 + a debug
#     line; real events from fv.drivers (legacy and kitty bytes) end to end;
#   * the two passes of a hot-key map: mixed-script titles both match one
#     key without a word; `typed` asks the typed character only, `base` the
#     base key only (never for a Latin typed letter).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "028: hotKeyIs"

# ev KEY CHAR BASE — the event record of a key
ev() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=$2 FV_EV_BASE=$3; }
# hk TITLE WANT(0|1) HOT [plain] — one test on the current record
hk() {
    local t=$1 want=$2 rc
    shift 2
    kt_test_start "$t -> rc $want"
    fv.views.hotKeyIs "$@"; rc=$?
    if [[ $rc == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc ($FV_EV_WHAT $FV_EV_KEY '$FV_EV_CHAR' '$FV_EV_BASE')"; fi
}

# --- Alt -----------------------------------------------------------------------------
ev kbAltF f ''
hk "legacy Alt+F (ESC f), hot F" 0 F
hk "legacy Alt+F (ESC f), hot f" 0 f
hk "legacy Alt+F (ESC f), hot G" 1 G
ev kbAltF F ''
hk "legacy Alt+Shift+F (ESC F), hot f" 0 f
ev kbAltF 'а' f
hk "Russian Alt+F (typed а, base f), hot F" 0 F
hk "Russian Alt+F, hot Ф (another key: ф is A)" 1 'Ф'
hk "Russian Alt+F, hot А (typed first: the Cyrillic title on its own key)" 0 'А'
ev kbAltA 'ф' a
hk "Russian Alt+A (typed ф), hot Ф: typed first" 0 'Ф'
hk "Russian Alt+A (typed ф), hot ф" 0 'ф'
hk "Russian Alt+A (typed ф), hot A: the base" 0 A
ev kbAltF 'φ' f
hk "Greek Alt+F (φ), hot F" 0 F
ev kbAltF 'כ' f
hk "Hebrew Alt+F (כ), hot F" 0 F
ev kbAltF 'ب' f
hk "Arabic Alt+F (ب), hot F" 0 F
ev kbAltX 'ч' x
hk "Russian Alt+X (ч), hot X" 0 X
ev kbAltA a q
hk "AZERTY Alt+A (typed a, base q), hot A" 0 A
hk "AZERTY Alt+A (typed a, base q), hot Q: the US position never counts for a Latin letter" 1 Q
ev kbAltSemiCol 'ж' ';'
hk "Russian Alt+ж (the ; key), hot Ж" 0 'Ж'
hk "Russian Alt+ж (the ; key), hot ;" 0 ';'
ev kbAltChar 'é' ''
hk "Alt+é (no base), hot É" 0 'É'
hk "Alt+é (no base), hot E" 1 E
ev kbAlt1 1 ''
hk "Alt+1, hot 1" 0 1

# --- plain ------------------------------------------------------------------------------
ev kbChar f ''
hk "plain f, hot F, plain allowed" 0 F plain
hk "plain f, hot F, plain not allowed" 1 F
ev kbChar 'а' ''
hk "plain а (legacy: no base), hot F, plain: the layout tables" 0 F plain
hk "plain а, hot F, plain not allowed" 1 F
hk "plain а, hot А (typed first)" 0 'А' plain
ev kbChar 'а' f
hk "plain а with a base (a kitty report), hot F" 0 F plain
ev kbChar a q
hk "plain AZERTY a (base q), hot Q: no" 1 Q plain
ev kbChar 'é' ''
hk "plain é (in no table), hot E" 1 E plain

# --- never ------------------------------------------------------------------------------
ev kbCtrlF 'а' f
hk "Ctrl+F (Russian), hot F" 1 F
hk "Ctrl+F (Russian), hot F, plain" 1 F plain
ev kbAltF1 '' ''
hk "Alt+F1, hot F" 1 F
ev kbAltF 'а' f
FV_EV_WHAT=evMouseDown
hk "a mouse event carrying a stale key, hot F" 1 F
ev kbAltF f ''
hk "an empty HOT" 1 ''

# --- the caller's state -----------------------------------------------------------------
kt_test_start "a C-locale caller: Cyrillic folded all the same (fv.video's guard); RESULT kept"
ev kbAltA 'Ф' a
RESULT=keep
r="$(LC_ALL=C; fv.views.hotKeyIs 'ф'; printf '%s' "$?:$RESULT")"
r+=" $(LC_ALL=C; fv.views.hotKeyIs 'Ж'; printf '%s' "$?")"
ev kbChar 'Ф' ''
r+=" $(LC_ALL=C; RESULT=keep; fv.views.hotKeyIs A plain; printf '%s' "$?:$RESULT")"
if [[ $r == '0:keep 1 0:keep' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "a nocasematch caller: the same answers, its nocasematch kept"
ev kbAltF 'а' f
r="$(shopt -s nocasematch; fv.views.hotKeyIs F; printf '%s' "$?"; fv.views.hotKeyIs G; printf ' %s' "$?"; shopt -q nocasematch && printf ' nc')"
if [[ $r == '0 1 nc' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "a bad word: rc 2 and a debug line (also PLAIN under nocasematch, a word twice, typed with base)"
ev kbAltF f ''
err="$(VERBOSE_KKLASS=debug; fv.views.hotKeyIs F alt 2>&1; printf '|%s' "$?")"
r="$(shopt -s nocasematch; fv.views.hotKeyIs F PLAIN 2>/dev/null; printf '%s' "$?")"
r+=" $(fv.views.hotKeyIs F plain plain 2>/dev/null; printf '%s' "$?")"
r+=" $(fv.views.hotKeyIs F typed base 2>/dev/null; printf '%s' "$?")"
r+=" $(fv.views.hotKeyIs F base plain typed 2>/dev/null; printf '%s' "$?")"
r+=" $(fv.views.hotKeyIs F base plain 2>/dev/null; printf '%s' "$?")"
if [[ $err == *"hotKeyIs: 'alt' is not plain, typed or base"*'|2' && $r == '2 2 2 2 1' ]]; then kt_test_pass "$r"; else kt_test_fail "got [$err] [$r]"; fi

# --- the two passes of a hot-key map (typed, then base) ------------------------------------
ev kbAltA 'ф' a
hk "mixed-script titles (~Ф~айл, ~A~bout), Russian Alt+Ф (typed ф, base a): both ~Ф~ and ~A~ match without a word" 0 'Ф'
hk "... hot A without a word" 0 A
hk "... typed pass: ~Ф~ matches" 0 'Ф' typed
hk "... typed pass: ~A~ does not (the base key is not asked)" 1 A typed
hk "... base pass: ~A~ matches" 0 A base
hk "... base pass: ~Ф~ does not (the typed character is not asked)" 1 'Ф' base
ev kbAltA a q
hk "AZERTY Alt+A (typed a, base q), base pass, hot Q: never (a Latin typed letter)" 1 Q base
hk "AZERTY Alt+A, typed pass, hot A" 0 A typed
ev kbChar 'а' ''
hk "plain а (legacy, no base), base pass with plain: the tables, hot F" 0 F plain base
hk "plain а, typed pass with plain, hot F: no" 1 F typed plain
hk "plain а, base pass without plain: no" 1 F base

# --- end to end: events from fv.drivers --------------------------------------------------
kt_test_start "end to end: legacy and kitty bytes through fv.drivers.getEvent, then hotKeyIs F"
printf '%s' $'\e\xd0\xb0\e[1072::102;3u\ef\e\xd1\x84\e[97::113;3u' > "$FVW_TMP/keys.bin"
exec {kfd}< "$FVW_TMP/keys.bin"
saved=${FV_KEY_FD-0}
FV_KEY_FD=$kfd
fv.keyboard.flush
r=''
for i in 1 2 3 4 5; do
    fv.drivers.getEvent 0
    fv.views.hotKeyIs F; r+="$?"
    fv.views.hotKeyIs A; r+="$? "
done
FV_KEY_FD=$saved
exec {kfd}<&-
# ESC а: F yes A no; kitty а: F yes A no; ESC f: F yes A no; ESC ф (base a): F no A yes; AZERTY a/q: F no A yes
if [[ $r == '01 01 01 10 10 ' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_log "028_HotKey.sh completed"
