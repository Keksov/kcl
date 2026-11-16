#!/usr/bin/env bash
# 018_Names.sh - reserved names, the constructor guard and a constructor that
# skipped `inherited` (design §1.6, §1.11, risk R11):
#   * a name with `__fv` inside is refused by TView's constructor (rc 2, one
#     Error line on stderr) unless fv.views._newReserved makes it
#     (${OWNER}__fv${ROLE}); the check is case-sensitive, also under
#     nocasematch;
#   * `.new` over a live view: the tree is repaired (the stale name out of
#     its owner's list with a `delete` hook and Current reset, its old
#     subviews destroyed, its entries freed), one Error line, rc 1 (also
#     through TGroup's and a subclass's constructor); the name stays a bare
#     kklass instance that `.delete` frees quietly; the dialog pattern in a
#     loop (new, insert, delete, .delete) runs clean, the anti-pattern (new
#     again without .delete) fails loudly and the tree never grows;
#   * a user constructor that skipped `inherited`: insert refuses the view
#     (and a group of such a class as the target) with one Error line, rc 2;
#   * VERBOSE_KKLASS=quiet silences the Error lines (rc unchanged); nothing
#     goes to stdout; every rc-2 refusal gives one debug line under
#     VERBOSE_KKLASS=debug and none without it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "018: names and the constructor guard"

HOOK=()
fv.views._changed() { HOOK+=("$1 $2 ${3:-.}"); }
E="$FVW_TMP/err.txt"

kt_test_start "reserved names refused: rc 2, one Error line on stderr, nothing on stdout, no live view"
out=''
for n in win__fvframe __fvx a__fv a__fv__fv; do
    o=$(TView.new "$n" 0 0 1 1 2>"$E"); r=$?
    e=$(<"$E")
    if [[ $r == 2 && -z $o && $e == "Error: fv.views: TView.Create: '$n': names with '__fv' are reserved for framework-made views" ]] && ! fv.views.isView "$n"; then out+=ok; else out+="[$n rc=$r o=$o e=$e]"; fi
done
o=$(TGroup.new g__fvx 0 0 1 1 2>"$E"); r=$?
if [[ $r == 2 && $(<"$E") == *"'g__fvx': names with '__fv' are reserved"* ]] && ! fv.views.isView g__fvx; then out+=ok; else out+="[group rc=$r]"; fi
if [[ $out == okokokokok ]]; then kt_test_pass "ok"; else kt_test_fail "$out"; fi

kt_test_start "not reserved (the check is case-sensitive, also under nocasematch): a_fv, a__f, a__FV, a__Fv"
out=''
shopt -s nocasematch
for n in a_fv a__f a__FV a__Fv; do
    if TView.new "$n" 0 0 1 1 2>"$E" && fv.views.isView "$n" && [[ ! -s $E ]]; then out+=ok; else out+="[$n]"; fi
    "$n.delete"
done
shopt -u nocasematch
if [[ $out == okokokok ]]; then kt_test_pass "ok"; else kt_test_fail "$out"; fi

kt_test_start "fv.views._newReserved OWNER ROLE CLASS ARGS: makes \${OWNER}__fv\${ROLE} (RESULT), a live view that inserts like any other"
TGroup.new win 0 0 20 10
fv.views._newReserved win frame TView 0 0 20 10; r=$?
n=$RESULT
fv.views.insert win "$n"; r2=$?
fvw_tree win
if [[ $r == 0 && $n == win__fvframe && $r2 == 0 && $REPLY == 'win[win__fvframe]' ]] && fv.views.isView win__fvframe; then kt_test_pass "ok"; else kt_test_fail "rc=$r/$r2 name=$n tree=$REPLY"; fi

kt_test_start "_newReserved: a bad ROLE or too few arguments rc 2 (RESULT ''); the permission is one-shot (a refused constructor clears it too)"
out=''
for role in '' 'a-b' 'x y' 'é'; do RESULT=x; fv.views._newReserved win "$role" TView 0 0 1 1 2>/dev/null; out+="$?[$RESULT]"; done
RESULT=x; fv.views._newReserved win frame2; out+="$?[$RESULT]"
fv.views._newReserved win bad TView 0 0 1 2>/dev/null; out+=" $?"
TView.new win__fvbad 0 0 1 1 2>/dev/null; out+=" $?"
o=$(TView.new win__fvframe3 0 0 1 1 2>&1); out+=" $?"
if [[ $out == '2[]2[]2[]2[]2[] 2 2 2' && -z ${__FV_VW_RESNAME} ]]; then kt_test_pass "ok"; else kt_test_fail "$out resname=[$__FV_VW_RESNAME]"; fi

# --- the constructor guard -----------------------------------------------------
TGroup.new desk 0 0 80 24
TView.new leaf 1 1 5 5; leaf_data[Options]=$FV_OF_SELECTABLE
TGroup.new box 10 1 30 9
TView.new k1 0 0 1 1; TView.new k2 0 0 1 1
fv.views.insert box k1; fv.views.insert box k2
fv.views.insert desk box; fv.views.insert desk leaf

