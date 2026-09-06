#!/bin/bash
source /c/projects/kkbot/kbool/kcl/tcustomapplication/tcustomapplication.sh
echo "--- A1 --opt=value (FPC's long-option value syntax)"
TCustomApplication.new a; a.SetArgs -- --config=data.ini file.txt
a.GetOptionValue "" config; echo "GetOptionValue config -> [$RESULT] (FPC: data.ini)"
a.HasOption "" config; echo "HasOption config -> $RESULT (FPC: true)"
a.CheckOptions "" "config:"; echo "CheckOptions '' 'config:' -> [$RESULT] (FPC: '')"
a.CheckOptions "" "config"; echo "CheckOptions '' 'config' -> [$RESULT] (FPC: 'Option at position 1 does not allow an argument: config')"
a.GetNonOptions "" "config:"; echo "GetNonOptions -> $RESULT (FPC: 1)"
a.delete
echo "--- A2 ':' / '::' in ShortOptions ignored"
TCustomApplication.new a; a.SetArgs -- -c cfg.ini -v tail.txt
a.CheckOptions "c:v" ""; echo "CheckOptions 'c:v' -> [$RESULT]"
a.GetNonOptions "c:v" "" nn; echo "GetNonOptions 'c:v' -> $RESULT [${nn[*]}] (FPC: 1 [tail.txt]; cfg.ini consumed by -c)"
a.SetArgs -- -c
a.CheckOptions "c:" ""; echo "'-c' alone with 'c:' -> [$RESULT] (FPC: 'Option at position 1 needs an argument : c')"
a.SetArgs -- -cv x
a.CheckOptions "c:v" ""; echo "'-cv x' with 'c:v' -> [$RESULT] (FPC: error, c needs arg but is not last in cluster)"
a.SetArgs -- --verbose
a.CheckOptions "" "verbose:"; echo "'--verbose' with 'verbose:' -> [$RESULT] (FPC: needs an argument error)"
a.delete
echo "--- A3 CaseSensitiveOptions=false ignored"
TCustomApplication.new a; a.property CaseSensitiveOptions = false; a.SetArgs -- -V file --Verbose x
a.HasOption v; echo "HasOption v (args -V) -> $RESULT (FPC: true)"
a.HasOption "" verbose; echo "HasOption verbose (args --Verbose) -> $RESULT (FPC: true)"
a.CheckOptions "v" "verbose"; echo "CheckOptions 'v' 'verbose' -> [$RESULT] (FPC: '')"
a.delete
echo "--- A4 ParamCount / Params use the method's own \$#, not stored args"
TCustomApplication.new a -v file.txt out.txt
a.ParamCount; echo "ParamCount -> $RESULT (FPC: 3)"
a.Params 1; echo "Params 1 -> [$RESULT] (FPC: -v)"
a.Params 1 2 3; echo "Params 1 2 3 -> [$RESULT]  (returns its own 1st arg)"
a._GetArgs; echo "_GetArgs -> $RESULT"
a.delete
echo "--- A5 _EnsureArgsInitialized captures METHOD parameters as app args when SetArgs never called"
TCustomApplication.new a
a.GetNonOptions "" "" nn; echo "fresh app GetNonOptions '' '' -> $RESULT [${nn[*]@Q}] (expected 0)"
a._GetArgs; echo "stored args count now = $RESULT"
a.delete
TCustomApplication.new b
b.HasOption "" "-x"; echo "fresh app HasOption '' '-x' -> $RESULT"
b.delete
TCustomApplication.new c
c.CheckOptions "hv" "help" "false"; echo "fresh app CheckOptions -> [$RESULT]"; c.GetNonOptions "hv" "help" nn; echo "  then GetNonOptions -> $RESULT [${nn[*]@Q}]"
c.delete
echo "--- A6 test-019 pattern: CheckOptions ... false \"\$@\" with real params"
set -- -h file.txt
TCustomApplication.new d
d.CheckOptions "hv" "help version verbose" "false" "$@"; echo "CheckOptions(real params -h file.txt) -> [$RESULT]"
d.GetNonOptions "hv" "help version verbose" nn; echo "  non-options -> $RESULT [${nn[*]@Q}] (expected 1 [file.txt])"
d.delete
set --
echo "--- A7 GetOptionValues encoding"
TCustomApplication.new a; a.SetArgs -- -f "a b" -f "c"
a.GetOptionValues f; echo "values -> [$RESULT] (2 values 'a b','c' indistinguishable from 3)"
IFS=:; a.GetOptionValues f; echo "with caller IFS=: -> [$RESULT]"; unset IFS
a.delete
echo "--- A8 long_opts array-name coupling with opts_param"
TCustomApplication.new a; a.SetArgs -- --help
declare -a lo=(help version); declare -a o n
a.CheckOptions "" lo o n; echo "with out-arrays: [$RESULT] opts=[${o[*]}]"
a.CheckOptions "" lo; echo "without out-arrays: [$RESULT] (array name treated as literal option name)"
a.CheckOptions "" lo "false"; echo "with all_errors only: [$RESULT]"
declare -a empty_lo=(); a.SetArgs -- --; a.CheckOptions "" empty_lo o n; echo "empty array + '--' arg: [$RESULT] non_opts=[${n[*]@Q}]"
a.delete
echo "--- A9 AllErrors ignored"
TCustomApplication.new a; a.SetArgs -- -x -y
a.CheckOptions "v" "" "true"; echo "AllErrors=true -> [$RESULT] (FPC: two messages: -x and -y)"
a.delete
echo "--- A10 '-' and '--' args"
TCustomApplication.new a; a.SetArgs -- - -- x
a.CheckOptions "v" "" o n; echo "[$RESULT] non_opts=[${n[*]@Q}] (FPC: '-' and '--' are invalid options)"
a.delete
echo "--- A11 EnvironmentVariable indirect expansion"
M=$PWD/.inj_env_$$; rm -f "$M"
TCustomApplication.new a
a.EnvironmentVariable 'x[$(touch '"$M"')]' 2>&1; if [[ -e $M ]]; then echo "EnvironmentVariable: RCE via subscript"; else echo "EnvironmentVariable: safe"; fi; rm -f "$M"
a.EnvironmentVariable 'not valid' 2>&1; echo "invalid name -> rc=$? RESULT=[$RESULT]"
a.EnvironmentVariable '@'; echo "name '@' -> [$RESULT]"
a.delete
echo "--- A12 Location / ExeName"
TCustomApplication.new a; a.Location; echo "Location -> $RESULT (FPC: dir of running program; cwd=$PWD, script=$0)"; a.ExeName; echo "ExeName -> $RESULT"; a.delete
echo "--- A13 Terminate exports EXITCODE into env"
TCustomApplication.new a; a.Terminate 7; echo "child sees EXITCODE=$(bash -c 'echo $EXITCODE')"; a.delete
echo "--- A14 Run: no DoRun"
if declare -f TCustomApplication.DoRun >/dev/null 2>&1; then echo "DoRun exists"; else echo "no DoRun method (FPC Run calls DoRun until Terminated)"; fi
grep -c "DoRun" /c/projects/kkbot/kbool/kcl/tcustomapplication/tcustomapplication.sh
echo "--- A15 GetOptionValue with OptionChar=+ and value starting with +"
TCustomApplication.new a; a.property OptionChar = "+"; a.SetArgs -- +c +v
a.GetOptionValue c; echo "-> [$RESULT] (FPC: also '+v' since FPC hardcodes '-' in GetOptionAtIndex)"; a.delete
echo "--- A16 GetNonOptions creates global _dummy_opts"
unset _dummy_opts; TCustomApplication.new a; a.SetArgs -- -v f; a.GetNonOptions v ""; declare -p _dummy_opts 2>&1 | cut -c1-80; a.delete
echo "--- A17 out-array named like an internal local"
TCustomApplication.new a; a.SetArgs -- -v f
declare -a found_opts=() values=(); a.CheckOptions v "" found_opts values; echo "opts into 'found_opts' -> [${found_opts[*]}] non-opts into 'values' -> [${values[*]}] (expected -v / f)"
a.delete
echo "--- A18 Log: EventLogFilter substring, output stream"
TCustomApplication.new a; a.property EventLogFilter = "etError"; a.Log etErr "substring-matched type" >/dev/null && echo "etErr passed filter 'etError' (printed to stdout)"; a.Log "" "empty type" 2>/dev/null; a.delete
echo "--- A19 FindOptionIndex start_at injection"
M=$PWD/.inj_fo_$$; TCustomApplication.new a; a.SetArgs -- -v; a.FindOptionIndex v "" 'a[$(touch '"$M"')]' 2>/dev/null; if [[ -e $M ]]; then echo "FindOptionIndex start_at: RCE"; else echo "safe"; fi; rm -f "$M"; a.delete
echo "--- A20 leak check after delete"
TCustomApplication.new a; a.SetArgs -- -v x; a.delete; echo "vars left with prefix a_: $(compgen -v | grep -c '^a_')"
echo "--- A21 first vs last occurrence"
TCustomApplication.new a; a.SetArgs -- -c one -c two; a.GetOptionValue c; echo "GetOptionValue c -> $RESULT (FPC 3.2.2 FindOptionIndex scans from the END -> two)"; a.delete
echo "--- A22 GetEnvironmentList newline in value"
export NLV=$'l1\nl2'; TCustomApplication.new a; declare -a el; a.GetEnvironmentList el true; c=0; for e in "${el[@]}"; do [[ $e == l2 ]] && ((c++)); done; echo "entries equal to 'l2' (should be 0): $c"; a.delete
echo "--- A23 --opt= empty value and '--opt value' for long"
TCustomApplication.new a; a.SetArgs -- --name= --out file
a.GetOptionValue "" name; echo "GetOptionValue name (--name=) -> [$RESULT]"
a.GetOptionValue "" out; echo "GetOptionValue out (--out file) -> [$RESULT] (FPC: '' — long values only via =)"
a.delete
echo "--- A24 HandleException with OnException containing spaces"
TCustomApplication.new a; a.property OnException = "my handler"; a.HandleException s m 2>&1 | head -1; a.delete
