#!/usr/bin/env bash
# fvx_want.sh — the reference answers of fvx_testlib's child scene
# (fvx_scenefile), shared by 005_ZeroFork and 006_CallerState. Not a test
# file. The rows are the screen's text (rows 9 / 13 / 10 / 9 / 9 of the
# boxes), then the answers, the refusals' rc, the views left, '#same'.
FVX_WANT='░░░░░░░░░░░░░░░░░░░░║  Файл жук.txt: 12 строк              ║░░░░░░░░░░░░░░░░░░░░|░░░░░░░░░░░░░░░░░░░░║     Yes   ▄      No   ▄    Cancel ▄  ║░░░░░░░░░░░░░░░░░░░░|cmNo|cmNo|cmNo|░░╚══════════════════════════════════════╝░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░|cmCancel|░░░░░░░░░░║  Имя  старое                                             ║░░░░░░░░░░|░░░░░░░░░░║                                                          ║░░░░░░░░░░|cmOK:староеж中|░░░░░░░░░░║  Pass  ******                                            ║░░░░░░░░░░|░░░░░░░░░░║                                                          ║░░░░░░░░░░|cmOK:中|in:cmOK|cmCancel:keep|rc2:|rc2|rc2|live 0|#same'
