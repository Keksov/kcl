#!/usr/bin/env bash
# 002_Parse.sh - fv.dlg's parser (design §4.5, P4-7; D32's flag set):
#   * every flag of the stage in both tools' spellings maps to one key;
#     --opt=value and --opt value; the fv extras and their values;
#   * §4.5's rules: options anywhere before `--` (before, between, after the
#     positionals), the fixed positionals literal (TEXT '-5', '--title', ''),
#     an optional positional (INIT) unless it is exactly a known option,
#     `--` ending the options (INIT after it), one widget per call, sizes
#     0 / -1 / numbers, refusals with one line (unknown, missing, extra, bad
#     sizes, values); the list widgets (4a-2): LH,
#     TAG ITEM [STATUS] groups, options at a group boundary, `--` before
#     tags, empty / incomplete lists, STATUS on / off (any case); flags
#     outside the subset;
#   * THE GOLDEN TABLE (stage 4a-1, the real whiptail 0.52.25 and dialog
#     1.3-20250116 on Debian 13 under script(1); scratchpad p4/golden): each
#     row names what whiptail and dialog did with the same argv and what
#     fvdlg must do (the parse, or the refusal's words);
#   * `\n` and \Z in TEXT (fv.dlg._text), the fit of a text (fv.dlg._fit).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# pt TITLE WANT ARG... — one test: the parse of ARG is WANT
pt() {
    local title=$1 want=$2
    shift 2
    fvdl_parse "$@"
    kt_test_start "$title"
    if [[ $REPLY == "$want" ]]; then kt_test_pass "$REPLY"; else kt_test_fail "got [$REPLY] want [$want]"; fi
}

kt_test_section "002: the widgets and the positionals"
pt "msgbox TEXT H W" '0|msgbox|Hello|8|30||' --msgbox Hello 8 30
pt "yesno" '0|yesno|Sure?|0|0||' --yesno 'Sure?' 0 0
pt "infobox" '0|infobox|Wait|-1|-1||' --infobox Wait -1 -1
pt "inputbox without INIT" '0|inputbox|Name:|0|0||' --inputbox 'Name:' 0 0
pt "inputbox with INIT" '0|inputbox|Name:|0|0|init||' --inputbox 'Name:' 0 0 init
pt "passwordbox with INIT" '0|passwordbox|P|8|40|sec||' --passwordbox P 8 40 sec
pt "TEXT may start with '-' (fixed positionals are literal)" '0|msgbox|-5 °C|0|0||' --msgbox '-5 °C' 0 0
pt "TEXT may look like an option" '0|msgbox|--title|8|30||' --msgbox --title 8 30
pt "TEXT may be empty" '0|msgbox||8|30||' --msgbox '' 8 30
pt "H / W may look like options too: taken, then checked" '1|HEIGHT must be an integer (got '"'"'--x'"'"')' --msgbox t --x 30
pt "INIT '-x' is INIT (not a known option)" '0|inputbox|N|0|0|-x||' --inputbox N 0 0 -x
pt "INIT that is exactly a known option is that option" '0|inputbox|N|0|0||title=TT;' --inputbox N 0 0 --title TT
pt "\`--\` forces INIT" '0|inputbox|N|0|0|--weird||' --inputbox N 0 0 -- --weird
pt "\`--\` then an empty INIT" '0|inputbox|N|0|0|||' --inputbox N 0 0 -- ''
pt "the widget after the options" '0|yesno|q|0|0||defaultno=1;title=T;' --title T --defaultno --yesno q 0 0
pt "options after the positionals" '0|msgbox|Hi|10|40||title=T;' --msgbox Hi 10 40 --title T
pt "options between the positionals are positionals (fixed ones are literal); H checked at once: the refusal names the word" "1|HEIGHT must be an integer (got '--title')" --msgbox Hi --title T 10 40
pt "an option after INIT" '0|inputbox|N|0|0|v||out=1;' --inputbox N 0 0 v --stdout

