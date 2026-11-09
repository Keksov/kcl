#!/usr/bin/env bash
# 002_Malformed.sh - what is not a mouse report: rc 1, RESULT='', every
# FV_MOUSE_* global reset, nothing printed (kcl README 1.2); one Error line on
# stderr under VERBOSE_KKLASS=debug.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../ktests/ktest.sh"
source "$SCRIPT_DIR/../fv.mouse.sh"
kt_test_init "$(basename "$0" .sh)" "$SCRIPT_DIR" "$@"

kt_test_section "002: malformed reports"

bad() {
    local v out
    printf -v v '%q' "$1"
    kt_test_start "$v is rejected${2:+ ($2)}"
    fv.mouse.decode $'\e[<0;5;5M'                    # leave non-default values behind
    out=$(fv.mouse.decode "$1" 2>&1)
    fv.mouse.decode "$1" 2>/dev/null; local rc=$?
    if [[ $rc == 1 && -z $out && -z $RESULT && -z $FV_MOUSE_WHAT \
          && "$FV_MOUSE_BUTTON $FV_MOUSE_X $FV_MOUSE_Y $FV_MOUSE_MODS" == '0 0 0 0' ]]; then
        kt_test_pass "rc 1"
    else
        kt_test_fail "rc=$rc out='$out' RESULT='$RESULT' what='$FV_MOUSE_WHAT' $FV_MOUSE_BUTTON $FV_MOUSE_X $FV_MOUSE_Y $FV_MOUSE_MODS"
    fi
}

bad ''                       'empty'
bad 'x'                      'not a report'
bad $'\e[A'                  'a key'
bad $'\e[<M'                 'SGR without fields'
bad $'\e[<0;1M'              'two fields'
bad $'\e[<0;1;2;3M'          'four fields'
bad $'\e[<;1;1M'             'empty button field'
bad $'\e[<0;;1M'             'empty x'
bad $'\e[<0;1;M'             'empty y'
bad $'\e[<a;1;1M'            'a letter'
bad $'\e[<-1;1;1M'           'a sign'
bad $'\e[<0;0;1M'            'x 0 (coordinates are 1-based)'
bad $'\e[<0;1;0M'            'y 0'
bad $'\e[<256;1;1M'          'button byte > 255'
bad $'\e[<1234;1;1M'         'button field of 4 digits'
bad $'\e[<0;123456;1M'       'x of 6 digits'
bad $'\e[<0;1;123456M'       'y of 6 digits'
bad $'\e[<0;1;1X'            'wrong final byte'
bad $'\e[<0;1;1'             'no final byte'
bad $'\e[<0;1;1MxM'          'junk inside'
bad $'\e[<0;1;1M '           'junk after'
bad $'\e[<0;1;1$(echo x)M'   'an expansion is data'
bad $'\e[<0;1;1[$(echo x)]M' 'an array subscript is data'
bad $'\e[M'                  'X10 without bytes'
bad $'\e[M !'                'X10 with 2 bytes'
bad $'\e[M #!x'              'X10 with 4 bytes'
bad $'\e[M\x1f!!'            'X10 button byte < 32'
bad $'\e[M  !'               'X10 column byte 32 (column 0)'
bad $'\e[M ! '               'X10 row byte 32'
bad $'\e[M\x01\x02\x03'      'X10 control bytes'

kt_test_start "under VERBOSE_KKLASS=debug a malformed report prints one Error line"
err=$(VERBOSE_KKLASS=debug fv.mouse.decode $'\e[<0;0;1M' 2>&1 >/dev/null)
err2=$(VERBOSE_KKLASS=debug fv.mouse.decode x 2>&1 >/dev/null)
if [[ $err == 'Error: fv.mouse.decode: malformed SGR report' && $err2 == 'Error: fv.mouse.decode: not a mouse report' ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "'$err' / '$err2'"
fi

kt_test_log "002_Malformed.sh completed"
