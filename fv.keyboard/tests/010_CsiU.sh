#!/usr/bin/env bash
# 010_CsiU.sh - the kitty keyboard protocol's CSI u reports (flags 1|4; design
# P3 §14.1, §14.3, §14.4), decoded into FV's names:
#   * the design's examples: Alt+F / Alt+Shift+F / Ctrl+F / Ctrl+Alt+F with a
#     Russian, Greek, Hebrew and Arabic layout and with the US layout, Esc;
#     the name from the base-layout key, FV_KEY_CHAR the typed character (the
#     shifted key under Shift), FV_KEY_BASE the base key;
#   * a Latin layout (AZERTY): the name from the typed key, the base kept;
#   * modified Enter / Tab / Backspace / Space / Esc, Ctrl + \ ], Alt + the
#     punctuation keys, keypad and F13+ codes, Super / Hyper (kbUnknown), a
#     release (no key), a text field; no base field + a non-ASCII code: the
#     layout tables; xterm's formatOtherKeys / modifyOtherKeys forms;
#   * exact consumption: each report followed by another key (the trailing
#     key intact), a run of reports, the reports on a file fd;
#   * malformed reports: kbUnknown, the next key intact, never a hang (a cut
#     report on a live fd ends at the Esc timeout);
#   * what stays kbUnknown: win32-input-mode, bracketed paste (later stages);
#   * the 3L review's fixes: rxvt / xterm shifted arrows ending in c (CSI 1;2c,
#     ;5c) still decode; Alt + a shifted ASCII punctuation key is named from
#     the typed character (kbAltChar, as ESC !); Ctrl alone + M J I H [ give the
#     legacy names (kbEnter kbTab kbBack kbEsc); a shifted field that is a
#     control code is kbUnknown; ESC + a report that is no Alt key leaves no
#     character / base behind; kitty Ctrl+C under fv.video (__FV_KB_ISIG=1)
#     raises SIGINT to the process group from every reader and is no key (in a
#     job of its own: set -m), never from decode, Ctrl+Alt+C, Ctrl+Shift+C or
#     with ISIG 0 (kbCtrlC).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "010: CSI u (the kitty keyboard protocol)"