kt_test_section "002: every flag of the stage, both spellings"
pt "--title / --backtitle" '0|msgbox|t|0|0||backtitle=B;title=T;' --title T --backtitle B --msgbox t 0 0
pt "--ok-button = --ok-label" '0|msgbox|t|0|0||ok=X;' --ok-button X --msgbox t 0 0
pt "--ok-label (dialog)" '0|msgbox|t|0|0||ok=X;' --ok-label X --msgbox t 0 0
pt "--cancel-button / --cancel-label: the last wins" '0|inputbox|t|0|0||cancel=B;' --cancel-label A --cancel-button B --inputbox t 0 0
pt "--yes-button / --no-label" '0|yesno|t|0|0||no=N;yes=Y;' --yes-button Y --no-label N --yesno t 0 0
pt "--yes-label / --no-button" '0|yesno|t|0|0||no=N;yes=Y;' --yes-label Y --no-button N --yesno t 0 0
pt "--nocancel = --no-cancel" '0|inputbox|t|0|0||nocancel=1;' --no-cancel --inputbox t 0 0
pt "--notags / --no-tags, --noitem / --no-items" '0|msgbox|t|0|0||noitem=1;notags=1;' --notags --no-items --msgbox t 0 0
pt "--stdout" '0|msgbox|t|0|0||out=1;' --stdout --msgbox t 0 0
pt "--stderr" '0|msgbox|t|0|0||out=2;' --stdout --stderr --msgbox t 0 0
pt "--output-fd N" '0|msgbox|t|0|0||out=3;' --output-fd 3 --msgbox t 0 0
pt "--output-fd=N" '0|msgbox|t|0|0||out=7;' --output-fd=07 --msgbox t 0 0
pt "--title=VALUE (an = inside the value kept)" '0|msgbox|t|0|0||title=a=b;' --title=a=b --msgbox t 0 0
pt "--title= (empty)" '0|msgbox|t|0|0||title=;' --title= --msgbox t 0 0
pt "--defaultno --separate-output --single-quoted" '0|yesno|t|0|0||defaultno=1;sepout=1;single=1;' --defaultno --separate-output --single-quoted --yesno t 0 0
pt "--clear --colors --keep-tite --erase-on-exit" '0|msgbox|t|0|0||clear=1;colors=1;erase=1;keeptite=1;' --clear --colors --keep-tite --erase-on-exit --msgbox t 0 0
pt "--scrolltext --fb --fullbuttons --topleft" '0|msgbox|t|0|0||fb=1;scrolltext=1;topleft=1;' --scrolltext --fb --fullbuttons --topleft --msgbox t 0 0
pt "--no-collapse --cr-wrap --trim --insecure" '0|msgbox|t|0|0||crwrap=1;insecure=1;nocollapse=1;trim=1;' --no-collapse --cr-wrap --trim --insecure --msgbox t 0 0
pt "--ascii-lines = --fv-ascii; --no-shadow" '0|msgbox|t|0|0||ascii=1;noshadow=1;' --ascii-lines --fv-ascii --no-shadow --msgbox t 0 0
pt "--default-item (parsed now, used by the lists)" '0|msgbox|t|0|0||defitem=b;' --default-item b --msgbox t 0 0
pt "the fv extras" '0|passwordbox|t|0|0||echo=none;mouse=off;output=single;palette=blue;screen=main;' \
    --fv-palette blue --fv-mouse off --fv-echo none --fv-screen main --fv-output single --passwordbox t 0 0
pt "the headless options" '0|msgbox|t|0|0||fvout=o.bin;headless=1;keys=k.bin;size=100x30;' --fv-headless --fv-keys k.bin --fv-size 100x30 --fv-out o.bin --msgbox t 0 0
pt "--help stops the parse (the command's)" '0|m:--help' --msgbox t 0 0 --help --bogus
pt "--version" '0|m:--version' --version

