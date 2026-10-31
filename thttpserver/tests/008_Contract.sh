#!/usr/bin/env bash
# 008_Contract.sh — thttpserver P0–P3: the kcl contract (kcl/README.md §1,
# PLAN §2.1) for the message classes, the replay transport, the router, the
# netcat transport, the server and (P3) the application and the examples.
#
# What it pins:
#
#   source integrity  `bash -n` on every unit file; no single-quoted printf
#                     format left open at end of line (the dangling-quote
#                     check); no inline `$'\r'` (it does not survive `build`,
#                     hence `__THS_CR`); no `$this.` internal call; the
#                     red-first sentinel gone; never `local TZ` and the Date in
#                     the `LC_ALL=C TZ=UTC0 printf -v` prefix form (C15); the
#                     file-scope constants; destructors freeing every extra
#                     per-instance array (router: _pat _met _hnd _kind _def
#                     _rdat, never _data); ONE write in SendContent, errors
#                     silenced; the scope — thttpserver.sh uses (kk.uses) the message,
#                     router and tstopwatch units and declares the transports
#                     and THttpServer, thttpapplication.sh (P3) uses the
#                     thttpserver and tcustomapplication units and declares
#                     THttpApplication only; the transport's FIFO writer is
#                     O_WRONLY (never `<>`), the close path never kills before
#                     the drain; (P3) the application's overrides pass "$@" on
#                     (C8), its destructor has no `inherited` (C9), Run wraps
#                     the inherited loop in BeginServe / EndServe (C11), the
#                     idle event lives in ServeOne, `Stopping` is read-only;
#                     the examples parse and never register a "$this.X"
#                     handler (kklass rewrote that text into a call form
#                     until its R2_P8; the examples keep "$__inst__.X").
#   set -eu           a child under `set -eu` loads the unit (twice) and runs
#                     the replay pipeline end to end, every parser status path,
#                     every guarded miss and refusal, the server over a replay
#                     transport (BeginServe / ServeOne / EndServe / Serve), the
#                     netcat transport's refusals, (P3) the application over a
#                     replay transport and its refusals, and exits clean.
#   §1.2 diagnostics  every rc 1 / rc 2 path: silent with the switch off,
#                     exactly ONE `kk.debug` line under VERBOSE_KKLASS=debug;
#                     the successful paths silent either way.
#   fork-free         THttpServer.ServeOne over TReplayTransport: BASHPID,
#                     PATH='', the stored request-path bodies, a DEBUG canary.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thttpserver.sh"
MSG="$UNIT_DIR/thttpmessage.sh"
ROUTER="$UNIT_DIR/thttprouter.sh"
APP="$UNIT_DIR/thttpapplication.sh"
EXAMPLES=("$UNIT_DIR/examples/demo.sh" "$UNIT_DIR/examples/demo_oop.sh")
source "$UNIT"
source "$APP"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"
OUTF="$TMP/contract.out"
FILES=("$MSG" "$ROUTER" "$UNIT" "$APP")

kt_test_section "008: the kcl contract for thttpserver (P0 – P3)"

# ===========================================================================
kt_test_section "0. source integrity"
# ===========================================================================

for f in "${FILES[@]}" "${EXAMPLES[@]}"; do
    kt_test_start "$(basename "$f") parses (bash -n)"
    if err="$("$BASH" -n "$f" 2>&1)"; then kt_test_pass "clean"; else kt_test_fail "bash -n: $err"; fi
done

kt_test_start "no single-quoted printf format is left open at end of line (dangling quote)"
bad=""
for f in "${FILES[@]}"; do
    if b="$(grep -nE "printf (-v [A-Za-z_]+ )?'[^']*\$" "$f")"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
done
if [[ -z "$bad" ]]; then kt_test_pass "none"; else kt_test_fail "$bad"; fi

kt_test_start "no inline \$'\\r' anywhere (build drops it) — __THS_CR is the only CR"
bad=""
for f in "${FILES[@]}"; do
    if b="$(grep -n "\$'\\\\r" "$f")"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
done
if [[ -z "$bad" ]]; then kt_test_pass "none"; else kt_test_fail "$bad"; fi

kt_test_start "no internal member call spelled \`\$this.NAME\`; no kklass internal read (\`_class_abstract\`, \`kk._class_derives_from\` — kklass R2_P9: kk.isAbstract, kk.derivesFrom)"
bad=""
for f in "${FILES[@]}"; do
    if b="$(grep -n '\$this\.' "$f")"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
    if b="$(grep -nE '_class_abstract|kk\._class_derives_from' "$f" | grep -v '^[0-9]*:[[:space:]]*#')"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
done
if [[ -z "$bad" ]]; then kt_test_pass "none"; else kt_test_fail "$bad"; fi

kt_test_start "the red-first sentinel __THS_PENDING__ is gone"
if grep -n '__THS_PENDING__' "${FILES[@]}" >/dev/null; then kt_test_fail "skeleton still in place"; else kt_test_pass "gone"; fi

kt_test_start "never \`local TZ\`; the Date is the prefix form \`LC_ALL=C TZ=UTC0 printf -v …'%(%a, %d %b %Y %H:%M:%S GMT)T' -1\`"
if ! grep -nE 'local[^#]*\bTZ=' "${FILES[@]}" >/dev/null \
   && grep -F "LC_ALL=C TZ=UTC0 printf -v __ths_date '%(%a, %d %b %Y %H:%M:%S GMT)T' -1" "$MSG" >/dev/null; then
    kt_test_pass "prefix form, no local TZ"
else
    kt_test_fail "Date idiom missing or local TZ present"
fi

kt_test_start "file-scope constants: __THS_CR is one CR; __THS_REASON is an assoc with the parser statuses"
bad=""
[[ "${__THS_CR:-}" == $'\r' ]] || bad+=" __THS_CR"
[[ "$(declare -p __THS_REASON 2>/dev/null)" == "declare -A"* ]] || bad+=" __THS_REASON-not-assoc"
for c in 200 400 408 413 414 431 500 501 505; do [[ -n "${__THS_REASON[$c]:-}" ]] || bad+=" reason-$c"; done
if [[ -z "$bad" ]]; then kt_test_pass "both"; else kt_test_fail "$bad"; fi

kt_test_start "destructors free every extra per-instance array (request _hdr _hdrn _qf _rp, response _hdr _hdrn, replay _rqf _rsf)"
bad=""
d="$(sed -n '/^THttpRequest.Destroy()/,/^}/p' "$MSG")"
for s in _hdr _hdrn _qf _rp; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" req$s"; done
[[ "$d" == *'unset -v'* ]] || bad+=" req-no-unset"
d="$(sed -n '/^THttpResponse.Destroy()/,/^}/p' "$MSG")"
for s in _hdr _hdrn; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" resp$s"; done
d="$(sed -n '/^TReplayTransport.Destroy()/,/^}/p' "$UNIT")"
for s in _rqf _rsf; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" replay$s"; done
[[ "$d" == *inherited* ]] || bad+=" replay-no-inherited"
d="$(sed -n '/^THttpRouter.Destroy()/,/^}/p' "$ROUTER")"
for s in _pat _met _hnd _kind _def _rdat; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" router$s"; done
[[ "$d" == *'unset -v'* ]] || bad+=" router-no-unset"
if grep -n '_data' "$ROUTER" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then bad+=" router-touches-_data"; fi
d="$(sed -n '/^THttpRouteObject.Destroy()/,/^}/p' "$ROUTER")"
[[ -n "$d" && "${THttpRouteObject_destructor_name:-}" == Destroy ]] || bad+=" routeobject-no-destructor"
d="$(sed -n '/^TNetcatTransport.Destroy()/,/^}/p' "$UNIT")"
[[ "$d" == *Shutdown* && "$d" == *inherited* ]] || bad+=" netcat-destroy"
d="$(sed -n '/^THttpServer.Destroy()/,/^}/p' "$UNIT")"
[[ "$d" == *EndServe* && "$d" == *'_sw.delete'* ]] || bad+=" server-destroy"
if grep -nE '_data\b' "$UNIT" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then bad+=" server-file-touches-_data"; fi
if [[ -z "$bad" ]]; then kt_test_pass "all fourteen arrays, replay/netcat chain with inherited, THttpRouteObject has a destructor, the server frees its own objects, nobody names _data"; else kt_test_fail "$bad"; fi

kt_test_start "SendContent writes with ONE printf to the fd, stderr silenced before the fd redirection"
b="$(sed -n '/^THttpResponse.SendContent()/,/^}/p' "$MSG")"
nw=0; while IFS= read -r l; do [[ "$l" == *'>&$__ths_fd'* ]] && nw=$(( nw + 1 )); done <<< "$b"
if [[ $nw -eq 1 && "$b" == *"printf '%s' \"\$__ths_out\" 2>/dev/null >&\$__ths_fd"* ]]; then kt_test_pass "one write"; else kt_test_fail "writes=$nw"; fi

kt_test_start "scope: thttpserver.sh is a unit whose dependencies are \`kk.uses kklass_pascal || return\` and \`kk.uses thttpmessage thttprouter tstopwatch || return\`, with no \`source\` line (kklass/USES_PLAN.md U4 rule 3, amendment b); declares exactly the two transports + TNetcatTransport + TSocatTransport (L2.7-N2) + THttpServer; the application is in its own file"
srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$UNIT" || :)"
uses="$(grep -E '^[[:space:]]*kk\.uses[[:space:]]' "$UNIT" || :)"
cls="$(grep -E '^class ' "$UNIT" || :)"
if [[ -z "$srcs" && "$uses" == $'kk.uses kklass_pascal || return\nkk.uses thttpmessage thttprouter tstopwatch || return' \
      && "$cls" == $'class THttpTransport\nclass TReplayTransport : THttpTransport\nclass TNetcatTransport : THttpTransport\nclass TSocatTransport : TNetcatTransport\nclass THttpServer' ]] \
   && ! grep -nE '^class THttpApplication' "$UNIT" "$ROUTER" "$MSG" >/dev/null; then
    kt_test_pass "two kk.uses lines, no source; five classes; no application here"
else
    kt_test_fail "source: ${srcs//$'\n'/ | }; kk.uses: ${uses//$'\n'/ | }; classes: ${cls//$'\n'/ | }"
fi

kt_test_start "P3 scope: thttpapplication.sh is a unit whose dependencies are \`kk.uses kklass_pascal || return\` and \`kk.uses thttpserver tcustomapplication || return\`, with no \`source\` line (kklass/USES_PLAN.md U4 rule 3, amendment b); declares exactly 'class THttpApplication : TCustomApplication'"
srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$APP" || :)"
uses="$(grep -E '^[[:space:]]*kk\.uses[[:space:]]' "$APP" || :)"
cls="$(grep -E '^class ' "$APP" || :)"
if [[ -z "$srcs" && "$uses" == $'kk.uses kklass_pascal || return\nkk.uses thttpserver tcustomapplication || return' \
      && "$cls" == 'class THttpApplication : TCustomApplication' ]]; then
    kt_test_pass "two kk.uses lines, no source; one class"
else
    kt_test_fail "source: ${srcs//$'\n'/ | }; kk.uses: ${uses//$'\n'/ | }; classes: ${cls//$'\n'/ | }"
fi

kt_test_start "P3 C8/C9/C11: every override passes \"\$@\" to inherited; no bare inherited outside the constructor; Destroy has NO inherited (TCustomApplication has no destructor) and frees _server and _router; Run = BeginServe → inherited Run → EndServe"
bad=""
for m in Initialize Run Terminate; do
    b="$(sed -n "/^THttpApplication.$m()/,/^}/p" "$APP")"
    [[ "$b" == *"inherited $m \"\$@\""* ]] || bad+=" $m-no-args"