kt_test_start "re-creating a live leaf: rc 1, one Error line, out of its owner (delete hook, Current reset), entries freed, a bare instance left"
HOOK=()
o=$(TView.new leaf 2 2 3 3 2>"$E"; echo "rc=$?")
# ($( ) ran it in a subshell: run it here for the effect, the line checked above)
TView.new leaf 2 2 3 3 2>"$E"; r=$?
e=$(<"$E")
fvw_tree desk
if [[ $o == 'rc=1' && $r == 1 && $e == "Error: fv.views: TView.Create: 'leaf' is a live view: re-creating it is refused (delete it first: leaf.delete); its old tree was removed" \
   && $REPLY == 'desk[{box[k1 k2]}]*box' && "${HOOK[*]}" == 'delete leaf desk' && -z ${__FV_VW_AX[leaf]-}${__FV_VW_C1[leaf]-} && -z ${leaf_data[Owner]} ]] \
   && ! fv.views.isView leaf && declare -F leaf.delete >/dev/null; then kt_test_pass "ok"
else kt_test_fail "o=$o rc=$r e=[$e] tree=$REPLY hook=[${HOOK[*]}]"; fi

kt_test_start "the bare instance left: insert refuses it loudly (rc 2), .delete frees it quietly, then the name is new"
fv.views.insert desk leaf 2>"$E"; r=$?
e=$(<"$E")
leaf.delete 2>"$E"; r2=$?
TView.new leaf 0 0 1 1; r3=$?
if [[ $r == 2 && $e == "Error: fv.views: insert: 'leaf' is not a live view (re-created over a live name)" && $r2 == 0 && ! -s $E && $r3 == 0 ]] && fv.views.isView leaf; then kt_test_pass "ok"
else kt_test_fail "rc=$r/$r2/$r3 e=[$e]"; fi

kt_test_start "re-creating a live group with subviews: its subtree destroyed (functions, data, lists gone), the owner repaired, rc 1 through TGroup's constructor"
TGroup.new box 0 0 2 2 2>"$E"; r=$?
fvw_tree desk
gone=1
for v in k1 k2; do if declare -F "$v.delete" >/dev/null || fv.views.isView "$v" || declare -p "${v}_data" >/dev/null 2>&1; then gone=0; fi; done
if declare -p box_views >/dev/null 2>&1 || [[ -n ${__FV_VW_GRP[box]-} ]]; then gone=0; fi
if [[ $r == 1 && $(<"$E") == *"'box' is a live view"* && $REPLY == 'desk[]' && -z ${desk_data[Current]} && $gone == 1 ]]; then kt_test_pass "ok"
else kt_test_fail "rc=$r tree=$REPLY gone=$gone err=[$(<"$E")]"; fi
box.delete

kt_test_start "a subclass constructor that checks fv.views.isView after inherited returns the refusal; one that does not continues, but its view is no live view"
class TDlg : TGroup
    public
        var Title
        constructor Create
end
TDlg.Create() { inherited; fv.views.isView "$this" || return 1; Title=$5; }
build TDlg
class TLax : TView
    public
        var Title
        constructor Create
end
TLax.Create() { inherited; Title=$5; }
build TLax
TDlg.new dlg 0 0 10 5 hello; a=$?
TDlg.new dlg 0 0 10 5 again 2>/dev/null; b=$?
TLax.new lax 0 0 1 1 t; c=$?
TLax.new lax 0 0 1 1 t2 2>/dev/null; d=$?
if [[ $a$b$c$d == 0100 && ${dlg_data[Title]} == hello && ${lax_data[Title]} == t2 ]] && ! fv.views.isView dlg && ! fv.views.isView lax; then kt_test_pass "ok"
else kt_test_fail "rc=$a$b$c$d titles=${dlg_data[Title]}/${lax_data[Title]}"; fi
dlg.delete; lax.delete

kt_test_start "the dialog pattern in a loop (new, insert, delete, .delete) x5: clean; the anti-pattern (new again without .delete) fails loudly each time and the tree never grows"
out=''
for i in 1 2 3 4 5; do
    TDlg.new dlg 5 5 20 10 "n$i" 2>>"$E.loop" || out+="new$i "
    fv.views.insert desk dlg || out+="ins$i "
    fv.views.delete desk dlg || out+="del$i "
    dlg.delete
done
fvw_tree desk; t1=$REPLY
: > "$E.anti"
for i in 1 2 3 4; do
    TDlg.new dlg 5 5 20 10 "a$i" 2>>"$E.anti" && fv.views.insert desk dlg 2>>"$E.anti"