E=$'\e'
# chk BYTES KEY CHAR BASE [NOTE] — one test: decode BYTES -> FV_KEY KEY,
# FV_KEY_CHAR CHAR, FV_KEY_BASE BASE, every byte consumed
chk() {
    local n
    fvk_vis "$1"
    kt_test_start "decode $REPLY -> $2 char='$3' base='$4'${5:+ ($5)}"
    fvk_len "$1"; n=$REPLY
    fv.keyboard.decode "$1"
    if [[ $FV_KEY == "$2" && $FV_KEY_CHAR == "$3" && $FV_KEY_BASE == "$4" && $FV_KEY_LEN == "$n" && $FV_KEY_SEQ == "$1" && $RESULT == "$2" ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "got $FV_KEY char='$FV_KEY_CHAR' base='$FV_KEY_BASE' len=$FV_KEY_LEN of $n RESULT=$RESULT"
    fi
}
# keys VAR — every key of the queue: "name:char:base|..." (getKeyEvent 0)
keys() {
    local -n __o=$1
    __o=''
    while fv.keyboard.getKeyEvent 0; do __o+="$FV_KEY:$FV_KEY_CHAR:$FV_KEY_BASE|"; done
    __o=${__o%|}
}
# stream TITLE BYTES WANT — the keys of BYTES fed into the queue
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
stream() {
    kt_test_start "$1"
    fv.keyboard.flush
    fv.keyboard.feed "$2"
    keys got
    if [[ $got == "$3" ]]; then kt_test_pass "$got"; else kt_test_fail "got  $got"$'\n'"want $3"; fi
}

# --- the design's examples ------------------------------------------------------
chk "${E}[1072::102;3u" kbAltF 'а' f 'Alt+F, Russian'
chk "${E}[966::102;3u" kbAltF 'φ' f 'Alt+F, Greek'
chk "${E}[1499::102;3u" kbAltF 'כ' f 'Alt+F, Hebrew'
chk "${E}[1576::102;3u" kbAltF 'ب' f 'Alt+F, Arabic'
chk "${E}[102;3u" kbAltF f f 'Alt+F, US: no base field, the code is the base'
chk "${E}[1095::120;3u" kbAltX 'ч' x 'Alt+X, Russian: the status line kbAltX'
chk "${E}[1072:1040:102;4u" kbAltF 'А' f 'Alt+Shift+F, Russian: the shifted key typed, Shift in the character'
chk "${E}[102:70;4u" kbAltF F f 'Alt+Shift+F, US'
chk "${E}[102;4u" kbAltF F f 'Alt+Shift+F, US, no shifted field: the letter in upper case'
chk "${E}[1072::102;5u" kbCtrlF 'а' f 'Ctrl+F, Russian'
chk "${E}[102;5u" kbCtrlF f f 'Ctrl+F, US'
chk "${E}[1072::102;7u" kbCtrlAltF 'а' f 'Ctrl+Alt+F, Russian'
chk "${E}[1072:1040:102;8u" kbCtrlAltF 'А' f 'Ctrl+Alt+Shift+F, Russian'
chk "${E}[27u" kbEsc '' '' 'Esc (no Esc timeout with the protocol)'
chk "${E}[1072::102;33u" kbAltF 'а' f 'Meta read as Alt'
chk "${E}[1072::102;67u" kbAltF 'а' f 'Caps Lock (64) ignored'
chk "${E}[1072::102;131u" kbAltF 'а' f 'Num Lock (128) ignored'
chk "${E}[1078::59;3u" kbAltSemiCol 'ж' ';' 'Alt + the ; key, Russian'
chk "${E}[1093::91;3u" kbAltLftBrack 'х' '[' 'Alt + the [ key, Russian'
chk "${E}[49;3u" kbAlt1 1 1 'Alt+1'
chk "${E}[1;3u" kbUnknown '' '' 'a control code is no key'

# --- a Latin layout: the typed letter names the key ----------------------------------
chk "${E}[97::113;3u" kbAltA a q 'AZERTY Alt+A (the US q key): kbAltA, the base kept'
chk "${E}[113::97;5u" kbCtrlQ q a 'AZERTY Ctrl+Q (the US a key)'
chk "${E}[33::56;3u" kbAltChar '!' 8 'AZERTY Alt+! (the US 8 key): FV names no Alt+!'
chk "${E}[33::56;5u" kbUnknown '!' 8 'Ctrl+! : no FV name'

# --- functional keys and modified Enter / Tab / Backspace / Space ----------------------
chk "${E}[27;3u" kbAltEsc '' ''
chk "${E}[27;5u" kbCtrlEsc '' ''
chk "${E}[13u" kbEnter '' ''
chk "${E}[13;2u" kbShiftEnter '' ''
chk "${E}[13;3u" kbAltEnter '' ''
chk "${E}[13;5u" kbCtrlEnter '' '' "FV's name"
chk "${E}[9;2u" kbShiftTab '' ''
chk "${E}[9;5u" kbCtrlTab '' '' "FV's name"
chk "${E}[127;3u" kbAltBack '' ''
chk "${E}[127;5u" kbCtrlBack '' '' "FV's name"
chk "${E}[8;5u" kbCtrlBack '' '' 'Backspace sent as 8'
chk "${E}[32;3u" kbAltSpace ' ' ''
chk "${E}[32;5u" kbCtrlSpace ' ' ''
chk "${E}[32;2u" kbChar ' ' '' 'Shift+Space types a space'
chk "${E}[92;5u" kbCtrlBackslash '\' '\'
chk "${E}[93;5u" kbCtrlRBracket ']' ']'
chk "${E}[92;3u" kbAltBkSlash '\' '\'
chk "${E}[57414u" kbEnter '' '' 'keypad Enter'
chk "${E}[57414;5u" kbCtrlEnter '' '' 'Ctrl + keypad Enter'
chk "${E}[57417;5u" kbCtrlLeft '' '' 'Ctrl + keypad Left'
chk "${E}[57427u" kbCenter '' '' 'keypad Begin'
chk "${E}[57376u" kbF13 '' '' 'F13'
chk "${E}[57383;2u" kbShiftF20 '' '' 'Shift+F20'
chk "${E}[57398u" kbF35 '' '' 'F35'
chk "${E}[57404;3u" kbAlt5 5 5 'Alt + keypad 5'
chk "${E}[57413;5u" kbUnknown '+' '+' 'Ctrl + keypad +: no FV name'
chk "${E}[57441;2u" kbUnknown '' '' 'a modifier key (flag 8 only): kbUnknown'
chk "${E}[57358u" kbUnknown '' '' 'Caps Lock key'
chk "${E}[102;9u" kbUnknown '' '' 'Super+F: no FV key'
chk "${E}[102;17u" kbUnknown '' '' 'Hyper+F'
chk "${E}[97;1;97u" kbChar a a 'a text field (flag 16) is accepted and not needed'
chk "${E}[1072::102;3;1072u" kbAltF 'а' f 'Alt+F with a text field'
chk "${E}[1072::102;3:1u" kbAltF 'а' f 'event type 1 (press)'
chk "${E}[1072::102;3:2u" kbAltF 'а' f 'event type 2 (repeat)'
chk "${E}[1092u" kbChar 'ф' a 'a plain non-ASCII report (flag 8): kbChar, the base from the tables'

kt_test_start "a release report (event type 3) is no key: decode skips it (rc 1 alone, the next key after it)"
r=''
fv.keyboard.decode "${E}[1072::102;3:3u"; r+="$?:$FV_KEY "
fv.keyboard.decode "${E}[1072::102;3:3ux"; r+="$?:$FV_KEY:$FV_KEY_LEN"
if [[ $r == '1:kbNoKey 0:kbChar:1' ]]; then kt_test_pass "ok"; else kt_test_fail "got $r"; fi

# --- no base field, a non-ASCII code: the layout tables; xterm's forms -----------------
chk "${E}[1072;3u" kbAltF 'а' f "xterm formatOtherKeys=1 Alt+а (no base field): the tables"
chk "${E}[27;3;1072~" kbAltF 'а' f "xterm modifyOtherKeys=2 Alt+а: the tables"
chk "${E}[27;5;13~" kbCtrlEnter '' '' 'xterm modifyOtherKeys Ctrl+Enter'
chk "${E}[27;3;102~" kbAltF f f 'xterm modifyOtherKeys Alt+f'
chk "${E}[233;3u" kbAltChar 'é' '' 'Alt+é (no base, in no default table): kbAltChar'
chk "${E}[233;5u" kbUnknown 'é' '' 'Ctrl+é: no name'

# --- what stays kbUnknown ---------------------------------------------------------------
chk "${E}[70;33;1072;1;2;1_" kbUnknown '' '' 'win32-input-mode (option d, not decoded)'
chk "${E}[200~" kbPaste '' '' 'bracketed paste start alone: an empty paste (P3 3d; 014_Paste)'
chk "${E}[1072::102;3x" kbUnknown '' '' 'another final byte'

# --- exact consumption --------------------------------------------------------------------
stream "each report followed by a plain key: the trailing key intact" \
    "${E}[1072::102;3ux${E}[27uy${E}[13;5uz${E}[1072:1040:102;4u!" \
    'kbAltF:а:f|kbChar:x:|kbEsc::|kbChar:y:|kbCtrlEnter::|kbChar:z:|kbAltF:А:f|kbChar:!:'
stream "a run of reports, legacy keys between them" \
    "${E}[966::102;3u${E}[A${E}[1499::102;3u${E}f${E}[1576::102;5u${E}[1;5D" \
    'kbAltF:φ:f|kbUp::|kbAltF:כ:f|kbAltF:f:|kbCtrlF:ب:f|kbCtrlLeft::'
stream "an Esc report and a legacy Esc next to each other" \
    "${E}[27u${E}" \
    'kbEsc::|kbEsc::'

kt_test_start "reports on a file fd: the same keys, nothing read ahead"
fvk_fdfile "${E}[1072::102;3u${E}[102;5uq"
keys got
want='kbAltF:а:f|kbCtrlF:f:f|kbChar:q:'
if [[ $got == "$want" ]]; then kt_test_pass "$got"; else kt_test_fail "got  $got"$'\n'"want $want"; fi
FV_KEY_FD=$nullfd

# --- malformed: kbUnknown, the next key intact -----------------------------------------
stream "a non-digit inside the parameters ends the report (CSI grammar): the rest are keys" \
    "${E}[1072::x;3uk" \
    'kbUnknown::|kbChar:;:|kbChar:3:|kbChar:u:|kbChar:k:'
stream "empty code, four code fields, a 4-digit modifier, a 2-digit event: kbUnknown each" \
    "${E}[;3u${E}[1072:1:2:3;3u${E}[102;1000u${E}[102;3:11uk" \
    'kbUnknown::|kbUnknown::|kbUnknown::|kbUnknown::|kbChar:k:'
stream "modifier 0 and a code above U+10FFFF: kbUnknown" \
    "${E}[102;0u${E}[1114112;3uk" \
    'kbUnknown::|kbUnknown::|kbChar:k:'
stream "a surrogate code: kbUnknown" \
    "${E}[55357;3uk" \
    'kbUnknown::|kbChar:k:'
stream "a report cut by the next ESC: kbUnknown, the next key intact" \
    "${E}[1072::10${E}[27u" \
    'kbUnknown::|kbEsc::'
stream "a report cut by a high byte: kbUnknown, the character intact" \
    "${E}[1072;3"$'\xd0\xb6' \
    'kbUnknown::|kbChar:ж:'

kt_test_start "a report cut short on a live fd (nothing more comes) ends at the Esc timeout: kbUnknown, no hang"
fvk_fdfile "${E}[1072::102;3"
b=$EPOCHREALTIME
FV_ESC_TIMEOUT=0.05 fv.keyboard.getKeyEvent 2; r="$?:$FV_KEY"
e=$EPOCHREALTIME
ms=$(( ( ${e%[.,]*} * 1000000 + 10#${e##*[.,]} - ${b%[.,]*} * 1000000 - 10#${b##*[.,]} ) / 1000 ))
if [[ $r == 0:kbUnknown ]] && (( ms < 1500 )); then kt_test_pass "$r in $ms ms"; else kt_test_fail "got $r in $ms ms"; fi
FV_KEY_FD=$nullfd

kt_test_start "FV_KEY_BASE is empty for every legacy key and after rc 1"
r=''
for s in a "${E}f" "${E}[A" $'\x06' $'\xd0\xb6' "${E}[1;5D"; do fv.keyboard.decode "$s"; r+="[$FV_KEY_BASE]"; done
fv.keyboard.decode ''; r+="[$FV_KEY_BASE]"
if [[ $r == '[][][][][][][]' ]]; then kt_test_pass "ok"; else kt_test_fail "got $r"; fi


# --- the 3L review's fixes ------------------------------------------------------------------
# rxvt-style shifted arrows that end in c (the CSI u / reply arm hands them on)
chk "${E}[1;2c" kbShiftRight '' '' 'CSI 1;2c: the xterm form of a shifted arrow, not a reply'
chk "${E}[;2c" kbShiftRight '' '' 'CSI ;2c'
chk "${E}[1;5c" kbCtrlShiftRight '' '' 'CSI 1;5c (c is rxvt Shift+Right, the modifier adds Ctrl)'
chk "${E}${E}[1;2c" kbAltShiftRight '' '' 'ESC ESC [1;2c: Alt'
chk "${E}${E}[;5c" kbCtrlAltShiftRight '' '' 'ESC ESC [;5c'

# Alt + a shifted ASCII punctuation key: named from the typed character, as the legacy ESC + it
chk "${E}[49:33;4u" kbAltChar '!' 1 'Alt+Shift+1 types !: kbAltChar, as ESC ! (not kbAlt1)'
chk "${E}[50:64;4u" kbAltChar '@' 2 'Alt+Shift+2 types @'
chk "${E}[59:58;4u" kbAltChar ':' ';' 'Alt+Shift+; types :'
chk "${E}[49:33;6u" kbUnknown '!' 1 'Ctrl+Shift+1: no FV name'
chk "${E}[45:95;4u" kbAltChar '_' '-' 'Alt+Shift+- types _'
kt_test_start "the legacy forms of the same keys agree: ESC ! / ESC @ / ESC : are kbAltChar"
r=''
for s in "${E}!" "${E}@" "${E}:"; do fv.keyboard.decode "$s"; r+="$FV_KEY:$FV_KEY_CHAR "; done
if [[ $r == 'kbAltChar:! kbAltChar:@ kbAltChar:: ' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

# Ctrl alone + M / J / I / H / [: the legacy names (a legacy terminal sends 0x0D 0x0A 0x09 0x08 0x1B)
chk "${E}[109;5u" kbEnter '' '' 'Ctrl+M is Enter, as 0x0D'
chk "${E}[106;5u" kbEnter '' '' 'Ctrl+J is Enter, as 0x0A'
chk "${E}[105;5u" kbTab '' '' 'Ctrl+I is Tab, as 0x09'
chk "${E}[104;5u" kbBack '' '' 'Ctrl+H is Back, as 0x08'
chk "${E}[91;5u" kbEsc '' '' 'Ctrl+[ is Esc, as 0x1B'
chk "${E}[1100::109;5u" kbEnter '' '' 'Russian Ctrl+Ь (the US m key): Enter'
chk "${E}[109;69u" kbEnter '' '' 'Ctrl+M with Caps Lock'
chk "${E}[109;6u" kbCtrlM 'M' m 'Ctrl+Shift+M: not Ctrl alone, its own name'
chk "${E}[109;7u" kbCtrlAltM m m 'Ctrl+Alt+M'
chk "${E}[99;5u" kbCtrlC c c 'Ctrl+C decoded (decode never interrupts)'
chk "${E}[1089::99;5u" kbCtrlC 'с' c 'Russian Ctrl+С (the US c key)'

# a shifted field that is a control code
chk "${E}[97:5;2u" kbUnknown '' '' 'a shifted field 5 (a control code): no character'
chk "${E}[97:127;2u" kbUnknown '' '' 'a shifted field 127'

# an Esc right in front of a report that is no Alt key: a lone Esc, nothing of the report kept
stream "ESC + a plain report / a reply: kbEsc with no character or base left over, then the report; ESC + Ctrl+M: kbAltEnter, as ESC 0x0D" \
    "${E}${E}[1092u${E}${E}[?5u${E}${E}[109;5u" \
    'kbEsc::|kbChar:ф:a|kbEsc::|kbAltEnter::'

# --- Ctrl+C as a CSI u report (no 0x03, so the tty raises no SIGINT) -----------------------
# REPLY = the process group of PID ('' when /proc does not tell)
pgid() {
    local s
    REPLY=''
    if [[ -r /proc/$1/pgid ]]; then read -r REPLY < "/proc/$1/pgid"
    elif [[ -r /proc/$1/stat ]]; then read -r s < "/proc/$1/stat"; read -r _ _ REPLY _ <<< "${s##*) }"; fi
}
kt_test_start "kitty Ctrl+C with fv.video's TUI on (__FV_KB_ISIG=1): every reader raises SIGINT to its process group (kill 0, as the tty for 0x03) and answers no key; Ctrl+Alt+C, Ctrl+Shift+C, decode and ISIG 0 do not"
pgid "$BASHPID"; mypg=$REPLY
rm -f "$FVK_TMP/int.log" "$FVK_TMP/int.out"
if [[ -n $mypg ]]; then
    # a job of its own (set -m: its own process group), so kill 0 reaches it alone;
    # checked inside before anything is raised
    set -m
    (
        pgid "$BASHPID"
        if [[ -z $REPLY || $REPLY == "$mypg" ]]; then printf 'NOPG' > "$FVK_TMP/int.out"; exit 0; fi
        trap 'printf I >> "$FVK_TMP/int.log"' INT
        n() { local c=''; if [[ -f $FVK_TMP/int.log ]]; then c=$(<"$FVK_TMP/int.log"); fi; REPLY=${#c}; }
        __FV_KB_ISIG=1 r=''
        fv.keyboard.flush; fv.keyboard.feed "${E}[99;5ux"
        fv.keyboard.getKeyEvent 0; rc=$?; n; r+="[$rc:$FV_KEY:$FV_KEY_CHAR:$REPLY]"
        fv.keyboard.feed "${E}[1089::99;5uy"
        fv.keyboard.pollKeyEvent; p="$?:$FV_KEY_CHAR"
        fv.keyboard.getKeyEvent 0; rc=$?; n; r+="[$p $rc:$FV_KEY_CHAR:$REPLY]"
        fv.keyboard.feed "${E}[99;5u"
        fv.keyboard.getKeyEvent 0; rc=$?; n; r+="[$rc:$FV_KEY:$REPLY]"
        fv.keyboard.feed "${E}${E}[99;5uz"
        fv.keyboard.getKeyEvent 0; a="$?:$FV_KEY"
        fv.keyboard.getKeyEvent 0; rc=$?; n; r+="[$a $rc:$FV_KEY_CHAR:$REPLY]"
        fvk_fdfile "${E}[99;5uw"
        fv.keyboard.getKeyEvent; rc=$?; n; r+="[$rc:$FV_KEY_CHAR:$REPLY]"
        exec {nfd}</dev/null; FV_KEY_FD=$nfd
        fv.keyboard.feed "${E}[99;7u${E}[99;6u"
        fv.keyboard.getKeyEvent 0; a=$FV_KEY
        fv.keyboard.getKeyEvent 0; n; r+="[$a $FV_KEY:$REPLY]"
        fv.keyboard.decode "${E}[99;5u" >/dev/null; n; r+="[$FV_KEY:$REPLY]"
        __FV_KB_ISIG=0
        fv.keyboard.feed "${E}[99;5u"
        fv.keyboard.getKeyEvent 0; n; r+="[$FV_KEY:$FV_KEY_CHAR:$REPLY]"
        printf '%s' "$r" > "$FVK_TMP/int.out"
    ) &
    jp=$!
    set +m                    # (the job has its group; no job-control notice on stderr)
    wait "$jp"
    got=$(<"$FVK_TMP/int.out")
    want='[0:kbChar:x:1][0:y 0:y:2][1:kbNoKey:3][0:kbEsc 0:z:4][0:w:5][kbCtrlAltC kbCtrlC:5][kbCtrlC:5][kbCtrlC:c:5]'
    if [[ $got == NOPG ]]; then kt_test_pass "SKIP: no process group of its own here (set -m)"
    elif [[ $got == "$want" ]]; then kt_test_pass "$got"
    else kt_test_fail "got  $got"$'\n'"want $want"; fi
else
    kt_test_pass "SKIP: /proc tells no process group here"
fi
FV_KEY_FD=$nullfd

kt_test_log "010_CsiU.sh completed"