kt_test_section "002: the refusals"
pt "no arguments" '1|no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox, --menu, --checklist, --radiolist)'
pt "options only" '1|no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox, --menu, --checklist, --radiolist)' --title T
pt "an unknown option" "1|unknown option '--bogus'" --bogus --msgbox t 0 0
pt "an unknown option after the positionals" "1|unknown option '--bogus'" --msgbox t 0 0 --bogus
pt "a single-dash word before the widget" "1|unknown option '-x'" -x --msgbox t 0 0
pt "a stray word" "1|unexpected argument 'hello'" hello --msgbox t 0 0
pt "an extra positional" "1|unexpected argument 'extra'" --msgbox t 0 0 extra
pt "an extra after INIT" "1|unexpected argument 'more'" --inputbox t 0 0 init more
pt "an extra after \`--\`" "1|unexpected argument '--title'" --msgbox t 0 0 -- --title X
pt "\`--\` before the widget makes it data" "1|unexpected argument '--msgbox'" -- --msgbox t 0 0
pt "too few positionals" "1|'--msgbox' needs TEXT HEIGHT WIDTH (got 2 of 3)" --msgbox t 8
pt "the widget alone" "1|'--yesno' needs TEXT HEIGHT WIDTH (got 0 of 3)" --yesno
pt "HEIGHT not an integer" "1|HEIGHT must be an integer (got 'x')" --msgbox t x 10
pt "WIDTH not an integer" "1|WIDTH must be an integer (got '')" --msgbox t 1 ''
pt "a size with seven digits" "1|HEIGHT must be an integer (got '1234567')" --msgbox t 1234567 10
pt "two widgets" "1|one widget per call ('--yesno' after '--msgbox'); --and-widget is not supported" --msgbox a 0 0 --yesno b 0 0
pt "--and-widget" "1|option '--and-widget' is not supported (outside fvdlg's whiptail / dialog subset)" --msgbox a 0 0 --and-widget --msgbox b 0 0
pt "--help-button / --extra-button" "1|option '--extra-button' is not supported (outside fvdlg's whiptail / dialog subset)" --extra-button --msgbox t 0 0
pt "a dialog-only widget" "1|option '--calendar' is not supported (outside fvdlg's whiptail / dialog subset)" --calendar t 0 0
pt "--menu: TEXT H W LH and TAG ITEM groups" "0|menu|t|0|0|0|a|A|b|B||" --menu t 0 0 0 a A b B
pt "--checklist: TAG ITEM STATUS groups, an option before" "0|checklist|t|0|0|0|a|A|on||title=T;" --title T --checklist t 0 0 0 a A on
pt "--radiolist: STATUS in any case" "0|radiolist|t|0|0|3|a|A|ON|b|B|Off||" --radiolist t 0 0 3 a A ON b B Off
pt "a list's fixed positionals are literal (TEXT '--title')" "0|menu|--title|0|0|0|a|A||" --menu --title 0 0 0 a A
pt "an option at a group boundary is an option, inside a group data" "0|menu|t|0|0|0|a|--title|b|B||title=T;" --menu t 0 0 0 a --title --title T b B
pt "after -- every word is an item" "0|checklist|t|0|0|0|--title|x|on|-|y|off||" --checklist t 0 0 0 -- --title x on - y off
pt "an unknown word at a boundary starts a group" "0|menu|t|0|0|0|-x|X||" --menu t 0 0 0 -x X
pt "LH not an integer" "1|LIST-HEIGHT must be an integer, 0 or more (got 'z')" --menu t 0 0 z a A
pt "LH negative" "1|LIST-HEIGHT must be an integer, 0 or more (got '-1')" --menu t 0 0 -1 a A
pt "too few fixed positionals for a list" "1|'--menu' needs TEXT HEIGHT WIDTH LIST-HEIGHT (got 3 of 4)" --menu t 0 0
pt "an empty list" "1|'--radiolist' needs at least one TAG ITEM STATUS group (the list is empty)" --radiolist t 0 0 0
pt "an incomplete group" "1|'--menu' takes TAG ITEM groups (3 words after LIST-HEIGHT: the last group is incomplete)" --menu t 0 0 0 a A b
pt "a bad STATUS" "1|STATUS must be on or off (got '1' for the tag 'b')" --checklist t 0 0 0 a A on b B 1
pt "--gauge / --textbox: not yet (4d)" "1|'--textbox' is not supported yet" --textbox /etc/hosts 0 0
pt "a list widget after a widget: one widget per call" "1|one widget per call ('--menu' after '--msgbox'); --and-widget is not supported" --msgbox a 0 0 --menu t 0 0 0
pt "a value missing at the end" "1|option '--backtitle' needs a value" --msgbox t 0 0 --backtitle
pt "a flag with =value" "1|option '--nocancel' takes no value" --nocancel=yes --inputbox t 0 0
pt "--stdout=1" "1|option '--stdout' takes no value" --stdout=1 --msgbox t 0 0
pt "--output-fd not a number" "1|--output-fd needs a file descriptor number (got '-1')" --output-fd -1 --msgbox t 0 0
pt "--output-fd empty" "1|--output-fd needs a file descriptor number (got '')" --output-fd= --msgbox t 0 0
pt "--fv-palette" "1|--fv-palette must be gray | blue | cyan (got 'Blue')" --fv-palette Blue --msgbox t 0 0
pt "--fv-echo" "1|--fv-echo must be star | none (got '')" --fv-echo '' --passwordbox t 0 0
pt "--fv-screen" "1|--fv-screen must be alt | main (got 'both')" --fv-screen both --msgbox t 0 0
pt "--fv-mouse" "1|--fv-mouse must be on | off (got '1')" --fv-mouse 1 --msgbox t 0 0
pt "--fv-output" "1|--fv-output must be lines | quoted | single (got 'x')" --fv-output x --msgbox t 0 0
pt "--fv-size W only" "1|--fv-size must be WxH, 1..1000 each (got '80x')" --fv-headless --fv-size 80x --msgbox t 0 0
pt "--fv-size zero" "1|--fv-size must be WxH, 1..1000 each (got '0x24')" --fv-headless --fv-size 0x24 --msgbox t 0 0
pt "--fv-size 1000x1000 (the cap) is taken" '0|msgbox|t|0|0||headless=1;size=1000x1000;' --fv-headless --fv-size 1000x1000 --msgbox t 0 0
pt "--fv-size above 1000 per side is refused (W)" "1|--fv-size must be WxH, 1..1000 each (got '1001x24')" --fv-headless --fv-size 1001x24 --msgbox t 0 0
pt "--fv-size above 1000 per side is refused (H, leading zeros)" "1|--fv-size must be WxH, 1..1000 each (got '80x09999')" --fv-headless --fv-size 80x09999 --msgbox t 0 0
pt "--fv-keys without --fv-headless" "1|--fv-keys, --fv-size and --fv-out are for --fv-headless" --fv-keys k --msgbox t 0 0
pt "an fv extra's value is one word exactly: 'gray blue' is refused (no substring)" "1|--fv-palette must be gray | blue | cyan (got 'gray blue')" --fv-palette 'gray blue' --msgbox t 0 0
pt "an fv extra's value with a blank around it is refused" "1|--fv-mouse must be on | off (got ' off')" --fv-mouse ' off' --msgbox t 0 0
pt "a pattern in an fv extra's value is no pattern" "1|--fv-echo must be star | none (got 's*')" --fv-echo 's*' --passwordbox t 0 0
shopt -s nocasematch
pt "under nocasematch --fv-mouse OFF is refused (exact words)" "1|--fv-mouse must be on | off (got 'OFF')" --fv-mouse OFF --msgbox t 0 0
pt "under nocasematch --fv-output Lines is refused" "1|--fv-output must be lines | quoted | single (got 'Lines')" --fv-output Lines --msgbox t 0 0
pt "under nocasematch the right words still pass" '0|msgbox|t|0|0||mouse=off;output=lines;' --fv-mouse off --fv-output lines --msgbox t 0 0
shopt -u nocasematch
pt "W checked as soon as the three positionals are taken (an option after them is not reached)" "1|WIDTH must be an integer (got '--stdout')" --msgbox t 8 --stdout --bogus
pt "nocasematch does not make --TITLE an option" "1|unknown option '--TITLE'" --TITLE T --msgbox t 0 0