done
fvw_tree desk; t2=$REPLY
nerr=0
while IFS= read -r l; do [[ $l == Error:* ]] && nerr=$(( nerr + 1 )); done < "$E.anti"
if [[ -z $out && $t1 == 'desk[]' && ! -s $E.loop && $t2 == 'desk[]' && $nerr == 2 ]]; then kt_test_pass "ok ($nerr Error lines for 2 re-creations over a live dialog)"
else kt_test_fail "out=[$out] t1=$t1 t2=$t2 errors=$nerr"; fi
# (iterations 1 and 3 create and insert; 2 and 4 hit the live one: refused,
# its tree repaired, the stale dialog out of the desktop -> it ends empty)
dlg.delete

kt_test_start "a user constructor that skipped inherited: .new succeeds (kklass), insert refuses it loudly (rc 2); a group of such a class refused as the target"
class TNoInh : TView
    public
        var Title
        constructor Create
end
TNoInh.Create() { Title=x; }
build TNoInh
class TNoInhG : TGroup
    public
        constructor Create
end
TNoInhG.Create() { :; }
build TNoInhG
TNoInh.new ni 0 0 1 1; a=$?
TNoInhG.new nig 0 0 1 1; b=$?
o=$(fv.views.insert desk ni 2>"$E"); c=$?
e1=$(<"$E")
TView.new pl 0 0 1 1
fv.views.insert nig pl 2>"$E"; d=$?
e2=$(<"$E")
if [[ $a$b$c$d == 0022 && -z $o && $e1 == "Error: fv.views: insert: 'ni' is not a live view: its constructor did not call inherited (TView.Create)" \
   && $e2 == "Error: fv.views: insert: 'nig' is not a live view: its constructor did not call inherited (TView.Create)" ]]; then kt_test_pass "ok"
else kt_test_fail "rc=$a$b$c$d e1=[$e1] e2=[$e2]"; fi
ni.delete; nig.delete

kt_test_start "VERBOSE_KKLASS=quiet: the same refusals with the same rc, no Error line"
TView.new q1 0 0 1 1
VERBOSE_KKLASS=quiet TView.new q1 0 0 1 1 2>"$E"; a=$?
VERBOSE_KKLASS=quiet TView.new q__fvx 0 0 1 1 2>>"$E"; b=$?
VERBOSE_KKLASS=quiet fv.views.insert desk q1 2>>"$E"; c=$?
if [[ $a$b$c == 122 && ! -s $E ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$a$b$c err=[$(<"$E")]"; fi

kt_test_start "a non-instance name (no kklass instance) is refused quietly (rc 2, a debug line only)"
fv.views.insert desk 'no such' 2>"$E"; a=$?
fv.views.insert desk nosuch 2>>"$E"; b=$?
VERBOSE_KKLASS=debug fv.views.insert desk nosuch 2>"$E.dbg"; c=$?
if [[ $a$b$c == 222 && ! -s $E && $(<"$E.dbg") == "Error: fv.views.insert: 'nosuch' is not a view" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$a$b$c err=[$(<"$E")] dbg=[$(<"$E.dbg")]"; fi


kt_test_start "every rc-2 refusal sets RESULT '' and gives exactly one debug line (none without the switch): argument counts, bad integers, a bad ROLE, a destroyed view (review 2c-1 #5)"
TView.new gone 0 0 1 1; gone.delete; TView.new lv 0 0 1 1
out='' nl=0
for c in 'fv.views.insert desk' 'fv.views.insertBefore desk x' 'fv.views.delete desk' 'fv.views.putInFrontOf lv' 'fv.views.makeFirst' \
    'fv.views.first' 'fv.views.last' 'fv.views.next' 'fv.views.prevView lv lv' 'fv.views.getBounds' 'fv.views.getExtent lv x' \
    'fv.views.locate lv 0 0 1' 'fv.views.moveTo lv 1' 'fv.views.growTo lv' 'fv.views.changeBounds lv 0 0 1' 'fv.views.makeLocal lv 1' \
    'fv.views.makeGlobal lv' 'fv.views.mouseInView lv 1' 'fv.views.mouseInView lv 1 x' 'fv.views.moveTo lv x 1' \
    'fv.views._newReserved desk a-b TView 0 0 1 1' 'fv.views._newReserved desk frame' 'fv.views.insert desk gone'; do
    RESULT=x; $c 2>"$E"; r=$?
    [[ $r == 2 && -z $RESULT && ! -s $E ]] || out+="[quiet: $c rc=$r R=$RESULT]"
    RESULT=x; VERBOSE_KKLASS=debug $c 2>"$E"; r=$?
    n=0; while IFS= read -r l; do [[ $l == 'Error: fv.views.'* ]] && n=$(( n + 1 )); done < "$E"
    [[ $r == 2 && -z $RESULT && $n == 1 ]] || out+="[debug: $c rc=$r R=$RESULT lines=$n $(<"$E")]"
    nl=$(( nl + 1 ))
done
if [[ -z $out ]]; then kt_test_pass "$nl calls"; else kt_test_fail "$out"; fi
lv.delete
kt_test_log "018_Names.sh completed"
