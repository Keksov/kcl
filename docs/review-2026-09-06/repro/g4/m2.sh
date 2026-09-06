source /c/projects/kkbot/kbool/kcl/math/math.sh
math.feStart
p() { local r; r=$(math.$1 "${@:2}" 2>&1); echo "math.$* -> [$r]"; }
p sin "1 2"; p ceil " 5"; p sin ""; p sqrt abc; p min 0x10 5; p ceil 0x10; p ceil 1e3; p floor "1.2.3"; p min "1.2.3" 1.25; p sign "-"; p ceil "+-5"; p ceil "1-2.5"
echo "--- negative zero"
p roundTo -0.4 0; p roundTo -0.004 -2; p simpleRoundTo -0.001; p simpleRoundTo -0.4 0; p ceil -0.5; p floor -0.0; p fmod -1 1; p sign -0.0; p degNormalize -0.0; p ceil -1e-9; p floor 1e-9
echo "--- roundTo banker's / FPC parity"
p roundTo 2.5 0; p roundTo 3.5 0; p roundTo -2.5 0; p roundTo 0.125 -2; p roundTo 2.675 -2; p roundTo 1234.5678 2; p roundTo 12345 3; p roundTo 1.25 -1; p simpleRoundTo 1.005 -2; p simpleRoundTo 2.5 0; p simpleRoundTo -2.5 0
echo "--- inf/nan"
p sqrt -1; p ln 0; p ln -1; p exp 1000; p isNan "$(math.sqrt -1)"; p isInfinite "$(math.exp 1000)"; p min nan 1; p max inf 1; p max 1 inf; p ceil inf; p ceil nan; p sign nan; p inRange nan 0 1; p isZero nan
echo "--- frexp/ldexp/power"
p frexp 0; p frexp -8; p ldexp 1 1024; p power 2 0.5; p power -8 0.3333; p power -2 3; p power 0 -1; p intPower 2 -2; p intPower 1.5 3; p intPower 2 1e18