kt_test_section "002: the golden table (whiptail 0.52.25 / dialog 1.3-20250116 vs fvdlg)"
# golden ID WHIPTAIL DIALOG WANT ARG... — the row ID of p4/golden/summary.txt:
# what each real tool did (documented here), what fvdlg's parse must give
golden() {
    local id=$1 wt=$2 dg=$3 want=$4
    shift 4
    pt "golden $id (whiptail: $wt; dialog: $dg)" "$want" "$@"
}
golden msg_enter   'rc 0' 'rc 0' '0|msgbox|Hello world|8|30||' --msgbox 'Hello world' 8 30
golden msg_00      'auto size' 'auto size' '0|msgbox|Hello world|0|0||' --msgbox 'Hello world' 0 0
golden msg_m1      "'-1: unknown option' rc 1" 'the whole screen' '0|msgbox|Hello world|-1|-1||' --msgbox 'Hello world' -1 -1
golden msg_x       'usage, rc 255' "'Expected a number for token 2', 255" "1|HEIGHT must be an integer (got 'x')" --msgbox 'Hello world' x 10
golden msg_after   'title shown' "'Expected a box option', 255" '0|msgbox|Hello world|8|30||title=AFTERTITLE;' --msgbox 'Hello world' 8 30 --title AFTERTITLE
golden msg_between 'title shown' 255 "1|HEIGHT must be an integer (got '--title')" --msgbox 'Hello world' --title BETWEENT 8 30
golden msg_dash    "'-5: unknown option' rc 1" 'text -5' '0|msgbox|-5|8|30||' --msgbox -5 8 30
golden msg_dashopt 'usage, 255' 255 '0|msgbox|--title|8|30||' --msgbox --title 8 30
golden msg_empty   'rc 0' 'rc 0' '0|msgbox||8|30||' --msgbox '' 8 30
golden msg_missing 'usage, 255' 255 "1|'--msgbox' needs TEXT HEIGHT WIDTH (got 2 of 3)" --msgbox Hello 8
golden msg_extra   'ignored, rc 0' "'Expected no more than 2 tokens', 255" "1|unexpected argument 'extra'" --msgbox Hello 8 30 extra
golden msg_unknown "'--bogus: unknown option' rc 1" "'Unknown option --bogus.' 255" "1|unknown option '--bogus'" --bogus --msgbox Hello 8 30
golden msg_unknown_after "'--bogus: unknown option' rc 1" 255 "1|unknown option '--bogus'" --msgbox Hello 8 30 --bogus
golden msg_two     'usage, 255' 'both shown, rc 0' "1|one widget per call ('--yesno' after '--msgbox'); --and-widget is not supported" --msgbox a 8 30 --yesno b 8 30
golden msg_titleeq 'title shown' "'Unknown option --title=EQTITLE.' 255" '0|msgbox|Hello|8|30||title=EQTITLE;' --title=EQTITLE --msgbox Hello 8 30
golden msg_ddash   'rc 0 (extras ignored)' 255 "1|unexpected argument '--title'" --msgbox Hello 8 30 -- --title X
golden msg_ddash_first 'usage, 255' 'rc 0' "1|unexpected argument '--msgbox'" -- --msgbox Hello 8 30
golden msg_colors  "'--colors: unknown option' rc 1" '\Z stripped' '0|msgbox|a\Zbbold\Zn c|8|30||colors=1;' --colors --msgbox 'a\Zbbold\Zn c' 8 30
golden msg_space   "' ' ignored, rc 0" 255 "1|unexpected argument ' '" --msgbox 'Hello world' 8 30 ' '
golden msg_okbutton 'OKB shown' 'OKB shown' '0|msgbox|Hello|8|30||ok=OKB;' --ok-button OKB --msgbox Hello 8 30
golden msg_oklabel "'--ok-label: unknown option' rc 1" 'OKL shown' '0|msgbox|Hello|8|30||ok=OKL;' --ok-label OKL --msgbox Hello 8 30
golden msg_noargs  'usage, 255' 'rc 0, nothing' '1|no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox, --menu, --checklist, --radiolist)'
golden msg_stdout  "'--stdout: unknown option' rc 1" 'rc 0' '0|msgbox|Hello|8|30||out=1;' --stdout --msgbox Hello 8 30
golden yn_button   'JAB / NEINB' 'JAB / NEINB' '0|yesno|q|8|30||no=NEINB;yes=JAB;' --yes-button JAB --no-button NEINB --yesno q 8 30
golden yn_label    "'--yes-label: unknown option' rc 1" 'JAL / NEINL' '0|yesno|q|8|30||no=NEINL;yes=JAL;' --yes-label JAL --no-label NEINL --yesno q 8 30
golden in_dashinit "'-x: unknown option' rc 1" "INIT '-x'" '0|inputbox|Name:|8|40|-x||' --inputbox 'Name:' 8 40 -x
golden in_ddinit   "INIT '--weird'" "INIT '--weird'" '0|inputbox|Name:|8|40|--weird||' --inputbox 'Name:' 8 40 -- --weird
golden in_optinit  'the title, no INIT' "'Expected a box option', 255" '0|inputbox|Name:|8|40||title=TT;' --inputbox 'Name:' 8 40 --title TT
golden in_stderr   "'--stderr: unknown option' rc 1" 'stderr' '0|inputbox|Name:|8|40|val||out=2;' --stderr --inputbox 'Name:' 8 40 val
golden in_cancel_label "'--cancel-label: unknown option' rc 1" 'CL (the last)' '0|inputbox|Name:|8|40|val||cancel=CL;' --cancel-button CB --cancel-label CL --inputbox 'Name:' 8 40 val
golden pw_insecure "'--insecure: unknown option' rc 1" 'accepted' '0|passwordbox|Password:|8|40||insecure=1;' --insecure --passwordbox 'Password:' 8 40
golden f_keeptite  'unknown option, rc 1' 'the alternate screen' '0|msgbox|hi|8|30||keeptite=1;' --keep-tite --msgbox hi 8 30
golden f_fullbuttons 'rc 0' "'Unknown option --fullbuttons.' 255" '0|msgbox|hi|8|30||fb=1;' --fullbuttons --msgbox hi 8 30
golden f_sepout    'rc 0' "'Unexpected widget with --separate-output', 255" '0|msgbox|hi|8|30||sepout=1;' --separate-output --msgbox hi 8 30
golden f_no_cancel 'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||nocancel=1;' --no-cancel --msgbox hi 8 30
golden f_helpbutton 'unknown option, rc 1' 'rc 0 (a Help button)' "1|option '--help-button' is not supported (outside fvdlg's whiptail / dialog subset)" --help-button --msgbox hi 8 30
golden f_andwidget 'unknown option, rc 1' 'both shown, rc 0' "1|option '--and-widget' is not supported (outside fvdlg's whiptail / dialog subset)" --msgbox a 8 30 --and-widget --msgbox b 8 30
golden f_gauge_missing 'usage, 255' 'rc 0' "1|'--gauge' is not supported yet" --gauge
golden msg_onlytitle 'usage, 255' 'rc 0, nothing' '1|no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox, --menu, --checklist, --radiolist)' --title T
golden menu_trailopt 'rc 0, TRAILT shown' "'Expected a box option', 255" '0|menu|Pick|15|40|4|a|Apple|b|Banana||title=TRAILT;' --menu 'Pick' 15 40 4 a Apple b Banana --title TRAILT
golden menu_dashtags 'tags - and --title (Down: --title)' "'Expected a box option', 255" '0|menu|Pick|15|40|4|-|Dash|--title|Title||' --menu 'Pick' 15 40 4 -- - Dash --title Title
golden menu_odd    'usage, 255' "'Expected 2 arguments, found extra 1', 255" "1|'--menu' takes TAG ITEM groups (3 words after LIST-HEIGHT: the last group is incomplete)" --menu 'Pick' 15 40 4 a Apple b
golden check_odd   'usage, 255' "'Expected 3 arguments, found extra 2', 255" "1|'--checklist' takes TAG ITEM STATUS groups (5 words after LIST-HEIGHT: the last group is incomplete)" --checklist 'Chk' 15 50 5 a A on b B
golden check_status 'ON 1 yes On all on' 'ON On on, 1 yes off' "1|STATUS must be on or off (got '1' for the tag 'b')" --checklist 'Chk' 15 50 5 a A ON b B 1 c C yes d D On
golden check_off_upper 'OFF Off off (golden2)' 'OFF Off off' '0|checklist|Chk|15|50|5|a|A|OFF|b|B|Off|c|C|on||' --checklist 'Chk' 15 50 5 a A OFF b B Off c C on
golden menu_empty  'usage, 255 (golden2)' "'Expected at least 20 tokens', 255" "1|'--menu' needs at least one TAG ITEM group (the list is empty)" --menu 'Pick' 15 40 4
golden check_empty 'rc 0, nothing (golden2)' "'Expected at least 20 tokens', 255" "1|'--checklist' needs at least one TAG ITEM STATUS group (the list is empty)" --checklist 'Chk' 15 50 5
golden radio_empty 'segfault, rc 139 (golden2)' "'Expected at least 20 tokens', 255" "1|'--radiolist' needs at least one TAG ITEM STATUS group (the list is empty)" --radiolist 'Rad' 15 50 5
golden msg_realnl  'rc 0, two lines' 'rc 0, two lines' $'0|msgbox|one\ntwo|10|30||' --msgbox $'one\ntwo' 10 30
golden msg_long    'rc 0' 'rc 0' '0|msgbox|The quick brown fox jumps over the lazy dog and keeps running far past the end of this box|0|0||' --msgbox 'The quick brown fox jumps over the lazy dog and keeps running far past the end of this box' 0 0
golden yn_00       'rc 0' 'rc 0' '0|yesno|Proceed?|0|0||' --yesno 'Proceed?' 0 0
golden info_00     'rc 0' 'rc 0' '0|infobox|Please wait|0|0||' --infobox 'Please wait' 0 0
golden info_clear  'rc 0' 'rc 0' '0|infobox|Please wait|8|30||clear=1;' --clear --infobox 'Please wait' 8 30
golden pw_abc      'no rc (a timing artefact; rerun pw_abc2: stderr abc)' "stderr 'pw'" '0|passwordbox|Password:|8|40||' --passwordbox 'Password:' 8 40

