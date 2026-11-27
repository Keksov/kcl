#!/usr/bin/env bash
# fv.dlg.usage.sh — the command's --help / --version text, the one copy:
# bin/fvdlg sources it WITHOUT loading kbool (`fvdlg --help` costs bash's
# start only) and fv.dlg sources it for fv.dlg.main --help / --version
# (fv.dlg._usage). Not a unit: no kk.unit header, it defines no name.
#
#     source fv.dlg.usage.sh --help | --version
#
# Prints to stdout: rc 0, or printf's status when the write fails (a closed
# stdout, a full disk: the caller exits with it).
if [ "${1-}" = --version ]; then
    printf '%s\n' 'fvdlg 0.1 (kbool fv.dlg)'
    case $? in 0) return 0 2>/dev/null || exit 0 ;; *) return 1 2>/dev/null || exit 1 ;; esac
fi
printf '%s\n' \
    'Usage: fvdlg [OPTION...] WIDGET TEXT HEIGHT WIDTH [ARG...]' \
    'Free Vision dialogs for shell scripts (kbool fv.dlg); whiptail / dialog flags.' \
    '' \
    'Widgets:' \
    '  --msgbox TEXT H W            a message, OK' \
    '  --yesno TEXT H W             Yes / No (status 0 / 1)' \
    '  --infobox TEXT H W           drawn once, returns at once (stays on the screen)' \
    '  --inputbox TEXT H W [INIT]   a line of text, OK / Cancel' \
    '  --passwordbox TEXT H W [INIT]  the same, typed text shown as *' \
    '  --menu TEXT H W LH [TAG ITEM]...              one tag' \
    '  --checklist TEXT H W LH [TAG ITEM STATUS]...  the checked tags' \
    '  --radiolist TEXT H W LH [TAG ITEM STATUS]...  one tag (STATUS on / off)' \
    '  --gauge TEXT H W [PERCENT]   a progress bar; percentages read from stdin (a pipe)' \
    '                               one per line, XXX / PERCENT / TEXT... / XXX sets' \
    '                               the text too; status 0 at the end of stdin' \
    '  --textbox FILE H W           a file viewer (arrows, PgUp / PgDn, Home / End;' \
    '                               Left / Right scroll sideways), OK' \
    '' \
    'H / W: 0 = fit the text, -1 = the whole screen; LH: the list rows, 0 = fit.' \
    'Status: 0 OK / Yes, 1 Cancel / No, 255 Esc or an error (130 / 143 / 129:' \
    'Ctrl+C / SIGTERM / SIGHUP, the terminal restored).' \
    'The answer goes to stderr; --stdout, --output-fd N choose another.' \
    'A checklist answers "tag1" "tag2"; --separate-output one tag per line,' \
    '--single-quoted the form of dialog, --fv-output lines|quoted|single.' \
    '' \
    'The screen: the alternate screen per call (left as it was found);' \
    '--fv-screen main (or --erase-on-exit) draws on the screen itself and leaves' \
    'the last dialog there, the cursor on the last row; --clear / --erase-on-exit' \
    'clear the screen at the exit. --keep-tite = alternate. The infobox always' \
    'uses the screen itself.' \
    '' \
    'No terminal (no /dev/tty, TERM unset or dumb): status 255, unless' \
    '--no-tty=default (or FVDLG_NOTTY=default in the environment): then the' \
    'answer Enter would give, without a dialog. --no-tty=refuse overrides the' \
    'variable. FVDLG_FORCE=1: TERM unset / dumb is not taken for no terminal.' \
    '' \
    'Options: --title T --backtitle T --ok-button/--ok-label L --cancel-button/--cancel-label L' \
    '  --yes-button/--yes-label L --no-button/--no-label L --defaultno --nocancel/--no-cancel' \
    '  --default-item TAG --notags/--no-tags --noitem/--no-items --separate-output --single-quoted' \
    '  --stdout --stderr --output-fd N --colors --topleft --no-shadow --ascii-lines --scrolltext' \
    '  --clear --keep-tite --erase-on-exit --fb --insecure (accepted)' \
    '  --fv-palette gray|blue|cyan  --fv-ascii  --fv-mouse on|off  --fv-echo star|none' \
    '  --fv-screen alt|main  --fv-output lines|quoted|single  --no-tty=default|refuse' \
    '  --fv-headless [--fv-keys FILE] [--fv-size WxH] [--fv-out FILE]   (tests)' \
    '  --help  --version'
case $? in 0) return 0 2>/dev/null || exit 0 ;; *) return 1 2>/dev/null || exit 1 ;; esac