done
b="$(sed -n '/^THttpApplication.Create()/,/^}/p' "$APP")"
[[ "$b" == *$'\n    inherited\n'* ]] || bad+=" ctor-no-inherited"
for m in Destroy Initialize RegisterRoute Run DoRun Terminate; do
    b="$(sed -n "/^THttpApplication.$m()/,/^}/p" "$APP")"
    if grep -qE '(^|[[:space:];])inherited[[:space:]]*($|;)' <<< "$b"; then bad+=" bare-inherited-in-$m"; fi
done
b="$(sed -n '/^THttpApplication.Destroy()/,/^}/p' "$APP")"
[[ "$b" != *inherited* && "$b" == *'"$_server.delete"'* && "$b" == *'"$_router.delete"'* ]] || bad+=" destroy"
[[ -z "${TCustomApplication_destructor_name:-}" && "${THttpApplication_destructor_name:-}" == Destroy ]] || bad+=" destructor-names(${TCustomApplication_destructor_name:-}/${THttpApplication_destructor_name:-})"
b="$(sed -n '/^THttpApplication.Run()/,/^}/p' "$APP")"
ib="${b%%'.BeginServe"'*}"; ii="${b%%'inherited Run'*}"; ie="${b%%'.EndServe"'*}"
(( ${#ib} < ${#ii} && ${#ii} < ${#ie} && ${#ie} < ${#b} )) || bad+=" run-order"
if [[ -z "$bad" ]]; then kt_test_pass "as specified"; else kt_test_fail "$bad"; fi

kt_test_start "P3 server surface: 'property Stopping read _stop' (read-only view of the private flag); OnAcceptIdle fired by ServeOne, no longer by Serve's loop"
b="$(sed -n '/^THttpServer.Serve()/,/^}/p' "$UNIT")"
b1="$(sed -n '/^THttpServer.ServeOne()/,/^}/p' "$UNIT")"
if grep -qE '^[[:space:]]+property Stopping[[:space:]]+read _stop$' "$UNIT" && [[ "$b" != *OnAcceptIdle* && "$b1" == *'"$OnAcceptIdle" "$__inst__"'* ]]; then
    kt_test_pass "as specified"
else
    kt_test_fail "Stopping/OnAcceptIdle placement differs"
fi

kt_test_start "the examples register no \"\$this.X\" handler (until kklass R2_P8 the text \$this.NAME of a member body was rewritten into 'INST.call NAME'; they keep \"\$__inst__.X\"); each resolves nc and prints its URL"
bad=""
for f in "${EXAMPLES[@]}"; do
    if grep -nE 'RegisterRoute[^#]*"\$this\.' "$f" >/dev/null; then bad+=" $(basename "$f"):this-handler"; fi
    grep -q 'KCL_NC=/c/bin/msys64/usr/bin/nc.exe' "$f" || bad+=" $(basename "$f"):no-nc-fallback"
    grep -q "printf 'kcl demo.*http://%s:%s/" "$f" || bad+=" $(basename "$f"):no-url"
done
if [[ -z "$bad" ]]; then kt_test_pass "both"; else kt_test_fail "$bad"; fi

kt_test_start "the transport's mechanism (PLAN §2.5, C1–C4): the FIFO writer is opened O_WRONLY (never '<>'), nc's stdin through 'exec cat' (a FIFO relay unlinked after its open, L3.5-7), a FRESH FIFO per listener (L3.5-10), the child closes the other slot's fds, nc -vv"
b="$(sed -n '/^TNetcatTransport._spawn()/,/^}/p' "$UNIT")"
a="$(sed -n '/^TNetcatTransport.BuildArgv()/,/^}/p' "$UNIT")"
bad=""
[[ "$b" == *'exec {__ths_wr}>"'* ]] || bad+=" no-O_WRONLY-writer"
[[ "$b" == *'<>'* ]] && bad+=" O_RDWR"
[[ "$b" == *'ths._relayExec "$__ths_dir/err$__ths_s" <(exec cat "$__ths_ff" '* ]] || bad+=" no-cat-relay"
# launch L3.5-10: every listener gets a FRESH FIFO (_newFifo: fifo.N, N = _gen counted up, batch mkfifo) before the writer opens it
nf="$(sed -n '/^TNetcatTransport._newFifo()/,/^}/p' "$UNIT")"
[[ "$b" == *'"$__inst__._newFifo" "$__ths_s"'*'__ths_ff="$__ths_fS"'*'exec {__ths_wr}>"$__ths_ff"'* ]] || bad+=" no-fresh-fifo"
[[ "$nf" == *'__ths_fS="$_dir/fifo.$_gen"'*'_gen=$(( _gen + 1 ))'* && "$nf" == *'command mkfifo -- "${__ths_l[@]}"'* && "$nf" == *'command rm -f -- "${__ths_l[@]}"'* ]] || bad+=" fifo-reused"
if grep -n '/fifo\$__ths_s\|/fifo[01]"' "$UNIT" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then bad+=" fixed-fifo-name"; fi
rx="$(sed -n '/^ths._relayExec()/,/^}/p' "$UNIT")"
# launch L3.5-7: a FIFO relay (named like bash's sh-np.* / sh-np-N FIFOs) is unlinked right after its open, before the exec
[[ "$rx" == *'exec <"$__ths_p"'*'== sh-np[.-]*'*'rm -f -- "$__ths_p"'*'exec "$@" 2>"$__ths_e"'* ]] || bad+=" relay-fifo-not-unlinked"
[[ "$b" == *'if [[ -n "$__ths_wo" ]]; then exec {__ths_wo}>&-; fi'*'if [[ -n "$__ths_ro" ]]; then exec {__ths_ro}<&-; fi'*'exec "${ths_argv[@]}"'* ]] || bad+=" child-keeps-other-slot"
[[ "$a" == *'-l -c -vv -n -w'* ]] || bad+=" argv"
if grep -n '<>' "$UNIT" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v '/dev/ptmx' >/dev/null; then bad+=" <>-somewhere"; fi
if [[ -z "$bad" ]]; then kt_test_pass "as measured"; else kt_test_fail "$bad"; fi

kt_test_start "the drained close (C2): wr closed, rd drained to EOF under CloseTimeout, rd closed, kill (ths._stopPid) ONLY past the deadline, every kill/wait silenced"
b="$(sed -n '/^TNetcatTransport._closeSlot()/,/^}/p' "$UNIT")"
s="$(sed -n '/^TNetcatTransport.Shutdown()/,/^}/p' "$UNIT")"
bad=""
iw="${b%%'exec {__ths_wr}>&-'*}"; ir="${b%%'exec {__ths_rd}<&-'*}"; ik="${b%%ths._stopPid*}"; iwt="${b%%'wait "$__ths_pid"'*}"
(( ${#iw} < ${#ir} && ${#ir} < ${#ik} && ${#ik} < ${#iwt} )) || bad+=" order"
[[ "$b" == *'read -r -d '"''"' -n 8192 -t'* ]] || bad+=" no-drain"
[[ "$b" == *'if (( ! __ths_eof )); then'*'ths._stopPid "$__ths_pid"'* ]] || bad+=" kill-not-deadline-only"
[[ "$b" == *'wait "$__ths_pid" 2>/dev/null ||'* ]] || bad+=" wait-not-silenced"
[[ "$s" == *'ths._stopPid "$__ths_pid"'* && "$s" == *'wait "$__ths_pid" 2>/dev/null || :'* ]] || bad+=" shutdown-not-silenced"
# launch L3.5-10: after the listener's wait the slot's FIFO is dropped (queued in _dead, never reopened); no relay is signalled (no pid of a process that is not ours)
ir2="${b%%'wait "$__ths_pid"'*}"; ifd="${b%%'_dead+='*}"
(( ${#ir2} < ${#ifd} )) && [[ "$b" == *'_dead+="${_dead:+ }${__ths_fS##*/fifo.}"'*'__ths_fS=""'* ]] || bad+=" fifo-not-dropped"
if grep -n 'relay\$\|__ths_rp' "$UNIT" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then bad+=" relay-pid-signalled"; fi
sp="$(sed -n '/^ths._stopPid()/,/^}/p' "$UNIT")"
[[ "$sp" == *'kill -TERM'*'kill -KILL'*'/usr/bin/kill -f -9'* ]] || bad+=" stopPid-no-escalation"
if [[ -z "$bad" ]]; then kt_test_pass "close wr → drain → close rd → ths._stopPid (TERM → KILL → kill -f -9) past deadline → wait"; else kt_test_fail "$bad"; fi

kt_test_start "the server never touches EXIT; traps restored as 'trap - INT TERM PIPE; eval \"\$_savedTraps\"'; the ONE fork of Serve is the trap -p capture"
b="$(sed -n '/^THttpServer.EndServe()/,/^}/p' "$UNIT")"
bs="$(sed -n '/^THttpServer.BeginServe()/,/^}/p' "$UNIT")"
if ! grep -nE "^[^#]*trap[^#]*EXIT" "$UNIT" >/dev/null && [[ "$b" == *'trap - INT TERM PIPE'*'eval "$_savedTraps"'* \
      && "$bs" == *'_savedTraps="$(trap -p INT TERM PIPE)"'* && "$bs" == *"trap '' PIPE"* ]]; then
    kt_test_pass "as specified"
else
    kt_test_fail "EndServe/BeginServe trap handling differs"
fi

kt_test_start "thttprouter.sh: a unit whose only dependencies are \`kk.uses kklass_pascal || return\` and \`kk.uses thttpmessage || return\` (never the entry point), with no \`source\` line (kklass/USES_PLAN.md U4 rule 3); declares exactly THttpRouteObject and THttpRouter"
srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$ROUTER" || :)"
uses="$(grep -E '^[[:space:]]*kk\.uses[[:space:]]' "$ROUTER" || :)"
cls="$(grep -E '^class ' "$ROUTER" || :)"
if [[ -z "$srcs" && "$uses" == $'kk.uses kklass_pascal || return\nkk.uses thttpmessage || return' \
      && "$cls" == $'class THttpRouteObject\nclass THttpRouter' ]]; then
    kt_test_pass "two kk.uses lines, no source; two classes"
else
    kt_test_fail "source: ${srcs//$'\n'/ | }; kk.uses: ${uses//$'\n'/ | }; classes: ${cls//$'\n'/ | }"
fi

kt_test_start "the router sourced ALONE (fresh child) loads its classes and the message classes it needs"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
out="$(ROUTER="$ROUTER" "$KT_TIMEOUT" 180 "$BASH" -c 'source "$ROUTER"; THttpRouter.new X; THttpRequest.new Y; X.RouteCount; printf "%s" "$RESULT"; X.delete; Y.delete' 2>&1 </dev/null)"
if [[ "$out" == "0" ]]; then kt_test_pass "standalone"; else kt_test_fail "out='${out:0:200}'"; fi
fi   # kt_need_timeout

# ===========================================================================
kt_test_section "1. set -eu"
# ===========================================================================

# expect_clean TITLE SNIPPET — a CHILD under `set -eu` with the unit freshly
# sourced; it must end rc 0, print exactly OK and write nothing to stderr.
expect_clean() {
    local title="$1" snippet="$2" out rc err
    kt_test_start "$title"
    if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"; return 0; fi
    : > "$ERRF"
    out="$(TMP="$TMP" UNIT="$UNIT" UNIT_DIR="$UNIT_DIR" "$KT_TIMEOUT" 180 "$BASH" -c "set -eu
source \"\$UNIT\"
$snippet
printf OK" 2>"$ERRF" </dev/null)"; rc=$?
    err="$(<"$ERRF")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "[$title] rc=$rc out='${out:0:200}' stderr='${err:0:300}'"
    fi
}

printf 'POST /p?a=1&=&b=%%41 HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\n\r\nxyz' > "$TMP/ok.req"
printf 'GET http://x/ HTTP/1.1\r\nHost: h\r\n\r\n' > "$TMP/400.req"
printf 'GET / HT' > "$TMP/gone.req"
printf 'POST / HTTP/1.0\r\nContent-Length: 70000\r\n\r\n' > "$TMP/413.req"

expect_clean "the unit loads under set -eu, and loads again (every re-source guard holds)" '
source "$UNIT"
source "$UNIT"'

expect_clean "the replay pipeline end to end: accept, parse, answer, send, close, free" '
TReplayTransport.new T
T.AddRequestFile "$TMP/ok.req"
T.Accept 0 10
T.InFd; in="$RESULT"; T.OutFd; out="$RESULT"
THttpRequest.new R; THttpResponse.new S
S.Attach "$out" 0
dl=$(( ${EPOCHREALTIME//[!0-9]/} + 10000000 ))
R.ReadFrom "$in" "$dl" 65536
[[ "$RESULT" == "0" ]] || { printf "status=%s\n" "$RESULT" >&2; exit 9; }
R.Method; S.Write "$RESULT"
R.QueryField b; S.Write "$RESULT"
R.ContentLength; S.Write "$RESULT"
declare -a N=(); R.HeaderNames N
S.SetCustomHeader X-A 1
S.SendContent
S.ContentSent; [[ "$RESULT" == "1" ]] || exit 8
T.CloseConnection
R.delete; S.delete
T.ResponseFile 0; f="$RESULT"
body="$(<"$f")"; [[ "$body" == *"POSTA3" ]] || { printf "body=%s\n" "$body" >&2; exit 7; }
T.Shutdown
T.delete'

expect_clean "non-zero parser statuses are rc 0 (a value, not a miss): 400, 413, gone, 408" '
THttpRequest.new R
for f in 400 413 gone; do
    exec {fd}<"$TMP/$f.req"
    R.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536
    [[ "$RESULT" == "$f" ]] || { printf "%s → %s\n" "$f" "$RESULT" >&2; exit 9; }
    exec {fd}<&-
done
exec {fd}<"$TMP/ok.req"
R.ReadFrom "$fd" 0 65536
[[ "$RESULT" == "408" ]] || exit 8
exec {fd}<&-
R.delete'

expect_clean "misses and refusals under set -eu, each guarded: request" '
THttpRequest.new R
rc=0
R.GetHeader x || rc=$?;          [[ $rc -eq 1 ]] || exit 9; rc=0
R.GetHeader "" || rc=$?;         [[ $rc -eq 2 ]] || exit 8; rc=0
R.QueryField q || rc=$?;         [[ $rc -eq 1 ]] || exit 7; rc=0
R.RouteParam p || rc=$?;         [[ $rc -eq 1 ]] || exit 6; rc=0
R.SetRouteParam "" v || rc=$?;   [[ $rc -eq 2 ]] || exit 5; rc=0
R.HeaderNames 1bad || rc=$?;     [[ $rc -eq 2 ]] || exit 4; rc=0
R.ReadFrom x y z || rc=$?;       [[ $rc -eq 2 ]] || exit 3; rc=0
if R.HasHeader host; then exit 2; fi
R.ContentLength; [[ "$RESULT" == "0" ]] || exit 1
R.delete'

expect_clean "misses and refusals under set -eu, each guarded: response and replay" '
THttpResponse.new S
rc=0
S.SetCustomHeader "a b" v || rc=$?;  [[ $rc -eq 2 ]] || exit 9; rc=0
S.GetCustomHeader x || rc=$?;        [[ $rc -eq 1 ]] || exit 8; rc=0
S.Attach abc || rc=$?;               [[ $rc -eq 2 ]] || exit 7; rc=0
S.SendRedirect /p 200 || rc=$?;      [[ $rc -eq 2 ]] || exit 6; rc=0
S.SendContent || rc=$?;              [[ $rc -eq 1 ]] || exit 5; rc=0
S.Code = 99
exec {fd}>"$TMP/v500.cap"
S.Attach "$fd" 0
S.SendContent
S.SendContent || rc=$?;              [[ $rc -eq 1 ]] || exit 4; rc=0
exec {fd}>&-
S.Code; [[ "$RESULT" == "500" ]] || exit 3
S.delete
TReplayTransport.new T
T.AddRequestFile "" || rc=$?;        [[ $rc -eq 2 ]] || exit 2; rc=0
T.Accept 0 10 || rc=$?;              [[ $rc -eq 2 ]] || exit 1; rc=0
T.ResponseFile 0 || rc=$?;           [[ $rc -eq 1 ]] || exit 10; rc=0
T.CloseConnection
T.delete'

printf 'GET /u/7/a/b HTTP/1.0\r\n\r\n' > "$TMP/route.req"
printf 'PUT /u/7/a/b HTTP/1.0\r\n\r\n' > "$TMP/route405.req"
printf 'GET /none HTTP/1.0\r\n\r\n' > "$TMP/route404.req"

expect_clean "the router end to end: register the three kinds, route 200/405/404, a failing handler, free" '
class TEuRoute : THttpRouteObject
    public
        override proc HandleRequest
end
TEuRoute.HandleRequest() { $2.Write "obj:$RouteData"; }
build TEuRoute
class TEuCtl
    public
        constructor Create
        proc Hit
end
TEuCtl.Create() { :; }
TEuCtl.Hit() { $2.Write "ctl:$3"; }
build TEuCtl
TEuCtl.new C
fn() { local id; $1.RouteParam id; id="$RESULT"; $2.Write "fn:$id:$3"; }
bad() { return 3; }
THttpRouter.new RT
RT.RegisterRoute /u/:id/*rest GET fn 0 d1
RT.RegisterRoute /c GET C.Hit 0 d2
RT.RegisterRoute /o GET TEuRoute 0 d3
RT.RegisterRoute /bad POST bad
RT.RegisterRoute /any ALL fn 1
RT.RouteCount; [[ "$RESULT" == 5 ]] || exit 9
RT.FindRoute /c GET; [[ "$RESULT" == 1 ]] || exit 8
RT.FindRoute /c HEAD
RT.BeforeRequest = fn
RT.BeforeRequest = ""
for f in route route405 route404; do
    TReplayTransport.new T
    T.AddRequestFile "$TMP/$f.req"
    T.Accept 0 10
    T.InFd; in="$RESULT"; T.OutFd; out="$RESULT"
    THttpRequest.new R; THttpResponse.new S
    S.Attach "$out" 0
    R.ReadFrom "$in" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536
    RT.RouteRequest R S
    S.SendContent
    T.CloseConnection
    T.ResponseFile 0; cap="$(<"$RESULT")"
    case $f in
        route)    [[ "$cap" == *"fn:7:d1" ]] || exit 7 ;;
        route405) [[ "$cap" == "HTTP/1.1 405 "* && "$cap" == *"Allow: GET, HEAD"* ]] || exit 6 ;;
        route404) [[ "$cap" == *"fn::"* ]] || exit 5 ;;
    esac
    R.delete; S.delete; T.delete
done
C.delete
RT.delete'

expect_clean "router misses and refusals under set -eu, each guarded" '
THttpRouter.new RT
fn() { :; }
rc=0
RT.RegisterRoute || rc=$?;                     [[ $rc -eq 2 ]] || exit 9; rc=0
RT.RegisterRoute /x fn 0 || rc=$?;             [[ $rc -eq 2 ]] || exit 8; rc=0
RT.RegisterRoute /x GET "a b" || rc=$?;        [[ $rc -eq 2 ]] || exit 7; rc=0
RT.RegisterRoute "/*a/b" GET fn || rc=$?;      [[ $rc -eq 2 ]] || exit 6; rc=0
RT.RegisterRoute /x GET THttpRouteObject || rc=$?; [[ $rc -eq 2 ]] || exit 5; rc=0
RT.RegisterRoute /d GET fn 1
RT.RegisterRoute /e GET fn 1 || rc=$?;         [[ $rc -eq 1 ]] || exit 4; rc=0
RT.FindRoute /none PUT || rc=$?;               [[ $rc -eq 1 && "$REPLY" == 404 ]] || exit 3; rc=0
RT.FindRoute /d || rc=$?;                      [[ $rc -eq 2 ]] || exit 2; rc=0
RT.RouteRequest || rc=$?;                      [[ $rc -eq 2 ]] || exit 1; rc=0
THttpRouteObject.new X 2>/dev/null || rc=$?;   [[ $rc -eq 1 ]] || exit 10; rc=0
RT.delete'

printf 'GET /a HTTP/1.0\r\n\r\n' > "$TMP/s1.req"

expect_clean "the server over a replay transport: BeginServe, ServeOne x5 (200, 400, gone, 200, fatal), EndServe, Serve, Active, Terminate, free" '
fa() { $2.Write "a"; }
bad() { return 5; }
lg() { :; }
THttpRouter.new RT
RT.RegisterRoute /a GET fa
RT.RegisterRoute /p POST fa
TReplayTransport.new T
for f in s1 400 gone ok; do T.AddRequestFile "$TMP/$f.req"; done
THttpServer.new S
S.Transport = T
S.Router = RT
S.OnLog = lg
S.BeginServe
S.Active; [[ "$RESULT" == 1 ]] || exit 11
S.ServeOne; [[ "$RESULT" == 200 ]] || exit 9
S.ServeOne; [[ "$RESULT" == 400 ]] || exit 8
S.ServeOne; [[ "$RESULT" == gone ]] || exit 7
S.ServeOne; [[ "$RESULT" == 200 ]] || exit 6
rc=0; S.ServeOne || rc=$?; [[ $rc -eq 2 ]] || exit 5; rc=0
S.EndServe
S.RequestCount; [[ "$RESULT" == 3 ]] || exit 4
S.Active; [[ "$RESULT" == 0 ]] || exit 3
TReplayTransport.new T2
T2.AddRequestFile "$TMP/s1.req"
S.Transport = T2
S.OnRequest = bad
S.Serve || rc=$?; [[ $rc -eq 1 ]] || exit 2; rc=0
S.LastError; [[ -n "$RESULT" ]] || exit 1
S.Terminate
S.Active = false
S.delete; T.delete; T2.delete; RT.delete'

# A fake GNU netcat for the BuildArgv case below (L2.7-N1: an nc that is not
# identified as GNU netcat is refused, so $BASH no longer stands in for nc).
printf '#!%s\nprintf "netcat (The GNU Netcat) 0.7.1\\n"\n' "$BASH" > "$TMP/gnunc"
chmod +x "$TMP/gnunc"

expect_clean "TNetcatTransport under set -eu: BuildArgv, every refusal guarded, Close/Shutdown with nothing open, free" '
TNetcatTransport.new N
N.NcBinary = /no/such/nc
rc=0
N.BuildArgv 1bad || rc=$?;          [[ $rc -eq 2 ]] || exit 9; rc=0
N.BuildArgv A || rc=$?;             [[ $rc -eq 1 ]] || exit 8; rc=0
N.Accept x 1 || rc=$?;              [[ $rc -eq 2 ]] || exit 7; rc=0
N.Accept 0 10 || rc=$?;             [[ $rc -eq 2 ]] || exit 6; rc=0
N.LastError; [[ "$RESULT" == "nc not found"* ]] || exit 5
N.NcBinary = "$TMP/gnunc"
N.Port = 0
N.BuildArgv A || rc=$?;             [[ $rc -eq 2 ]] || exit 4; rc=0
N.Port = 8080
declare -a A=()
N.BuildArgv A
[[ "$RESULT" == 11 && "${A[0]}" == "$TMP/gnunc" && "${A[*]:1}" == "-l -c -vv -n -w 60 -s 127.0.0.1 -p 8080" ]] || exit 3
N.CloseConnection
N.Shutdown
N.delete'

printf 'POST /q HTTP/1.0\r\n\r\n' > "$TMP/q.req"

expect_clean "THttpApplication under set -eu (P3): options, routes before Initialize, Run over replay (MaxRequests and the fatal path), every refusal guarded, free" '
source "$UNIT_DIR/thttpapplication.sh"
source "$UNIT_DIR/thttpapplication.sh"
fa() { $2.Write "a"; }
q()  { App.Terminate; $2.Write q; }
THttpApplication.new App -p 9100 --address=127.0.0.3
App.RegisterRoute /a GET fa
App.RegisterRoute /q POST q
rc=0
App.RegisterRoute /x GET "no such" || rc=$?;  [[ $rc -eq 2 ]] || exit 9; rc=0
App.Run || rc=$?;                             [[ $rc -eq 2 ]] || exit 8; rc=0
App.ServerClass = THttpRouter
App.Initialize || rc=$?;                      [[ $rc -eq 2 ]] || exit 7; rc=0
App.ServerClass = THttpServer
App.Initialize
App.Port; [[ "$RESULT" == 9100 ]] || exit 6
App.Address; [[ "$RESULT" == 127.0.0.3 ]] || exit 5
App.Server; s="$RESULT"
TReplayTransport.new T
T.AddRequestFile "$TMP/s1.req"; T.AddRequestFile "$TMP/q.req"; T.AddRequestFile "$TMP/s1.req"
"$s.Transport" = T
App.Run
"$s.RequestCount"; [[ "$RESULT" == 2 ]] || exit 4
App.Initialize
App.Server; s="$RESULT"
TReplayTransport.new T2
T2.AddRequestFile "$TMP/s1.req"
"$s.Transport" = T2
App.Run || rc=$?;                             [[ $rc -eq 1 ]] || exit 3; rc=0
App.Terminate
App.Terminate x || rc=$?;                     [[ $rc -eq 1 ]] || exit 2; rc=0
App.delete; T.delete; T2.delete'

# ===========================================================================
kt_test_section "2. §1.2: one kk.debug line on every rc 1 / rc 2 path, none otherwise"
# ===========================================================================

THttpRequest.new DR; THttpResponse.new DS; TReplayTransport.new DT
printf 'GET / HTTP/1.0\r\nX-A: 1\r\n\r\n' > "$TMP/d.req"
fd=""; exec {fd}<"$TMP/d.req"; DR.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536; exec {fd}<&-

# lines RC CALL... — run CALL twice (switch off, switch on); stdout must be
# empty both times; stderr 0 lines off, WANT lines on.
lines() {
    local want="$1" wrc="$2"; shift 2
    local r1=0 r2=0 o1 o2 e1 e2 n=0 l
    "$@" >"$OUTF" 2>"$ERRF" || r1=$?
    o1="$(<"$OUTF")"; e1="$(<"$ERRF")"
    VERBOSE_KKLASS=debug "$@" >"$OUTF" 2>"$ERRF" || r2=$?
    o2="$(<"$OUTF")"; e2="$(<"$ERRF")"
    if [[ -n "$e2" ]]; then while IFS= read -r l; do n=$(( n + 1 )); done <<< "$e2"; fi
    if [[ $r1 -eq $wrc && $r2 -eq $wrc && -z "$o1$o2" && -z "$e1" && $n -eq $want ]]; then
        kt_test_pass "rc $r1; off: silent; debug: $n line(s)"
    else
        kt_test_fail "[$*] rc=$r1/$r2 (want $wrc) stdout='${o1:0:40}|${o2:0:40}' off='${e1:0:80}' debug-lines=$n (want $want) '${e2:0:120}'"
    fi
}
dcase() { kt_test_start "$1"; shift; lines "$@"; }
dcase "GetHeader miss"                1 1 DR.GetHeader x-none
dcase "GetHeader ''"                  1 2 DR.GetHeader ""
dcase "QueryField miss"               1 1 DR.QueryField q
dcase "QueryField ''"                 1 2 DR.QueryField ""
dcase "RouteParam miss"               1 1 DR.RouteParam p
dcase "RouteParam ''"                 1 2 DR.RouteParam ""
dcase "SetRouteParam ''"              1 2 DR.SetRouteParam "" v
dcase "HeaderNames bad name"          1 2 DR.HeaderNames 1bad
dcase "ReadFrom malformed call"       1 2 DR.ReadFrom x 1 1
THttpRequest.new DR2
dcase "ReadFrom malformed CONSUMED (F5)" 1 2 DR2.ReadFrom 0 1 1 "" "" 2
DR2.delete
dcase "SetCustomHeader non-token"     1 2 DS.SetCustomHeader "a b" v
dcase "SetCustomHeader server-owned"  1 2 DS.SetCustomHeader Date v
dcase "SetCustomHeader CR in value"   1 2 DS.SetCustomHeader X-A $'a\rb'
dcase "GetCustomHeader miss"          1 1 DS.GetCustomHeader x
dcase "GetCustomHeader ''"            1 2 DS.GetCustomHeader ""
dcase "Attach malformed"              1 2 DS.Attach abc 0
dcase "SendRedirect bad code"         1 2 DS.SendRedirect /p 200
dcase "SendContent before Attach"     1 1 DS.SendContent
dcase "AddRequestFile ''"             1 2 DT.AddRequestFile ""
dcase "AddRequestFile missing"        1 1 DT.AddRequestFile "$TMP/none.req"
dcase "Accept with nothing left"      1 2 DT.Accept 0 10
dcase "ResponseFile out of range"     1 1 DT.ResponseFile 0
dcase "HasHeader false: an answer, not a miss — silent"   0 1 DR.HasHeader x-none
dcase "GetHeader hit — silent"                            0 0 DR.GetHeader x-a
dcase "SetCustomHeader ok — silent"                       0 0 DS.SetCustomHeader X-Ok 1
dcase "Write — silent"                                    0 0 DS.Write text
dcase "CloseConnection with nothing open — silent"        0 0 DT.CloseConnection
dcase "LineConsumed (read) — silent (F5)"                 0 0 DT.LineConsumed

THttpRouter.new DX
dfn() { :; }
dfail() { return 4; }
DX.RegisterRoute /d GET dfn 1
DX.RegisterRoute /f GET dfail
dcase "RegisterRoute bad argument count"   1 2 DX.RegisterRoute /x
dcase "RegisterRoute bad METHOD"           1 2 DX.RegisterRoute /x get dfn
dcase "RegisterRoute bad ISDEFAULT"        1 2 DX.RegisterRoute /x GET dfn yes
dcase "RegisterRoute bad handler name"     1 2 DX.RegisterRoute /x GET 'a b'
dcase "RegisterRoute unknown handler"      1 2 DX.RegisterRoute /x GET no_such_fn008
dcase "RegisterRoute abstract route class" 1 2 DX.RegisterRoute /x GET THttpRouteObject
dcase "RegisterRoute property wrapper"     1 2 DX.RegisterRoute /x GET DX.BeforeRequest
dcase "RegisterRoute '*' not last"         1 2 DX.RegisterRoute '/*a/b' GET dfn
dcase "RegisterRoute second default"       1 1 DX.RegisterRoute /y GET dfn 1
dcase "FindRoute miss"                     1 1 DX.FindRoute /none POST
dcase "FindRoute malformed"                1 2 DX.FindRoute /x
dcase "RouteRequest malformed"             1 2 DX.RouteRequest Nope Nope
dcase "RegisterRoute ok — silent"          0 0 DX.RegisterRoute /ok GET dfn
dcase "FindRoute hit — silent"             0 0 DX.FindRoute /ok GET
dcase "RouteCount — silent"                0 0 DX.RouteCount
dcase "RouteRequest to the default route — silent"      0 0 DX.RouteRequest DR DS
THttpRouter.new DY
dcase "RouteRequest 404 — an answer, silent"            0 0 DY.RouteRequest DR DS
DX.delete; DY.delete
DR.delete; DS.delete; DT.delete

THttpServer.new DV; TNetcatTransport.new DN; THttpRouter.new DZ
DN.NcBinary = /no/such/nc
dcase "ServeOne without a transport"             1 2 DV.ServeOne
dcase "SetActive with a value that is no boolean" 1 2 DV.SetActive maybe
DV.Transport = DZ
dcase "BeginServe with a non-transport"          1 2 DV.BeginServe
DV.Transport = ""
DV.MaxRequests = -1
dcase "BeginServe with a negative MaxRequests"   1 2 DV.BeginServe
DV.MaxRequests = 0
dcase "BuildArgv bad OUTARR"                     1 2 DN.BuildArgv 1bad
dcase "BuildArgv: nc not found"                  1 1 DN.BuildArgv NA
dcase "Accept malformed"                         1 2 DN.Accept x 1
dcase "Accept: nc not found"                     1 2 DN.Accept 0 10
dcase "EndServe when not active — silent"        0 0 DV.EndServe
dcase "Terminate — silent"                       0 0 DV.Terminate
dcase "Active (read) — silent"                   0 0 DV.Active
dcase "RequestCount — silent"                    0 0 DV.RequestCount
dcase "SetActive false when idle — silent"       0 0 DV.SetActive false
dcase "Shutdown with nothing open — silent"      0 0 DN.Shutdown
dcase "CloseConnection with nothing open — silent" 0 0 DN.CloseConnection
DV.delete; DN.delete; DZ.delete

THttpApplication.new DA --port=abc
dcase "Application: Run before Initialize"        1 2 DA.Run
dcase "Application: DoRun before Initialize"      1 2 DA.DoRun
dcase "Application: Initialize with a bad port"   1 2 DA.Initialize
DA.SetArgs --port=9101
DA.ServerClass = THttpRouter
dcase "Application: Initialize with a non-server ServerClass" 1 2 DA.Initialize
DA.ServerClass = THttpServer
dcase "Application: RegisterRoute malformed (the router's line)" 1 2 DA.RegisterRoute /x GET 'a b'
dcase "Application: Initialize — silent"          0 0 DA.Initialize
dcase "Application: RegisterRoute — silent"       0 0 DA.RegisterRoute /ok GET dfn
dcase "Application: Port / Server read — silent"  0 0 DA.Port
dcase "Application: Terminate — silent"           0 0 DA.Terminate
DA.delete

# ===========================================================================
kt_test_section "3. THttpServer.ServeOne over TReplayTransport is fork-free (PLAN §2.1, §4)"
# ===========================================================================

printf 'POST /ff?q=%%41b HTTP/1.1\r\nHost: h\r\nX-A: 1\r\nContent-Length: 3\r\n\r\nxyz' > "$TMP/ff.req"
ffh() { local m q c; $1.Method; m="$RESULT"; $1.QueryField q; q="$RESULT"; $1.Content; c="$RESULT"; $2.Write "$m:$q:$c"; $2.SetCustomHeader X-Out yes; }
FFLOG=""
fflog() { FFLOG="$2"; }
THttpRouter.new FR
FR.RegisterRoute /ff POST ffh
THttpServer.new FS
FS.Router = FR
FS.OnLog = fflog
# ff_serve — one ServeOne over a fresh replay transport; FF_FILE = the capture.
ff_serve() {
    TReplayTransport.new FT
    FT.AddRequestFile "$TMP/ff.req"
    FS.Transport = FT
    FS.ServeOne || return 11
    [[ "$RESULT" == 200 ]] || return 12
    FT.ResponseFile 0; FF_FILE="$RESULT"
    FT.delete
    return 0
}
ff_ok() { local b=""; [[ -f "$FF_FILE" ]] && b="$(<"$FF_FILE")"; [[ "$b" == *$'\r\nX-Out: yes\r\n'*$'\r\n\r\n'"POST:Ab:xyz" && "$FFLOG" =~ ^-\ POST\ /ff\?q=%41b\ 200\ 11\ [0-9]+$ ]]; }

kt_test_start "(a) \$BASHPID is unchanged across ServeOne (accept, objects, parse, route, send, log, close, free)"
p0=$BASHPID; FFLOG=""
prc=0; ff_serve || prc=$?
if [[ $prc -eq 0 && $BASHPID == "$p0" ]] && ff_ok; then kt_test_pass "BASHPID $p0, response and log line correct"; else kt_test_fail "rc=$prc log='$FFLOG' file='$(cat "$FF_FILE" 2>/dev/null | head -c 300)'"; fi

kt_test_start "(b) ServeOne works with PATH='' (no external command on the request path)"
ff_nopath() { local PATH=''; ff_serve; }
FFLOG=""; rm -f "$FF_FILE"
prc=0; ff_nopath 2>"$TMP/ffnp.err" || prc=$?
e="$(<"$TMP/ffnp.err")"
if [[ $prc -eq 0 && -z "$e" ]] && ff_ok; then kt_test_pass "rc 0, silent, full response"; else kt_test_fail "rc=$prc stderr='${e:0:200}' log='$FFLOG'"; fi

kt_test_start "(c) THttpServer's request-path bodies (ServeOne _handleConnection HandleRequest _log Terminate GetActive SetActive) hold no \$( , backtick or pipe"
bad=""; nb=0
for m in ServeOne _handleConnection HandleRequest _log Terminate GetActive SetActive; do
    v="THttpServer_method_body_${m}"
    if [[ -z "${!v+x}" ]]; then bad+=" missing:$m"; continue; fi
    b="${!v}"; nb=$(( nb + 1 ))
    probe="${b//'$(('/}"; probe="${probe//'||'/}"
    [[ "$probe" == *'$('* || "$probe" == *'`'* || "$probe" == *'|'* ]] && bad+=" $m"
done
if [[ -z "$bad" && $nb -eq 7 ]]; then kt_test_pass "$nb bodies clean"; else kt_test_fail "bodies=$nb:$bad"; fi

kt_test_start "(d) a DEBUG-trap canary (set -T) sees NO subshell during ServeOne — and does see one in a control run"
CANARY="$TMP/fork.canary"; rm -f "$CANARY"
set -T
trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
prc=0; ff_serve || prc=$?
trap - DEBUG
set +T
seen=0; [[ -e "$CANARY" ]] && seen=1
rm -f "$CANARY"
set -T; trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
ctl="$(printf x)"
trap - DEBUG; set +T
ctlseen=0; [[ -e "$CANARY" ]] && ctlseen=1
rm -f "$CANARY"
if [[ $prc -eq 0 && $seen -eq 0 && $ctlseen -eq 1 ]]; then kt_test_pass "ServeOne: no subshell; control: detected"; else kt_test_fail "rc=$prc seen=$seen control=$ctlseen"; fi
FS.delete; FR.delete

# ===========================================================================
kt_test_section "4. the network backend: ths._backend identifies the nc, a netcat other than GNU is never run with GNU flags (L2.7-N1)"
# ===========================================================================

# mkfake DIR VERSION_TEXT HELP_TEXT — DIR/nc, a script that appends "$*" as one
# line to DIR/log, answers --version / -h with the given first line (empty: no
# output) and exits 1; builtins only (the cases run it with PATH=DIR).
mkfake() {
    local d="$1"
    rm -rf "$d"; mkdir -p "$d"
    printf '%s\n' "$2" > "$d/v"; printf '%s\n' "$3" > "$d/h"
    cat > "$d/nc" <<EOS
#!$BASH
printf '%s\n' "\$*" >> "$d/log"
show() { local l=""; IFS= read -r l < "\$1" || :; if [[ -n "\$l" ]]; then printf '%s\n' "\$l"; fi; }
case "\${1-}" in
    --version) show "$d/v" ;;
    -h) show "$d/h" ;;
esac
exit 1
EOS
    chmod +x "$d/nc"
}

# detect DIR [NCBIN] — a fresh ths._backend with PATH=DIR and KCL_NC unset
# (both restored before the caller reports).
detect() {
    local d="$1" op="$PATH" hadk=0 kc=""
    if [[ -v KCL_NC ]]; then hadk=1; kc="$KCL_NC"; unset -v KCL_NC; fi
    PATH="$d"
    __THS_BACKEND_KEY=""
    ths._backend ${2:+"$2"}
    PATH="$op"
    if (( hadk )); then KCL_NC="$kc"; fi
}
nolog() {   # no line of DIR/log is an -l argument (token regex)
    local l
    while IFS= read -r l; do
        if [[ "$l" =~ (^|\ )-l(\ |$) ]]; then return 1; fi
    done < "$1/log"
    return 0
}
# why_for FLAVOUR NC — the WHY of an automatic detection that found a non-GNU
# nc and no socat (L2.7-N2 template; detect's PATH holds no socat).
why_for() { printf 'no usable network backend: %s at %s is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); no socat on PATH — install socat (apt/dnf/apk/pkg install socat) or GNU netcat 0.7.1 (Homebrew netcat, FreeBSD pkg install gnetcat, Arch gnu-netcat, or from source)' "$1" "$2"; }

# why_explicit FLAVOUR NC — the WHY of an explicit (NcBinary / KCL_NC / BuildArgv's
# resolved) non-GNU nc: socat is not consulted.
why_explicit() { printf 'no usable network backend: %s at %s is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); socat was not consulted because the netcat was set explicitly (NcBinary/KCL_NC)' "$1" "$2"; }

BK="$TMP/backend"; rm -rf "$BK"; mkdir -p "$BK"

kt_test_start "ths._backend: a nc whose --version says GNU Netcat is gnu (one probe, WHY empty)"
mkfake "$BK/gnu" "netcat (The GNU Netcat) 0.7.1" ""
detect "$BK/gnu"
if [[ "$__THS_BACKEND" == gnu && "$__THS_BACKEND_BIN" == "$BK/gnu/nc" && -z "$__THS_BACKEND_WHY" && "$(<"$BK/gnu/log")" == "--version" ]]; then
    kt_test_pass "gnu at $__THS_BACKEND_BIN"
else
    kt_test_fail "backend='$__THS_BACKEND' bin='$__THS_BACKEND_BIN' why='$__THS_BACKEND_WHY' log='$(<"$BK/gnu/log")'"
fi

# name, --version, -h, flavour in WHY, expected probe log
bkcase() {
    local n="$1" v="$2" h="$3" fl="$4" want="$5" got=""
    kt_test_start "ths._backend: $fl is refused as none — named in WHY, probes only ($want), never -l"
    mkfake "$BK/$n" "$v" "$h"
    detect "$BK/$n"
    got="$(<"$BK/$n/log")"
    if [[ "$__THS_BACKEND" == none && "$__THS_BACKEND_BIN" == "$BK/$n/nc" && "$__THS_BACKEND_WHY" == "$(why_for "$fl" "$BK/$n/nc")" \
          && "$got" == "$want" ]] && nolog "$BK/$n"; then
        kt_test_pass "none: $fl"
    else
        kt_test_fail "backend='$__THS_BACKEND' bin='$__THS_BACKEND_BIN' why='${__THS_BACKEND_WHY:0:140}' log='$got'"
    fi
}
bkcase openbsd "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)" "OpenBSD netcat" $'--version\n-h'
bkcase ncat "Ncat: Version 7.94 ( https://nmap.org/ncat )" "" "Ncat" "--version"
bkcase busybox "BusyBox v1.36.1 (Ubuntu 1:1.36.1-6ubuntu3) multi-call binary." "" "BusyBox nc" "--version"
bkcase trad "nc: invalid option -- '-'" "[v1.10-47]" "traditional nc (v1.10)" $'--version\n-h'
bkcase usage "nc: invalid option -- '-'" "usage: nc [-46cDdFhklNnrStUuvz] [-C certfile] [-e name] [-H hash]" "OpenBSD netcat" $'--version\n-h'
bkcase unknown "gibberish" "more gibberish" "unknown nc" $'--version\n-h'

kt_test_start "ths._backend: an empty PATH dir and KCL_NC unset is missing — no fork, WHY 'nc not found …', BIN empty"
mkdir -p "$BK/empty"
detect "$BK/empty"
if [[ "$__THS_BACKEND" == missing && -z "$__THS_BACKEND_BIN" && "$__THS_BACKEND_WHY" == "nc not found ("* ]]; then
    kt_test_pass "missing: $__THS_BACKEND_WHY"
else
    kt_test_fail "backend='$__THS_BACKEND' bin='$__THS_BACKEND_BIN' why='$__THS_BACKEND_WHY'"
fi

kt_test_start "ths._backend: the result is cached per \$PATH|\$KCL_NC|\$KCL_SOCAT|\$1|\$2 — two calls, ONE --version probe; a changed PATH probes again"
mkfake "$BK/cache" "netcat (The GNU Netcat) 0.7.1" ""
detect "$BK/cache"
op="$PATH"; PATH="$BK/cache"
ths._backend
r2="$__THS_BACKEND"
PATH="$op"
n1="$(<"$BK/cache/log")"
mkfake "$BK/cache2" "netcat (The GNU Netcat) 0.7.1" ""
detect "$BK/cache2"
if [[ "$r2" == gnu && "$n1" == "--version" && "$(<"$BK/cache2/log")" == "--version" ]]; then
    kt_test_pass "one probe per key"
else
    kt_test_fail "r2='$r2' log1='$n1' log2='$(<"$BK/cache2/log")'"
fi

kt_test_start "TNetcatTransport.BuildArgv with an nc that is not GNU netcat: rc 2, LastError = the explicit-netcat WHY (socat not consulted), the out array empty, no -l ever run"
mkfake "$BK/bargv" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
TNetcatTransport.new BN
BN.NcBinary = "$BK/bargv/nc"
__THS_BACKEND_KEY=""
declare -a BA=()
brc=0; BN.BuildArgv BA || brc=$?
BN.LastError; ble="$RESULT"
if [[ $brc -eq 2 && "$ble" == "$(why_explicit "OpenBSD netcat" "$BK/bargv/nc")" && "${#BA[@]}" -eq 0 ]] && nolog "$BK/bargv"; then
    kt_test_pass "rc 2, argv empty"
else
    kt_test_fail "rc=$brc le='${ble:0:120}' n=${#BA[@]} log='$(<"$BK/bargv/log")'"
fi
BN.delete

kt_test_start "THttpServer.BeginServe (no Transport) with an OpenBSD nc on PATH: rc 2, LastError = WHY, nothing started, INT/TERM traps unchanged"
mkfake "$BK/bserve" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
THttpServer.new BS
t_int0="$(trap -p INT)"; t_term0="$(trap -p TERM)"
op="$PATH"; okc=0; if [[ -v KCL_NC ]]; then okc=1; okv="$KCL_NC"; unset -v KCL_NC; fi
PATH="$BK/bserve"; __THS_BACKEND_KEY=""
bsrc=0; BS.BeginServe || bsrc=$?
PATH="$op"; if (( okc )); then KCL_NC="$okv"; fi
BS.LastError; bsle="$RESULT"; BS.Active; bsact="$RESULT"; bstr="${BS_tr_class:-}"
t_int1="$(trap -p INT)"; t_term1="$(trap -p TERM)"
if [[ $bsrc -eq 2 && "$bsle" == "$(why_for "OpenBSD netcat" "$BK/bserve/nc")" && "$bsact" == 0 && -z "$bstr" \
      && "$t_int0" == "$t_int1" && "$t_term0" == "$t_term1" ]] && nolog "$BK/bserve"; then
    kt_test_pass "rc 2, no trap, no transport, no -l"
else
    kt_test_fail "rc=$bsrc le='${bsle:0:100}' active='$bsact' BS_tr_class='$bstr' int='$t_int0'/'$t_int1' term='$t_term0'/'$t_term1'"
fi
BS.delete

# ===========================================================================
kt_test_section "5. the socat backend: the detection precedence, TSocatTransport, the server factory (L2.7-N2)"
# ===========================================================================

# The WHY templates of ths._backend, literally: why_for (auto, a non-GNU nc,
# no socat) and why_explicit are above; these are the other two.
why_nosocat() { printf 'no usable network backend: %s does not support accept-timeout (socat >= 1.7.4 needed)' "$1"; }
WHY_MISSING='nc not found (NcBinary, KCL_NC, PATH); no socat on PATH either'

# mksocat DIR OK — a fake socat in DIR: every call logged to DIR/slog; `-hhh`
# lists accept-timeout only when OK is 1 (the probe); anything else exits 0.
mksocat() {
    local d="$1"
    mkdir -p "$d"
    rm -f "$d/slog"
    cat > "$d/socat" <<EOS
#!$BASH
printf '%s\n' "\$*" >> "$d/slog"
if [[ "\${1-}" == -hhh ]]; then
    printf '%s\n' "      connect-timeout=<seconds>"
    if [[ "$2" == 1 ]]; then printf '%s\n' "      accept-timeout=<seconds>"; fi
fi
exit 0
EOS
    chmod +x "$d/socat"
}
slog() { if [[ -f "$1/slog" ]]; then SLOG="$(<"$1/slog")"; else SLOG="<none>"; fi; }

# sdetect PATH KCL_NC KCL_SOCAT [NCBIN] [SOCATBIN] — a fresh ths._backend with
# that PATH and the two variables ('-' = unset), all restored afterwards; the
# result copied at once into SB / SBIN / SWHY.
sdetect() {
    local op="$PATH" hk=0 kv="" hs=0 sv=""
    if [[ -v KCL_NC ]]; then hk=1; kv="$KCL_NC"; fi
    if [[ -v KCL_SOCAT ]]; then hs=1; sv="$KCL_SOCAT"; fi
    unset -v KCL_NC KCL_SOCAT
    if [[ "$2" != - ]]; then KCL_NC="$2"; fi
    if [[ "$3" != - ]]; then KCL_SOCAT="$3"; fi
    PATH="$1"
    __THS_BACKEND_KEY=""
    ths._backend "${4-}" "${5-}"
    SB="$__THS_BACKEND"; SBIN="$__THS_BACKEND_BIN"; SWHY="$__THS_BACKEND_WHY"
    PATH="$op"
    unset -v KCL_NC KCL_SOCAT
    if (( hk )); then KCL_NC="$kv"; fi
    if (( hs )); then KCL_SOCAT="$sv"; fi
}

SK="$TMP/socat"; rm -rf "$SK"; mkdir -p "$SK/empty"
mkfake "$SK/obsd" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
mkfake "$SK/gnu" "netcat (The GNU Netcat) 0.7.1" ""

kt_test_start "ths._backend auto: a non-GNU nc AND a socat on PATH (the Linux default) → socat, BIN = the socat, WHY ''; the nc only probed (never -l), the socat only -hhh"
mkfake "$SK/a1" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
mksocat "$SK/a1" 1
sdetect "$SK/a1" - -
slog "$SK/a1"
if [[ "$SB" == socat && "$SBIN" == "$SK/a1/socat" && -z "$SWHY" && "$SLOG" == "-hhh" ]] && nolog "$SK/a1"; then
    kt_test_pass "socat at $SBIN"
else
    kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:120}' slog='$SLOG'"
fi

kt_test_start "ths._backend auto: only a socat on PATH (no nc) → socat"
mksocat "$SK/a2" 1
sdetect "$SK/a2" - -
if [[ "$SB" == socat && "$SBIN" == "$SK/a2/socat" && -z "$SWHY" ]]; then kt_test_pass "socat"; else kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:120}'"; fi

kt_test_start "ths._backend auto: a GNU nc AND a socat on PATH → gnu, the socat never run"
mkfake "$SK/a3" "netcat (The GNU Netcat) 0.7.1" ""
mksocat "$SK/a3" 1
sdetect "$SK/a3" - -
slog "$SK/a3"
if [[ "$SB" == gnu && "$SBIN" == "$SK/a3/nc" && -z "$SWHY" && "$SLOG" == "<none>" ]]; then kt_test_pass "gnu"; else kt_test_fail "backend='$SB' bin='$SBIN' slog='$SLOG'"; fi

kt_test_start "ths._backend auto: a socat on PATH that fails the probe (older than 1.7.4) and no nc → none (not missing), BIN = the socat, WHY 'nc not found (NcBinary, KCL_NC, PATH); <socat> does not support accept-timeout (socat >= 1.7.4 needed)'"
mksocat "$SK/a4" 0
sdetect "$SK/a4" - -
if [[ "$SB" == none && "$SBIN" == "$SK/a4/socat" && "$SWHY" == "nc not found (NcBinary, KCL_NC, PATH); $SK/a4/socat does not support accept-timeout (socat >= 1.7.4 needed)" ]]; then kt_test_pass "none: $SWHY"; else kt_test_fail "backend='$SB' bin='$SBIN' why='$SWHY'"; fi

kt_test_start "ths._backend auto: a non-GNU nc AND a socat that fails the probe → none, BIN = the nc, WHY = the nc part + '; <socat> does not support accept-timeout (socat >= 1.7.4 needed)'"
mkfake "$SK/a5" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
mksocat "$SK/a5" 0
sdetect "$SK/a5" - -
want="no usable network backend: OpenBSD netcat at $SK/a5/nc is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); $SK/a5/socat does not support accept-timeout (socat >= 1.7.4 needed)"
if [[ "$SB" == none && "$SBIN" == "$SK/a5/nc" && "$SWHY" == "$want" ]] && nolog "$SK/a5"; then kt_test_pass "none"; else kt_test_fail "backend='$SB' bin='$SBIN' why='$SWHY'"; fi

kt_test_start "ths._backend: no nc and no socat → missing, BIN '', WHY exactly '$WHY_MISSING' (the 'nc not found (' prefix kept)"
sdetect "$SK/empty" - -
if [[ "$SB" == missing && -z "$SBIN" && "$SWHY" == "$WHY_MISSING" ]]; then kt_test_pass "$SWHY"; else kt_test_fail "backend='$SB' bin='$SBIN' why='$SWHY'"; fi

# mkgn DIR VERSION_TEXT HELP_TEXT — the same fake netcat, installed under the
# name gnetcat (FreeBSD net/gnetcat: no `nc` at all).
mkgn() { mkfake "$1" "$2" "$3"; mv "$1/nc" "$1/gnetcat"; }

kt_test_start "ths._backend auto: a non-GNU nc AND a GNU gnetcat on PATH (FreeBSD with the system nc) → gnu via gnetcat, WHY ''; the nc only probed (never -l)"
mkfake "$SK/g1o" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
mkgn "$SK/g1g" "netcat (The GNU Netcat) 0.7.1" ""
sdetect "$SK/g1o:$SK/g1g" - -
if [[ "$SB" == gnu && "$SBIN" == "$SK/g1g/gnetcat" && -z "$SWHY" && "$(<"$SK/g1g/log")" == "--version" ]] && nolog "$SK/g1o"; then kt_test_pass "gnu at $SBIN"; else kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:120}'"; fi

kt_test_start "ths._backend auto: no nc, only a GNU gnetcat on PATH → gnu via gnetcat"
mkgn "$SK/g2" "netcat (The GNU Netcat) 0.7.1" ""
sdetect "$SK/g2" - -
if [[ "$SB" == gnu && "$SBIN" == "$SK/g2/gnetcat" && -z "$SWHY" ]]; then kt_test_pass "gnu at $SBIN"; else kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:120}'"; fi

kt_test_start "ths._backend auto: a GNU gnetcat comes before socat — gnetcat AND a socat on PATH → gnu, the socat never run"
mkgn "$SK/g3" "netcat (The GNU Netcat) 0.7.1" ""
mksocat "$SK/g3" 1
sdetect "$SK/g3" - -
slog "$SK/g3"
if [[ "$SB" == gnu && "$SBIN" == "$SK/g3/gnetcat" && "$SLOG" == "<none>" ]]; then kt_test_pass "gnu"; else kt_test_fail "backend='$SB' bin='$SBIN' slog='$SLOG'"; fi

kt_test_start "ths._backend auto: a non-GNU gnetcat is not used — a non-GNU nc and a non-GNU gnetcat, no socat → none, BIN = the nc, WHY names the NC's flavour (the gnetcat probe leaves it alone), no -l"
mkfake "$SK/g4o" "nc: unknown option -- -" "OpenBSD netcat (Debian patchlevel 1.226-1ubuntu2)"
mkgn "$SK/g4g" "Ncat: Version 7.94 ( https://nmap.org/ncat )" ""
sdetect "$SK/g4o:$SK/g4g" - -
if [[ "$SB" == none && "$SBIN" == "$SK/g4o/nc" && "$SWHY" == "$(why_for "OpenBSD netcat" "$SK/g4o/nc")" ]] && nolog "$SK/g4o" && nolog "$SK/g4g"; then kt_test_pass "none"; else kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:160}'"; fi

kt_test_start "ths._backend auto: only a non-GNU gnetcat (no nc, no socat) → missing, never run with -l"
mkgn "$SK/g5" "Ncat: Version 7.94 ( https://nmap.org/ncat )" ""
sdetect "$SK/g5" - -
if [[ "$SB" == missing && -z "$SBIN" && "$SWHY" == "$WHY_MISSING" ]] && nolog "$SK/g5"; then kt_test_pass "missing"; else kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:120}'"; fi

kt_test_start "ths._backend b: an explicit KCL_SOCAT passing the probe wins over a GNU nc on PATH → socat (the GNU nc never probed)"
mkfake "$SK/b1p" "netcat (The GNU Netcat) 0.7.1" ""
mksocat "$SK/b1" 1
sdetect "$SK/b1p" - "$SK/b1/socat"
slog "$SK/b1"
if [[ "$SB" == socat && "$SBIN" == "$SK/b1/socat" && -z "$SWHY" && "$SLOG" == "-hhh" && ! -s "$SK/b1p/log" ]]; then kt_test_pass "socat"; else kt_test_fail "backend='$SB' bin='$SBIN' slog='$SLOG' nclog='$(cat "$SK/b1p/log" 2>/dev/null)'"; fi

kt_test_start "ths._backend b: an explicit KCL_SOCAT failing the probe → none, WHY exactly the 'does not support accept-timeout' template"
mksocat "$SK/b2" 0
sdetect "$SK/a2" - "$SK/b2/socat"
if [[ "$SB" == none && "$SBIN" == "$SK/b2/socat" && "$SWHY" == "$(why_nosocat "$SK/b2/socat")" ]]; then kt_test_pass "none: ${SWHY:0:90}"; else kt_test_fail "backend='$SB' bin='$SBIN' why='$SWHY'"; fi

kt_test_start "ths._backend b: SOCATBIN (\$2, a caller's SocatBinary) passing → socat; failing → none (the template)"
sdetect "$SK/empty" - - "" "$SK/b1/socat"
r1="$SB:$SBIN"
sdetect "$SK/empty" - - "" "$SK/b2/socat"
if [[ "$r1" == "socat:$SK/b1/socat" && "$SB" == none && "$SWHY" == "$(why_nosocat "$SK/b2/socat")" ]]; then kt_test_pass "socat / none"; else kt_test_fail "r1='$r1' backend='$SB' why='$SWHY'"; fi

kt_test_start "ths._backend a: a GNU KCL_NC and a KCL_SOCAT → gnu (a before b), the socat never run"
mksocat "$SK/p1" 1
sdetect "$SK/empty" "$SK/gnu/nc" "$SK/p1/socat"
slog "$SK/p1"
if [[ "$SB" == gnu && "$SBIN" == "$SK/gnu/nc" && "$SLOG" == "<none>" ]]; then kt_test_pass "gnu"; else kt_test_fail "backend='$SB' bin='$SBIN' slog='$SLOG'"; fi

kt_test_start "ths._backend a: an explicit non-GNU nc (KCL_NC) and a socat on PATH → none, WHY exactly the 'socat was not consulted' template, the socat never run"
mksocat "$SK/p2" 1
sdetect "$SK/p2" "$SK/obsd/nc" -
slog "$SK/p2"
if [[ "$SB" == none && "$SBIN" == "$SK/obsd/nc" && "$SWHY" == "$(why_explicit "OpenBSD netcat" "$SK/obsd/nc")" && "$SLOG" == "<none>" ]]; then kt_test_pass "none, not consulted"; else kt_test_fail "backend='$SB' bin='$SBIN' why='${SWHY:0:160}' slog='$SLOG'"; fi

kt_test_start "ths._backend a: an explicit KCL_NC that does not exist → missing 'nc not found (NcBinary, KCL_NC, PATH)' even with a socat on PATH (009 relies on it)"
sdetect "$SK/p2" /no/such/nc -
if [[ "$SB" == missing && -z "$SBIN" && "$SWHY" == "nc not found (NcBinary, KCL_NC, PATH)" ]]; then kt_test_pass "missing"; else kt_test_fail "backend='$SB' bin='$SBIN' why='$SWHY'"; fi

kt_test_start "ths._backend: the cache key is \$PATH|\$KCL_NC|\$KCL_SOCAT|\$1|\$2 — a repeated call probes nothing, a changed KCL_SOCAT probes again"
mksocat "$SK/c1" 1
mksocat "$SK/c2" 1
sdetect "$SK/empty" - "$SK/c1/socat"
op="$PATH"; okc=0; if [[ -v KCL_NC ]]; then okc=1; okv="$KCL_NC"; unset -v KCL_NC; fi
PATH="$SK/empty"; KCL_SOCAT="$SK/c1/socat"
ths._backend; k1="$__THS_BACKEND"
KCL_SOCAT="$SK/c2/socat"
ths._backend; k2="$__THS_BACKEND:$__THS_BACKEND_BIN"
unset -v KCL_SOCAT; PATH="$op"; if (( okc )); then KCL_NC="$okv"; fi
slog "$SK/c1"; s1="$SLOG"; slog "$SK/c2"
if [[ "$k1" == socat && "$k2" == "socat:$SK/c2/socat" && "$s1" == "-hhh" && "$SLOG" == "-hhh" ]]; then kt_test_pass "one probe per key"; else kt_test_fail "k1='$k1' k2='$k2' slog1='$s1' slog2='$SLOG'"; fi

kt_test_start "TSocatTransport.BuildArgv: SOCAT -d -d -lpsocat -t 0.5 TCP4-LISTEN:PORT,bind=ADDR,reuseaddr,accept-timeout=TTL STDIO (RESULT 8); an Address with ':' → TCP6-LISTEN:PORT,bind=[ADDR]"
TSocatTransport.new SX
SX.SocatBinary = "$SK/a2/socat"
SX.Port = 8081
SX.ListenerTTL = 30
declare -a SA=() SA6=()
r=0; SX.BuildArgv SA || r=$?; n4="$RESULT"
SX.Address = ::1
SX.BuildArgv SA6; n6="$RESULT"
if [[ $r -eq 0 && "$n4" == 8 && "${SA[0]}" == "$SK/a2/socat" && "${SA[*]:1}" == "-d -d -lpsocat -t 0.5 TCP4-LISTEN:8081,bind=127.0.0.1,reuseaddr,accept-timeout=30 STDIO" \
      && "$n6" == 8 && "${SA6[*]:1}" == "-d -d -lpsocat -t 0.5 TCP6-LISTEN:8081,bind=[::1],reuseaddr,accept-timeout=30 STDIO" ]]; then
    kt_test_pass "v4 and v6 as specified"
else
    kt_test_fail "rc=$r n=$n4/$n6 v4='${SA[*]}' v6='${SA6[*]}'"
fi
SX.delete

kt_test_start "TSocatTransport.BuildArgv: SocatBinary '' → \$KCL_SOCAT → socat on PATH (a KCL_NC never interferes); none → rc 1 'socat not found …'; a socat failing the probe → rc 2, LastError = that WHY, the out array empty; Port 0 → rc 2"
TSocatTransport.new SY
op="$PATH"
declare -a SB1=() SB2=() SB3=() SB4=()
KCL_NC="$SK/obsd/nc" KCL_SOCAT="$SK/b1/socat" SY.BuildArgv SB1; v1="${SB1[0]:-}"
PATH="$SK/a2"; SY.BuildArgv SB2; v2="${SB2[0]:-}"
PATH="$SK/empty"; r3=0; SY.BuildArgv SB3 || r3=$?; SY.LastError; l3="$RESULT"
PATH="$op"
SY.SocatBinary = "$SK/b2/socat"
r4=0; SY.BuildArgv SB4 || r4=$?; SY.LastError; l4="$RESULT"
SY.SocatBinary = "$SK/a2/socat"
SY.Port = 0
r5=0; SY.BuildArgv SB4 || r5=$?
if [[ "$v1" == "$SK/b1/socat" && "$v2" == "$SK/a2/socat" && $r3 -eq 1 && "$l3" == "socat not found ("* && ${#SB3[@]} -eq 0 \
      && $r4 -eq 2 && "$l4" == "$(why_nosocat "$SK/b2/socat")" && ${#SB4[@]} -eq 0 && $r5 -eq 2 ]]; then
    kt_test_pass "KCL_SOCAT, PATH, rc 1, rc 2 (WHY), rc 2 (Port)"
else
    kt_test_fail "v1='$v1' v2='$v2' r3=$r3 l3='$l3' n3=${#SB3[@]} r4=$r4 l4='${l4:0:100}' n4=${#SB4[@]} r5=$r5"
fi
SY.delete

# TSocatProbe — _state on a recorded stderr file: Probe DIR SLOT points the
# private _dir at DIR for one _state call (and clears it again, so Destroy's
# Shutdown never removes DIR).
class TSocatProbe : TSocatTransport
    public
        func Probe
end
TSocatProbe.Probe() {
    local r
    _dir="$1"
    "$__inst__._state" "$2"
    r="$RESULT"
    _dir=""
    kk._return "$r"
}
build TSocatProbe
TSocatProbe.new SP
SD="$SK/state"; mkdir -p "$SD"
# st NAME LINE… — the recorded lines (socat 1.8 on Ubuntu 24.04, L2.7-N2 step 0)
# as SD/errNAME; ST = the _state RESULT, STR = its REPLY.
st() {
    local n="$1"
    shift
    if (( $# )); then printf '%s\n' "$@" > "$SD/err$n"; else : > "$SD/err$n"; fi
    SP.Probe "$SD" "$n"
    ST="$RESULT"; STR="$REPLY"
}
P='2026/10/22 10:42:13 socat[1209]'

kt_test_start "TSocatTransport._state on recorded lines: 'N listening on' → listening; 'N accepting connection from AF=2 A:P on …' (+ the transfer lines, a later 'W exiting on signal 15') → connected, REPLY 'A:P'; IPv6 → REPLY '[::1]:P' (RFC 5952 short form of socat's eight groups); the FreeBSD form 'LEN=16 AF=2 A:P' / 'LEN=28 AF=28 […]:P' the same"
st 1 "$P N listening on AF=2 127.0.0.1:48772"; s1="$ST|$STR"
st 2 "$P N listening on AF=2 127.0.0.1:48772" "$P N accepting connection from AF=2 127.0.0.1:59560 on AF=2 127.0.0.1:48772" \
     "$P N reading from and writing to stdio" "$P N starting data transfer loop with FDs [6,6] and [0,1]" "$P W exiting on signal 15"; s2="$ST|$STR"
st 3 "$P N listening on AF=10 [0000:0000:0000:0000:0000:0000:0000:0001]:35388" \
     "$P N accepting connection from AF=10 [0000:0000:0000:0000:0000:0000:0000:0001]:36054 on AF=10 [0000:0000:0000:0000:0000:0000:0000:0001]:35388"; s3="$ST|$STR"
P='2026/10/22 11:28:10 socat[1419]'   # socat 1.8.1.3 on FreeBSD 15.1
st 31 "$P N listening on LEN=16 AF=2 127.0.0.1:48487" "$P N accepting connection from LEN=16 AF=2 127.0.0.1:33420 on LEN=16 AF=2 127.0.0.1:48487"; s3b="$ST|$STR"
st 32 "$P N accepting connection from LEN=28 AF=28 [0000:0000:0000:0000:0000:0000:0000:0001]:51308 on LEN=28 AF=28 [0000:0000:0000:0000:0000:0000:0000:0001]:43102"; s3c="$ST|$STR"
P='2026/10/22 10:42:13 socat[1209]'
if [[ "$s1" == "listening|" && "$s2" == "connected|127.0.0.1:59560" && "$s3" == "connected|[::1]:36054"       && "$s3b" == "connected|127.0.0.1:33420" && "$s3c" == "connected|[::1]:51308" ]]; then
    kt_test_pass "$s1 $s2 $s3 $s3b $s3c"
else
    kt_test_fail "'$s1' '$s2' '$s3' '$s3b' '$s3c'"
fi

kt_test_start "TSocatTransport._state: 'W accept: Connection timed out' (FreeBSD: 'Operation timed out') → ttl; an E line → failed:<the text after the severity letter>; an E line AFTER the timeout → still ttl; an accepted connection beats an E line"
st 4 "$P N listening on AF=2 127.0.0.1:33847" "$P W accept: Connection timed out" "$P N Waiting for child processes to terminate"; s4="$ST"
st 41 "$P N listening on LEN=16 AF=2 127.0.0.1:33593" "$P W accept: Operation timed out" "$P N Waiting for child processes to terminate"; s4b="$ST"
st 5 "$P E bind(5, {AF=2 127.0.0.1:32681}, 16): Address already in use" "$P N exit(1)"; s5="$ST"
st 6 "$P N listening on AF=2 127.0.0.1:33847" "$P W accept: Connection timed out" "$P E some later error"; s6="$ST"
st 7 "$P N listening on AF=2 127.0.0.1:33847" "$P N accepting connection from AF=2 127.0.0.1:5 on AF=2 127.0.0.1:33847" "$P E write(6, 0x1, 5): Broken pipe"; s7="$ST|$STR"
st 8 "$P F something fatal"; s8="$ST"
if [[ "$s4" == ttl && "$s4b" == ttl && "$s5" == "failed:bind(5, {AF=2 127.0.0.1:32681}, 16): Address already in use" && "$s6" == ttl \
      && "$s7" == "connected|127.0.0.1:5" && "$s8" == "failed:something fatal" ]]; then
    kt_test_pass "ttl; failed:bind(…); ttl; connected; failed (F)"
else
    kt_test_fail "'$s4' '$s5' '$s6' '$s7' '$s8'"
fi

kt_test_start "TSocatTransport._state: no file / an empty file → none; lines that are not socat's (no 'socat[PID] S ' prefix) and N/W noise are ignored"
SP.Probe "$SD" 9; s9="$RESULT"
st 10; s10="$ST"
st 11 "bash: /usr/bin/socat: cannot execute" "$P W some warning" "$P N exit(1)"; s11="$ST"
if [[ "$s9" == none && "$s10" == none && "$s11" == none ]]; then kt_test_pass "none none none"; else kt_test_fail "'$s9' '$s10' '$s11'"; fi
SP.delete

# The mechanism over a fake socat (no socket, every host): TSocatTransport's
# BuildArgv and _state are called from the BASE's Accept / CloseConnection /
# Shutdown — the public overrides print no kklass visibility warning.
mkdir -p "$SK/m"
cat > "$SK/m/socat" <<EOS
#!$BASH
case "\${1-}" in -hhh) printf '%s\n' "      accept-timeout=<seconds>"; exit 0 ;; esac
nm="\${0##*/}"
for a in "\$@"; do case "\$a" in -lp*) nm="\${a#-lp}" ;; esac; done
P="2026/10/22 10:42:13 \$nm[\$\$]"
n=\$(( \$(cat "$SK/m/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "\$n" > "$SK/m/count"
printf '%s %s\n' "\${FAKE_MODE-}" "\$*" >> "$SK/m/spawns"
case "\${FAKE_MODE-}:\$n" in
    bind:*)
        printf '%s\n' "\$P E bind(5, {AF=2 127.0.0.1:9}, 16): Address already in use" "\$P N exit(1)" >&2
        exit 1 ;;
    conn:1)
        printf '%s\n' "\$P N listening on AF=10 [0000:0000:0000:0000:0000:0000:0000:0001]:9" >&2
        printf '%s\n' "\$P N accepting connection from AF=10 [0000:0000:0000:0000:0000:0000:0000:0001]:4242 on AF=10 [0000:0000:0000:0000:0000:0000:0000:0001]:9" >&2
        printf 'GET /x HTTP/1.0\r\n\r\n'
        cat > "$SK/m/got"
        exit 0 ;;
    *)
        printf '%s\n' "\$P N listening on AF=2 127.0.0.1:9" >&2
        exec sleep 30 ;;
esac
EOS
chmod +x "$SK/m/socat"
cat > "$SK/m/child.sh" <<'EOS'
exec </dev/null
source "$UNIT" || exit 91
TSocatTransport.new T
T.SocatBinary = "$SKM/socat"
T.Port = 9
r=0; FAKE_MODE=bind T.Accept 0 10 || r=$?
T.LastError; printf 'bind_rc=%s\nbind_le=%s\n' "$r" "$RESULT"
T.Shutdown
rm -f "$SKM/count"
T.Address = ::1
r=0; FAKE_MODE=conn T.Accept 0 10 || r=$?
T.FirstLine; fl="$RESULT"; T.RemoteAddress; ra="$RESULT"
printf 'conn_rc=%s\nconn_fl=%s\nconn_ra=%s\n' "$r" "${fl%$'\r'}" "$ra"
T.OutFd; printf 'HTTP/1.0 200 OK\r\n\r\n' >&"$RESULT"
T.CloseConnection
T.Shutdown
d=""; for x in "$TMPDIR"/thttpserver.*; do [[ -e "$x" ]] && d+=" $x"; done
printf 'dirs=[%s]\n' "$d"
T.delete
EOS
kt_test_start "the base mechanism over a fake socat: a bind failure → Accept rc 2 at once, LastError = the text after E, spawned once; a v6 connection → rc 0, FirstLine, RemoteAddress '[::1]:4242', the response reaches the listener's stdin, the drained close; no kklass visibility warning, nothing left"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
mkdir -p "$SK/m/tmp"
rm -f "$SK/m/count" "$SK/m/spawns" "$SK/m/got"
mrc=0
FAKE_MODE="" UNIT="$UNIT" SKM="$SK/m" TMPDIR="$SK/m/tmp" "$KT_TIMEOUT" 120 "$BASH" "$SK/m/child.sh" >"$SK/m/out" 2>"$SK/m/err" || mrc=$?
declare -A MR=()
while IFS= read -r l; do [[ "$l" == *=* ]] && MR["${l%%=*}"]="${l#*=}"; done < "$SK/m/out"
# bind spawns only: the pre-spawned slot of the conn pass may be stopped by
# Shutdown before its fake even logs
ms="$(grep -c -- '^bind .*-d -d -lpsocat -t 0.5' "$SK/m/spawns" 2>/dev/null)"
mg="$(tr -d '\r' < "$SK/m/got" 2>/dev/null)"
me="$(<"$SK/m/err")"
if [[ $mrc -eq 0 && "${MR[bind_rc]:-}" == 2 && "${MR[bind_le]:-}" == "bind(5, {AF=2 127.0.0.1:9}, 16): Address already in use" \
      && "${MR[conn_rc]:-}" == 0 && "${MR[conn_fl]:-}" == "GET /x HTTP/1.0" && "${MR[conn_ra]:-}" == "[::1]:4242" \
      && "$mg" == "HTTP/1.0 200 OK" && "${MR[dirs]:-x}" == "[]" && "$ms" == 1 && -z "$me" ]]; then
    kt_test_pass "rc 2 '${MR[bind_le]:0:40}…' after 1 spawn; rc 0 from ${MR[conn_ra]}; silent"
else
    kt_test_fail "exit=$mrc out='$(tr '\n' ' ' < "$SK/m/out")' spawns=$ms got='$mg' stderr='${me:0:300}'"
fi
fi   # kt_need_timeout

kt_test_start "TSocatTransport.BuildArgv refuses an Address outside 0-9 A-Z a-z . : - (rc 2, LastError, the array empty): '127.0.0.1,fork', 'a b', 'x;y'; 'localhost' and 'fe80::1' pass"
TSocatTransport.new SZ
SZ.SocatBinary = "$SK/a2/socat"
bad=""
for a in '127.0.0.1,fork' 'a b' 'x;y'; do
    SZ.Address = "$a"
    declare -a SZA=()
    r=0; SZ.BuildArgv SZA || r=$?
    SZ.LastError
    [[ $r -eq 2 && ${#SZA[@]} -eq 0 && "$RESULT" == "TSocatTransport: Address '$a' may only contain 0-9 A-Z a-z . : -" ]] || bad+=" [$a]:rc=$r,n=${#SZA[@]},le='$RESULT'"
done
for a in localhost fe80::1; do
    SZ.Address = "$a"
    declare -a SZA=()
    r=0; SZ.BuildArgv SZA || r=$?
    [[ $r -eq 0 && ${#SZA[@]} -eq 8 ]] || bad+=" [$a]:rc=$r"
done
SZ.delete
if [[ -z "$bad" ]]; then kt_test_pass "three refused, two accepted"; else kt_test_fail "$bad"; fi

kt_test_start "TNetcatTransport.BuildArgv, NcBinary '' and KCL_NC unset, a non-GNU nc found on PATH: rc 2, LastError ends '; TNetcatTransport runs GNU netcat only (use TSocatTransport, or leave THttpServer.Transport '' for automatic selection)' — not the 'set explicitly' tail"
TNetcatTransport.new NP
op="$PATH"; okc=0; if [[ -v KCL_NC ]]; then okc=1; okv="$KCL_NC"; unset -v KCL_NC; fi
PATH="$SK/obsd"; __THS_BACKEND_KEY=""
declare -a NPA=()
r=0; NP.BuildArgv NPA || r=$?
PATH="$op"; if (( okc )); then KCL_NC="$okv"; fi
NP.LastError; le="$RESULT"
NP.delete
want="no usable network backend: OpenBSD netcat at $SK/obsd/nc is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); TNetcatTransport runs GNU netcat only (use TSocatTransport, or leave THttpServer.Transport '' for automatic selection)"
if [[ $r -eq 2 && "$le" == "$want" && ${#NPA[@]} -eq 0 ]]; then kt_test_pass "rc 2, the GNU-only reason"; else kt_test_fail "rc=$r le='$le'"; fi

kt_test_start "ths._v6short (RFC 5952): eight groups → the short form (the longest zero run, the first of equal runs, never a single zero); IPv4-mapped eight groups → '::ffff:7f00:1'; anything else unchanged"
bad=""
while IFS='|' read -r a w; do
    ths._v6short "$a"
    [[ "$REPLY" == "$w" ]] || bad+=" $a→'$REPLY'(want $w)"
done <<'EOV'
0000:0000:0000:0000:0000:0000:0000:0001|::1
0:0:0:0:0:0:0:0|::
2001:0DB8:0000:0000:0001:0000:0000:0001|2001:db8::1:0:0:1
fe80:0:0:1:0:0:0:1|fe80:0:0:1::1
1:0:0:1:0:0:1:1|1::1:0:0:1:1
fe80:0:0:1:0:0:0:0|fe80:0:0:1::
1:2:3:4:5:6:7:8|1:2:3:4:5:6:7:8
1:0:2:3:4:5:6:7|1:0:2:3:4:5:6:7
0:0:0:0:0:ffff:7f00:1|::ffff:7f00:1
::1|::1
::ffff:127.0.0.1|::ffff:127.0.0.1
EOV
if [[ -z "$bad" ]]; then kt_test_pass "11 vectors"; else kt_test_fail "$bad"; fi

kt_test_start "a socat binary under another name (socat1) logs as 'socat[PID]' through -lpsocat: the base mechanism still reads its lines (RemoteAddress '[::1]:4242'), no warning, nothing left"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
cp "$SK/m/socat" "$SK/m/socat1"
cat > "$SK/m/child1.sh" <<'EOS'
exec </dev/null
source "$UNIT" || exit 91
TSocatTransport.new T
T.SocatBinary = "$SKM/socat1"
T.Address = ::1
T.Port = 9
r=0; FAKE_MODE=conn T.Accept 0 10 || r=$?
T.RemoteAddress; printf 'rc=%s\nra=%s\n' "$r" "$RESULT"
T.OutFd; printf 'HTTP/1.0 200 OK\r\n\r\n' >&"$RESULT"
T.CloseConnection
T.Shutdown
d=""; for x in "$TMPDIR"/thttpserver.*; do [[ -e "$x" ]] && d+=" $x"; done
printf 'dirs=[%s]\n' "$d"
T.delete
EOS
rm -f "$SK/m/count" "$SK/m/spawns" "$SK/m/got"
mrc=0
FAKE_MODE="" UNIT="$UNIT" SKM="$SK/m" TMPDIR="$SK/m/tmp" "$KT_TIMEOUT" 120 "$BASH" "$SK/m/child1.sh" >"$SK/m/out1" 2>"$SK/m/err1" || mrc=$?
m1="$(tr '\n' ' ' < "$SK/m/out1")"; me="$(<"$SK/m/err1")"
if [[ $mrc -eq 0 && "$m1" == "rc=0 ra=[::1]:4242 dirs=[] " && -z "$me" ]] && grep -q -- '-lpsocat' "$SK/m/spawns"; then
    kt_test_pass "$m1"
else
    kt_test_fail "exit=$mrc out='$m1' spawns='$(tr '\n' '|' < "$SK/m/spawns" 2>/dev/null)' stderr='${me:0:200}'"
fi
fi   # kt_need_timeout

kt_test_start "the server factory: BeginServe (no Transport) with only a socat on PATH → the OWNED \${inst}_tr is a TSocatTransport (Port/Address copied); EndServe frees it"
THttpServer.new FS
FS.Port = 12346
FS.Address = 127.0.0.3
op="$PATH"; okc=0; if [[ -v KCL_NC ]]; then okc=1; okv="$KCL_NC"; unset -v KCL_NC; fi
PATH="$SK/a1"; __THS_BACKEND_KEY=""
r=0; FS.BeginServe || r=$?
PATH="$op"; if (( okc )); then KCL_NC="$okv"; fi
c1="${FS_tr_class:-}"; p1="$(FS_tr.Port)"; a1="$(FS_tr.Address)"; t1="$(FS.Transport)"
FS.EndServe
t2="$(FS.Transport)"
left=0; declare -p FS_tr_data >/dev/null 2>&1 && left=1
if [[ $r -eq 0 && "$c1" == TSocatTransport && "$t1" == FS_tr && "$p1" == 12346 && "$a1" == 127.0.0.3 && -z "$t2" && $left -eq 0 ]]; then
    kt_test_pass "TSocatTransport, configured, freed"
else
    kt_test_fail "rc=$r class='$c1' tr='$t1' port='$p1' addr='$a1' after='$t2' left=$left"
fi

kt_test_start "the server factory: a GNU KCL_NC (a socat on PATH too) → TNetcatTransport; a caller-set Transport is untouched (not replaced, not owned, not freed)"
op="$PATH"; PATH="$SK/a1"; __THS_BACKEND_KEY=""
r1=0; KCL_NC="$SK/gnu/nc" FS.BeginServe || r1=$?
PATH="$op"
c2="${FS_tr_class:-}"
FS.EndServe
TReplayTransport.new FT
FS.Transport = FT
op="$PATH"; PATH="$SK/a1"; __THS_BACKEND_KEY=""
r2=0; FS.BeginServe || r2=$?
PATH="$op"
t3="$(FS.Transport)"; c3="${FS_tr_class:-}"
FS.EndServe
t4="$(FS.Transport)"
alive=0; declare -F FT.Accept >/dev/null && alive=1
if [[ $r1 -eq 0 && "$c2" == TNetcatTransport && $r2 -eq 0 && "$t3" == FT && -z "$c3" && "$t4" == FT && $alive -eq 1 ]]; then
    kt_test_pass "TNetcatTransport; FT kept"
else
    kt_test_fail "rc=$r1/$r2 class='$c2' tr='$t3' owned-class='$c3' after='$t4' alive=$alive"
fi
FT.delete
FS.delete