kt_test_section "002: the golden table's flag rows (f_*: --msgbox hi 8 30 with one flag; Enter)"
golden f_clear      'rc 0' 'rc 0' '0|msgbox|hi|8|30||clear=1;' --clear --msgbox hi 8 30
golden f_erase      'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||erase=1;' --erase-on-exit --msgbox hi 8 30
golden f_scrolltext 'Enter does not leave (f_scrolltext2: Tab Enter, rc 0)' 'rc 0' '0|msgbox|hi|8|30||scrolltext=1;' --scrolltext --msgbox hi 8 30
golden f_fb         'rc 0' 'rc 0' '0|msgbox|hi|8|30||fb=1;' --fb --msgbox hi 8 30
golden f_single     'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||single=1;' --single-quoted --msgbox hi 8 30
golden f_nocancel   'rc 0' 'rc 0' '0|msgbox|hi|8|30||nocancel=1;' --nocancel --msgbox hi 8 30
golden f_defaultno  'rc 0' 'rc 0' '0|msgbox|hi|8|30||defaultno=1;' --defaultno --msgbox hi 8 30
golden f_topleft    'rc 0' 'rc 0' '0|msgbox|hi|8|30||topleft=1;' --topleft --msgbox hi 8 30
golden f_nocollapse 'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||nocollapse=1;' --no-collapse --msgbox hi 8 30
golden f_crwrap     'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||crwrap=1;' --cr-wrap --msgbox hi 8 30
golden f_trim       'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||trim=1;' --trim --msgbox hi 8 30
golden f_insecure   'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||insecure=1;' --insecure --msgbox hi 8 30
golden f_ascii      'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||ascii=1;' --ascii-lines --msgbox hi 8 30
golden f_noshadow   'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||noshadow=1;' --no-shadow --msgbox hi 8 30
golden f_notags     'rc 0' 'rc 0' '0|msgbox|hi|8|30||notags=1;' --notags --msgbox hi 8 30
golden f_no_tags    'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||notags=1;' --no-tags --msgbox hi 8 30
golden f_noitem     'rc 0' 'rc 0' '0|msgbox|hi|8|30||noitem=1;' --noitem --msgbox hi 8 30
golden f_no_items   'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||noitem=1;' --no-items --msgbox hi 8 30
golden f_backtitle  'rc 0, BACKT shown' 'rc 0, BACKT shown' '0|msgbox|hi|8|30||backtitle=BACKT;' --backtitle BACKT --msgbox hi 8 30
golden f_cancelbutton 'rc 0' 'rc 0' '0|msgbox|hi|8|30||cancel=X;' --cancel-button X --msgbox hi 8 30
golden f_cancellabel 'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||cancel=X;' --cancel-label X --msgbox hi 8 30
golden f_yesbutton  'rc 0' 'rc 0' '0|msgbox|hi|8|30||yes=X;' --yes-button X --msgbox hi 8 30
golden f_yeslabel   'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||yes=X;' --yes-label X --msgbox hi 8 30
golden f_nobutton   'rc 0' 'rc 0' '0|msgbox|hi|8|30||no=X;' --no-button X --msgbox hi 8 30
golden f_nolabel    'unknown option, rc 1' 'rc 0' '0|msgbox|hi|8|30||no=X;' --no-label X --msgbox hi 8 30
golden f_defitem    'rc 0' 'rc 0' '0|msgbox|hi|8|30||defitem=X;' --default-item X --msgbox hi 8 30
golden f_extrabutton 'unknown option, rc 1' 'rc 0 (an Extra button)' "1|option '--extra-button' is not supported (outside fvdlg's whiptail / dialog subset)" --extra-button --msgbox hi 8 30
golden f_version    'rc 0' 'rc 0' '0|m:--version' --version

kt_test_section "002: TEXT as shown"
tx() {   # TITLE WANT TEXT [colors]
    local -A __fvl_o=()
    if [[ -n ${4-} ]]; then __fvl_o[colors]=1; fi
    fv.dlg._text "$3"
    fvw_check "$1" "$2" "$RESULT"
}
tx "\\n (two characters) is a newline (golden msg_nl: both tools)" $'one\ntwo' 'one\ntwo'
tx "a real newline stays" $'one\ntwo' $'one\ntwo'
tx "\\Z escapes kept without --colors (golden msg_nocolors: both tools show them)" 'a\Zbbold\Zn c' 'a\Zbbold\Zn c'
tx "\\Z escapes stripped with --colors (golden msg_colors: dialog)" 'abold c \Zx' 'a\Zbbold\Zn c\Z1\ZR \Zx' colors
tx "a backslash alone stays" 'a\b' 'a\b'
shopt -s nocasematch
tx "under nocasematch \\N stays text, \\z is not stripped" 'a\Nb\zb' 'a\Nb\zb' colors
shopt -u nocasematch
kt_test_start "the caller's nocasematch is kept"
if shopt -q nocasematch; then kt_test_fail "left on"; else shopt -s nocasematch; fv.dlg._text 'x'; if shopt -q nocasematch; then kt_test_pass ok; else kt_test_fail "turned off"; fi; shopt -u nocasematch; fi

kt_test_section "002: the fit of a text (auto size)"
fit() {   # TITLE MAXW TEXT WANT("tw th")
    local __fvl_tw __fvl_th
    fv.dlg._fit "$3" "$2"
    fvw_check "$1" "$4" "$__fvl_tw $__fvl_th"
}
fit "one short line: its width + 1" 40 'Hello' '6 1'
fit "two lines: the widest + 1, two rows" 40 $'Hello\nworld!!' '8 2'
fit "an empty text: one row" 40 '' '1 1'
fit "a trailing newline is a row" 40 $'a\n' '2 2'
fit "wide characters count two cells" 40 '中文' '5 1'
fit "a line wider than MAXW wraps at blanks" 10 'aaaa bbbb cccc' '10 2'
fit "a word longer than MAXW is cut" 5 'abcdefghij' '5 3'
fit "short lines next to a long one" 12 $'short\nthe quick brown fox' '12 3'

kt_test_log "002_Parse.sh completed"
