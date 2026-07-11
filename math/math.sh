#!/bin/bash

# ===========================================================================
# math — a bash port of Free Pascal's Math unit (kcl static class).
#
# Source of truth:
#   C:/projects/KKMindWave/VendorsCore/fpc/sources/main/rtl/objpas/math.pp
# Plan / ledger: kcl/math/PLAN.md, kcl/math/math_ledger.json
#
# ---- The hybrid model ------------------------------------------------------
# FPC's Math is ~80% floating point (trig, log, exp, hyperbolic, statistics,
# financial). Bash has no float type, so this port splits the unit by
# feasibility:
#
#   Tier A  integer/decimal core  — everything bash computes EXACTLY and
#           fork-free (Min/Max/Sign/InRange/EnsureRange/DivMod/Ceil/Floor/
#           RoundTo/CompareValue/IfThen/SumInt/...). Exact FPC parity.
#   Tier B  transcendental        — delegated to a persistent `awk`
#           co-process (the "float engine"). One fork per process (lazy),
#           then sub-ms pipe round-trips. awk == C double == FPC Double on
#           the x86-64 targets, so results match to ~1-2 ulps.
#   Tier C  FPU/precision control — no bash analogue; wontfix (see PLAN.md).
#
# ---- The float engine ------------------------------------------------------
# math._fe_start spawns ONE `awk` co-process (bash `coproc`) LAZILY, on the
# first Tier-B call, and keeps it alive for the process. math._fe writes one
# request line "op args..." and reads one "%.17g" answer line. awk's prelude
# (__MATH_AWK_PROG) defines every derived function from the primitives
# (sin cos atan2 exp log sqrt int ^) and fflush()es after each answer.
#
# Persistence & command substitution: a `$( math.sin ... )` subshell inherits
# a parent-started co-process and reuses it (verified: exactly one awk
# process). If the FIRST engine call is itself inside `$( )` with no prior
# start, the co-process lives only for that substitution — call `math.feStart`
# once (e.g. at script top) to guarantee a single shared engine. With no `awk`
# on PATH the engine degrades gracefully (returns 1); the Tier-A core is
# unaffected.
#
# ---- Class shape / performance ---------------------------------------------
# Pascal DSL static utility class (same pattern as dateutils/tpath/tfile):
# STRUCTURE first, method BODIES as real bash functions, then `build math`.
# The class declares NO `static var`, so every method gets the thin,
# capture-free dispatcher (fast on bash 5.2 and 5.3). Constants are therefore
# top-level __MATH_* globals (bash has no file scope), `readonly` where
# constant, behind the re-source guard. The engine's pid/fds are the mutable
# __MATH_FE_* globals. Internal helpers (math._dec_cmp, math._fe, ...) are
# plain functions, NOT class members: they return via REPLY / __m_* scratch
# globals and rely on dynamic scoping — zero subshells on the Tier-A paths.
# ===========================================================================

# Re-source guard: the __MATH_* constants below are readonly, and the class
# only needs to be built once per process.
if [[ -n "$_MATH_SOURCED" ]]; then
    return
fi
declare -g _MATH_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
MATH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MATH_DIR/../../kklass/kklass_pascal.sh"

# ---- Mathematical + IEEE constants (readonly __MATH_* process globals) ------
# Pi/E to Extended precision (FPC values). The IEEE range constants are
# INFORMATIONAL string tokens (bash cannot overflow/denormalise a native
# float); NaN/±Inf are the literal tokens the engine emits and IsNan/IsInfinite
# recognise.
__MATH_PI='3.1415926535897932385'
__MATH_E='2.7182818284590452354'
__MATH_INFINITY='inf'
__MATH_NEG_INFINITY='-inf'
__MATH_NAN='nan'
__MATH_MIN_SINGLE='1.1754943508e-38'
__MATH_MAX_SINGLE='3.4028234664e+38'
__MATH_MIN_DOUBLE='2.2250738585072014e-308'
__MATH_MAX_DOUBLE='1.7976931348623157e+308'
__MATH_MIN_EXTENDED='3.36210314311209350626e-4932'
__MATH_MAX_EXTENDED='1.18973149535723176502e+4932'

readonly __MATH_PI __MATH_E __MATH_INFINITY __MATH_NEG_INFINITY __MATH_NAN \
         __MATH_MIN_SINGLE __MATH_MAX_SINGLE __MATH_MIN_DOUBLE \
         __MATH_MAX_DOUBLE __MATH_MIN_EXTENDED __MATH_MAX_EXTENDED

# ---- Float-engine state (MUTABLE globals — not readonly) --------------------
__MATH_FE_UP=""       # non-empty once the co-process has been spawned
__MATH_FE_IN=""       # fd to write requests to (awk stdin)
__MATH_FE_OUT=""      # fd to read answers from (awk stdout)
__MATH_FE_PID=""      # awk co-process pid
__MATH_FE_PROGFILE="" # temp file holding the awk program (see _fe_start)

# The awk prelude: derived functions built from awk primitives + a dispatch
# loop. Grows per phase; P0 = the foundational op set that proves the engine.
# Single-quoted so awk's $1/$2 fields are NOT expanded by bash.
__MATH_AWK_PROG='
function _pi(       ) { return 4*atan2(1,1) }
function _tan(x     ) { return sin(x)/cos(x) }
function _hypot(x,y, t,r){ x=(x<0?-x:x); y=(y<0?-y:y); if(x<y){t=x;x=y;y=t} if(x==0)return 0; r=y/x; return x*sqrt(1+r*r) }
function _log10(x   ) { return log(x)/log(10) }
function _log2(x    ) { return log(x)/log(2) }
function _ipow(b,e,  r){ if(e<0){b=1.0/b;e=-e} r=1.0; while(e>0){ if(e%2==1) r=r*b; e=int(e/2); b=b*b } return r }
function _cosh(x)   { return (exp(x)+exp(-x))/2 }
function _sinh(x)   { return (exp(x)-exp(-x))/2 }
function _tnh(x,  t){ if(x>10)return 1; if(x<-10)return -1; if(x<0){t=exp(2*x);return (t-1)/(1+t)} t=exp(-2*x); return (1-t)/(1+t) }
function _asin(x)   { return atan2(x, sqrt((1-x)*(1+x))) }
function _acos(x)   { return atan2(sqrt((1-x)*(1+x)), x) }
function _arsinh(x) { return (x<0?-1:1)*log((x<0?-x:x)+sqrt(1+x*x)) }
function _arcosh(x) { return log(x+sqrt((x-1)*(x+1))) }
function _artanh(x) { return 0.5*log((1+x)/(1-x)) }
function _lnxp1(x,  y,r){ if(x>=4) return log(1+x); y=1+x; if(y==1) return x; r=log(y); if(y>0) r+=(x-(y-1))/y; return r }
function _expm1(x,  u){ u=exp(x); if(u==1) return x; if(u-1==-1) return -1; return (u-1)*x/log(u) }
function _power(b,e){ if(e==0) return 1; if(b==0 && e>0) return 0; if(e==int(e) && e<=2147483647 && e>=-2147483647) return _ipow(b,int(e)); return exp(e*log(b)) }
function _frexp(x,  e,m){ if(x==0){_fr_m=0;_fr_e=0;return} e=int(log(x<0?-x:x)/log(2))+1; m=x/(2^e); while((m<0?-m:m)>=1){m/=2;e++} while((m<0?-m:m)<0.5){m*=2;e--} _fr_m=m; _fr_e=e }
function _asum(    i,s){ s=0; for(i=2;i<=NF;i++) s+=$i; return s }
function _amean(      ){ return _asum()/(NF-1) }
function _asumsq(  i,s){ s=0; for(i=2;i<=NF;i++) s+=$i*$i; return s }
function _atotvar(i,mu,s){ mu=_amean(); s=0; for(i=2;i<=NF;i++) s+=($i-mu)*($i-mu); return s }
function _sgn(x){ return (x>0)-(x<0) }
function _fv(rate,n,pmt,pv,pt,   q,qn,f){ if(rate==0)return -pv-pmt*n; q=1+rate; qn=_ipow(q,int(n)); f=(qn-1)/(q-1); if(pt==1)f=f*q; return -(pv*qn+pmt*f) }
function _pvf(rate,n,pmt,fv,pt,  q,qn,f){ if(rate==0)return -fv-pmt*n; q=1+rate; qn=_ipow(q,int(n)); f=(qn-1)/(q-1); if(pt==1)f=f*q; return -(fv+pmt*f)/qn }
function _pmtf(rate,n,pv,fv,pt,  q,qn,f){ if(rate==0)return -(fv+pv)/n; q=1+rate; qn=_ipow(q,int(n)); f=(qn-1)/(q-1); if(pt==1)f=f*q; return -(fv+pv*qn)/f }
function _irate(n,pmt,pv,fv,pt,  r1,r2,dr,f1,f2,it){ it=0; r1=0.05; do{ r2=r1+0.001; f1=_fv(r1,n,pmt,pv,pt); f2=_fv(r2,n,pmt,pv,pt); dr=(fv-f1)/(f2-f1)*0.001; r1=r1+dr; it++ }while(!((dr<0?-dr:dr)<1e-9||it>=20)); return r1 }
BEGIN { srand() }
{
  op=$1
  if      (op=="sin")    printf "%.17g\n", sin($2)
  else if (op=="cos")    printf "%.17g\n", cos($2)
  else if (op=="tan")    printf "%.17g\n", _tan($2)
  else if (op=="sqrt")   printf "%.17g\n", sqrt($2)
  else if (op=="exp")    printf "%.17g\n", exp($2)
  else if (op=="ln")     printf "%.17g\n", log($2)
  else if (op=="log10")  printf "%.17g\n", _log10($2)
  else if (op=="log2")   printf "%.17g\n", _log2($2)
  else if (op=="atan2")  printf "%.17g\n", atan2($2,$3)
  else if (op=="pow")    printf "%.17g\n", $2^$3
  else if (op=="hypot")  printf "%.17g\n", _hypot($2,$3)
  else if (op=="pi")     printf "%.17g\n", _pi()
  else if (op=="sincos") printf "%.17g %.17g\n", sin($2), cos($2)
  else if (op=="cmp")    { a=$2+0; b=$3+0; printf "%d\n", (a<b?-1:(a>b?1:0)) }
  else if (op=="cmpd")   { a=$2+0; b=$3+0; d=$4+0; e=a-b; if(e<0)e=-e; printf "%d\n", (e<=d?0:(a<b?-1:1)) }
  else if (op=="iszero") { a=$2+0; e=$3+0; if(e==0)e=1e-12; aa=(a<0?-a:a); printf "%s\n", (aa<=e?"true":"false") }
  else if (op=="samev")  { a=$2+0; b=$3+0; e=$4+0; if(e==0){ma=(a<0?-a:a);mb=(b<0?-b:b);mn=(ma<mb?ma:mb);e=mn*1e-12; if(e<1e-12)e=1e-12} dd=a-b; if(dd<0)dd=-dd; printf "%s\n", (dd<=e?"true":"false") }
  else if (op=="ceil")   { x=$2+0; t=int(x); printf "%d\n", (x>t?t+1:t) }
  else if (op=="floor")  { x=$2+0; t=int(x); printf "%d\n", (x<t?t-1:t) }
  else if (op=="roundto"){ v=$2+0; rv=_ipow(10,int($3)); printf "%.17g\n", sprintf("%.0f", v/rv)*rv }
  else if (op=="sround") { v=$2+0; d=(NF>=3?int($3):-2); rv=_ipow(10,-d); if(v<0) r=int(v*rv-0.5); else r=int(v*rv+0.5); printf "%.17g\n", r/rv }
  else if (op=="fmod")   { a=$2+0; b=$3+0; printf "%.17g\n", a-b*int(a/b) }
  else if (op=="ipow")   { printf "%.17g\n", _ipow($2+0, int($3)) }
  else if (op=="d2r")    printf "%.17g\n", $2*(_pi()/180.0)
  else if (op=="r2d")    printf "%.17g\n", $2*(180.0/_pi())
  else if (op=="g2r")    printf "%.17g\n", $2*(_pi()/200.0)
  else if (op=="r2g")    printf "%.17g\n", $2*(200.0/_pi())
  else if (op=="d2g")    printf "%.17g\n", $2*(200.0/180.0)
  else if (op=="g2d")    printf "%.17g\n", $2*(180.0/200.0)
  else if (op=="c2d")    printf "%.17g\n", $2*360.0
  else if (op=="d2c")    printf "%.17g\n", $2*(1/360.0)
  else if (op=="c2g")    printf "%.17g\n", $2*400.0
  else if (op=="g2c")    printf "%.17g\n", $2*(1/400.0)
  else if (op=="c2r")    printf "%.17g\n", $2*2*_pi()
  else if (op=="r2c")    printf "%.17g\n", $2*(1/(2*_pi()))
  else if (op=="dnorm")  { r=$2-int($2/360)*360; if(r<0)r+=360; printf "%.17g\n", r }
  else if (op=="cotan")  printf "%.17g\n", cos($2)/sin($2)
  else if (op=="sec")    printf "%.17g\n", 1/cos($2)
  else if (op=="csc")    printf "%.17g\n", 1/sin($2)
  else if (op=="asin")   printf "%.17g\n", _asin($2)
  else if (op=="acos")   printf "%.17g\n", _acos($2)
  else if (op=="atan")   printf "%.17g\n", atan2($2,1)
  else if (op=="cosh")   printf "%.17g\n", _cosh($2)
  else if (op=="sinh")   printf "%.17g\n", _sinh($2)
  else if (op=="tanh")   printf "%.17g\n", _tnh($2)
  else if (op=="sech")   printf "%.17g\n", 1/_cosh($2)
  else if (op=="csch")   printf "%.17g\n", 1/_sinh($2)
  else if (op=="coth")   printf "%.17g\n", _cosh($2)/_sinh($2)
  else if (op=="arsinh") printf "%.17g\n", _arsinh($2)
  else if (op=="arcosh") printf "%.17g\n", _arcosh($2)
  else if (op=="artanh") printf "%.17g\n", _artanh($2)
  else if (op=="arcsec") printf "%.17g\n", _acos(1/$2)
  else if (op=="arccsc") printf "%.17g\n", _asin(1/$2)
  else if (op=="arccot") { x=$2+0; printf "%.17g\n", (x==0? 2*atan2(1,1) : atan2(1/x,1)) }
  else if (op=="arcsech"){ x=$2+0; printf "%.17g\n", log((1+sqrt(1-x*x))/x) }
  else if (op=="arccsch"){ x=$2+0; printf "%.17g\n", log((1/x)+sqrt(1/(x*x)+1)) }
  else if (op=="arccoth"){ x=$2+0; printf "%.17g\n", 0.5*log((x+1)/(x-1)) }
  else if (op=="logn")   printf "%.17g\n", log($3)/log($2)
  else if (op=="lnxp1")  printf "%.17g\n", _lnxp1($2)
  else if (op=="expm1")  printf "%.17g\n", _expm1($2)
  else if (op=="power")  printf "%.17g\n", _power($2,$3)
  else if (op=="frexp")  { _frexp($2); printf "%.17g %d\n", _fr_m, _fr_e }
  else if (op=="ldexp")  printf "%.17g\n", $2*(2^int($3))
  else if (op=="asum")      printf "%.17g\n", _asum()
  else if (op=="amean")     printf "%.17g\n", _amean()
  else if (op=="asumsq")    printf "%.17g\n", _asumsq()
  else if (op=="asumsandsq")printf "%.17g %.17g\n", _asum(), _asumsq()
  else if (op=="atotvar")   printf "%.17g\n", _atotvar()
  else if (op=="avariance") { n=NF-1; printf "%.17g\n", (n==1?0:_atotvar()/(n-1)) }
  else if (op=="apopnvar")  { n=NF-1; printf "%.17g\n", _atotvar()/n }
  else if (op=="astddev")   { n=NF-1; printf "%.17g\n", sqrt(n==1?0:_atotvar()/(n-1)) }
  else if (op=="apopnstddev"){ n=NF-1; printf "%.17g\n", sqrt(_atotvar()/n) }
  else if (op=="ameanstddev"){ n=NF-1; printf "%.17g %.17g\n", _amean(), sqrt(n==1?0:_atotvar()/(n-1)) }
  else if (op=="anorm")     printf "%.17g\n", sqrt(_asumsq())
  else if (op=="amoments")  { n=NF-1; mu=_amean(); tm2=0;tm3=0;tm4=0; for(i=2;i<=NF;i++){d=$i-mu;d2=d*d;tm2+=d2;tm3+=d2*d;tm4+=d2*d2} m2=tm2/n;m3=tm3/n;m4=tm4/n; printf "%.17g %.17g %.17g %.17g %.17g %.17g\n", mu,m2,m3,m4, m3/(sqrt(m2)*m2), m4/(m2*m2) }
  else if (op=="randg")     { do{u1=2*rand()-1;u2=2*rand()-1;s2=u1*u1+u2*u2}while(s2>=1||s2==0); printf "%.17g\n", sqrt(-2*log(s2)/s2)*u1*$3+$2 }
  else if (op=="fv")     printf "%.17g\n", _fv($2,$3,$4,$5,$6)
  else if (op=="pv")     printf "%.17g\n", _pvf($2,$3,$4,$5,$6)
  else if (op=="pmt")    printf "%.17g\n", _pmtf($2,$3,$4,$5,$6)
  else if (op=="irate")  printf "%.17g\n", _irate($2,$3,$4,$5,$6)
  else if (op=="nper")   { r=$2+0;pmt=$3+0;pv=$4+0;fv=$5+0;pt=$6+0; if(r==0){printf "%.17g\n",-(pv+fv)/pmt} else {q=1+r; if(pt==1)pmt=pmt*q; x1=pmt-fv*r; x2=pmt+pv*r; if(x2==0||_sgn(x1)*_sgn(x2)<0) print "inf"; else printf "%.17g\n", log(x1/x2)/log(q)} }
  else                   printf "ERR\n"
  fflush()
}'
readonly __MATH_AWK_PROG

# ---------------------------------------------------------------------------
# Class interface (grows per implementation phase; P0 = constants + engine).
# ---------------------------------------------------------------------------
class math
    public
        # mathematical + IEEE constant getters (FPC exposes the same names)
        static proc pi
        static proc e
        static proc infinity
        static proc negInfinity
        static proc nan
        static proc minSingle
        static proc maxSingle
        static proc minDouble
        static proc maxDouble
        static proc minExtended
        static proc maxExtended
        # float-engine lifecycle (kcl extension — see header)
        static proc feStart
        static proc feStop
        static proc feActive
        # --- P1: integer/decimal core ---
        static proc min
        static proc max
        static proc minValue
        static proc maxValue
        static proc minIntValue
        static proc maxIntValue
        static proc sign
        static proc inRange
        static proc ensureRange
        static proc isZero
        static proc sameValue
        static proc compareValue
        static proc ifThen
        # --- P2: rounding & number conversion ---
        static proc ceil
        static proc ceil64
        static proc floor
        static proc floor64
        static proc roundTo
        static proc simpleRoundTo
        static proc divMod
        static proc fmod
        static proc intPower
        # --- P3: angle conversions ---
        static proc degToRad
        static proc radToDeg
        static proc gradToRad
        static proc radToGrad
        static proc degToGrad
        static proc gradToDeg
        static proc cycleToDeg
        static proc degToCycle
        static proc cycleToGrad
        static proc gradToCycle
        static proc cycleToRad
        static proc radToCycle
        static proc degNormalize
        # --- P4: trig, inverse, hyperbolic, area ---
        static proc sin
        static proc cos
        static proc tan
        static proc cotan
        static proc cot
        static proc sinCos
        static proc secant
        static proc cosecant
        static proc sec
        static proc csc
        static proc arcSin
        static proc arcCos
        static proc arcTan
        static proc arcTan2
        static proc cosh
        static proc sinh
        static proc tanh
        static proc secH
        static proc cscH
        static proc cotH
        static proc arcCosH
        static proc arcSinH
        static proc arcTanH
        static proc arCosH
        static proc arSinH
        static proc arTanH
        static proc arcSec
        static proc arcCsc
        static proc arcCot
        static proc arcSecH
        static proc arcCscH
        static proc arcCotH
        # --- P5: logs, exponentials, powers, misc ---
        static proc log10
        static proc log2
        static proc logN
        static proc lnXP1
        static proc expM1
        static proc power
        static proc hypot
        static proc frexp
        static proc ldexp
        static proc sqrt
        static proc exp
        static proc ln
        # --- P6: statistics ---
        static proc sum
        static proc sumInt
        static proc mean
        static proc sumOfSquares
        static proc sumsAndSquares
        static proc variance
        static proc totalVariance
        static proc popnVariance
        static proc stdDev
        static proc popnStdDev
        static proc meanAndStdDev
        static proc momentSkewKurtosis
        static proc norm
        static proc randG
        # --- P7: financial ---
        static proc futureValue
        static proc presentValue
        static proc payment
        static proc interestRate
        static proc numberOfPeriods
        # --- P7: RNG + IEEE predicates ---
        static proc randomRange
        static proc randomFrom
        static proc isNan
        static proc isInfinite
        # --- P7: FPU control (wontfix stubs — no FPU in bash) ---
        static proc getRoundMode
        static proc setRoundMode
        static proc getPrecisionMode
        static proc setPrecisionMode
        static proc getExceptionMask
        static proc setExceptionMask
        static proc clearExceptions
end

# ===========================================================================
# Internal helpers (plain functions, NOT class members).
# ===========================================================================

# ---- Pure-bash decimal helpers (Tier A, zero forks) -----------------------

# Split a signed decimal string into normalised magnitude parts.
# <value> -> __m_sign (1|-1)   __m_int (no leading zeros)   __m_frac (no trailing zeros)
math._dec_split() {
    local v=$1
    __m_sign=1
    case $v in
        -*) __m_sign=-1; v=${v#-} ;;
        +*) v=${v#+} ;;
    esac
    local ip fp
    if [[ $v == *.* ]]; then ip=${v%%.*}; fp=${v#*.}; else ip=$v; fp=; fi
    while [[ ${#ip} -gt 1 && $ip == 0* ]]; do ip=${ip#0}; done
    [[ -z $ip ]] && ip=0
    while [[ $fp == *0 ]]; do fp=${fp%0}; done
    __m_int=$ip
    __m_frac=$fp
}

# Compare two magnitudes (already split). <ai> <af> <bi> <bf> -> REPLY -1|0|1
math._mag_cmp() {
    local ai=$1 af=$2 bi=$3 bf=$4
    if (( ${#ai} != ${#bi} )); then
        (( ${#ai} > ${#bi} )) && REPLY=1 || REPLY=-1; return
    fi
    if [[ $ai != "$bi" ]]; then
        [[ $ai > $bi ]] && REPLY=1 || REPLY=-1; return
    fi
    # equal integer parts: right-pad the shorter fraction with zeros, compare
    while (( ${#af} < ${#bf} )); do af+=0; done
    while (( ${#bf} < ${#af} )); do bf+=0; done
    if   [[ $af == "$bf" ]]; then REPLY=0
    elif [[ $af >  "$bf" ]]; then REPLY=1
    else                          REPLY=-1
    fi
}

# Compare two signed decimal strings numerically. <a> <b> -> REPLY -1|0|1
# Pure bash, overflow-safe (string comparison), handles negatives, -0, and
# differing precision (1.5 == 1.50). Plain decimals only (no exponent/inf/nan).
math._dec_cmp() {
    local as ai af bs bi bf az=0 bz=0
    math._dec_split "$1"; as=$__m_sign; ai=$__m_int; af=$__m_frac
    math._dec_split "$2"; bs=$__m_sign; bi=$__m_int; bf=$__m_frac
    [[ $ai == 0 && -z $af ]] && az=1
    [[ $bi == 0 && -z $bf ]] && bz=1
    if (( az && bz )); then REPLY=0; return; fi          # 0 == -0
    if (( az )); then (( bs > 0 )) && REPLY=-1 || REPLY=1; return; fi
    if (( bz )); then (( as > 0 )) && REPLY=1 || REPLY=-1; return; fi
    if (( as != bs )); then (( as > 0 )) && REPLY=1 || REPLY=-1; return; fi
    math._mag_cmp "$ai" "$af" "$bi" "$bf"
    (( as < 0 )) && REPLY=$(( -REPLY ))
}

# Is <value> an integer literal? (status only)
math._is_int() { [[ $1 =~ ^[+-]?[0-9]+$ ]]; }

# Integer part toward zero. <value> -> REPLY
math._trunc() {
    local v=$1 s=
    case $v in -*) s=-; v=${v#-} ;; +*) v=${v#+} ;; esac
    v=${v%%.*}
    while [[ ${#v} -gt 1 && $v == 0* ]]; do v=${v#0}; done
    [[ -z $v ]] && v=0
    REPLY=$s$v
    [[ $REPLY == -0 ]] && REPLY=0
}

# Signed fractional part (value - trunc(value)). <value> -> REPLY (0 if none)
math._frac() {
    local v=$1 s=
    case $v in -*) s=-; v=${v#-} ;; +*) v=${v#+} ;; esac
    local fp=
    [[ $v == *.* ]] && fp=${v#*.}
    while [[ $fp == *0 ]]; do fp=${fp%0}; done
    if [[ -z $fp ]]; then REPLY=0; else REPLY=${s}0.$fp; fi
}

# Absolute value (magnitude token). <value> -> REPLY
math._abs() { local v=${1#-}; REPLY=${v#+}; }

# Numeric compare with engine fallback for exotic operands (exponent, inf, nan).
# <a> <b> -> REPLY -1|0|1. Plain integers/decimals use the pure-bash comparator
# (zero forks); anything with a non-[digit . + -] character goes to the engine.
math._num_cmp() {
    # integer fast path (the common case): plain integers within 64-bit are
    # compared with arithmetic — much faster than the decimal split.
    if [[ $1 =~ ^[+-]?[0-9]{1,18}$ && $2 =~ ^[+-]?[0-9]{1,18}$ ]]; then
        (( $1 < $2 )) && REPLY=-1 || { (( $1 > $2 )) && REPLY=1 || REPLY=0; }
        return
    fi
    if [[ $1 == *[![:digit:].+-]* || $2 == *[![:digit:].+-]* ]]; then
        math._fe cmp "$1" "$2"
    else
        math._dec_cmp "$1" "$2"
    fi
}

# ---- Float engine (Tier B) ------------------------------------------------

# Start the awk co-process if not already running. Reuses an inherited,
# still-alive co-process (so a $() subshell doesn't spawn a second one).
# Returns 1 (no spawn) when awk is unavailable.
math._fe_start() {
    if [[ -n "$__MATH_FE_UP" ]] && kill -0 "$__MATH_FE_PID" 2>/dev/null; then
        return 0
    fi
    command -v awk >/dev/null 2>&1 || return 1
    # Feed the program to awk via a temp file (`awk -f`), NOT as a command-line
    # argument: on cygwin (bash 5.3) a large argument (>~8 KB) is truncated,
    # corrupting the program and killing the co-process. Some setups also resolve
    # /tmp differently for bash vs the native awk, so we try candidate dirs and
    # PROBE each — falling back to MATH_DIR (a real path both agree on) if the
    # co-process can't read the file. The file is written once per process and
    # shared by any $() subshell that inherits the path.
    local d _probe
    for d in "${TMPDIR:-/tmp}" "$MATH_DIR" /tmp; do
        [[ -d "$d" && -w "$d" ]] || continue
        __MATH_FE_PROGFILE="$d/.math_fe_$$.awk"
        printf '%s\n' "$__MATH_AWK_PROG" > "$__MATH_FE_PROGFILE" 2>/dev/null || { __MATH_FE_PROGFILE=""; continue; }
        coproc MATH_FE { awk -f "$__MATH_FE_PROGFILE" 2>/dev/null; }
        __MATH_FE_IN=${MATH_FE[1]}; __MATH_FE_OUT=${MATH_FE[0]}; __MATH_FE_PID=$MATH_FE_PID
        if printf 'pi\n' >&"$__MATH_FE_IN" 2>/dev/null \
           && IFS= read -r -t 5 -u "$__MATH_FE_OUT" _probe 2>/dev/null && [[ -n "$_probe" ]]; then
            __MATH_FE_UP=1
            return 0
        fi
        kill "$__MATH_FE_PID" 2>/dev/null
        rm -f "$__MATH_FE_PROGFILE" 2>/dev/null
        __MATH_FE_PROGFILE=""
    done
    __MATH_FE_IN=""; __MATH_FE_OUT=""; __MATH_FE_PID=""
    return 1
}

# One request/response round-trip. <op> [args...] -> REPLY (answer line).
# Returns 1 if the engine is unavailable.
math._fe() {
    math._fe_start || { REPLY=""; return 1; }
    printf '%s\n' "$*" >&"$__MATH_FE_IN"
    IFS= read -r REPLY <&"$__MATH_FE_OUT"
}

# Stop the co-process (it also dies with the shell).
math._fe_stop() {
    [[ -n "$__MATH_FE_UP" ]] || return 0
    kill "$__MATH_FE_PID" 2>/dev/null
    wait "$__MATH_FE_PID" 2>/dev/null
    [[ -n "$__MATH_FE_PROGFILE" ]] && rm -f "$__MATH_FE_PROGFILE" 2>/dev/null
    __MATH_FE_UP=""; __MATH_FE_IN=""; __MATH_FE_OUT=""; __MATH_FE_PID=""; __MATH_FE_PROGFILE=""
}

# ===========================================================================
# Public method bodies.
# ===========================================================================

# ---- constant getters ------------------------------------------------------
math.pi()          { echo "$__MATH_PI"; }
math.e()           { echo "$__MATH_E"; }
math.infinity()    { echo "$__MATH_INFINITY"; }
math.negInfinity() { echo "$__MATH_NEG_INFINITY"; }
math.nan()         { echo "$__MATH_NAN"; }
math.minSingle()   { echo "$__MATH_MIN_SINGLE"; }
math.maxSingle()   { echo "$__MATH_MAX_SINGLE"; }
math.minDouble()   { echo "$__MATH_MIN_DOUBLE"; }
math.maxDouble()   { echo "$__MATH_MAX_DOUBLE"; }
math.minExtended() { echo "$__MATH_MIN_EXTENDED"; }
math.maxExtended() { echo "$__MATH_MAX_EXTENDED"; }

# ---- float-engine lifecycle (kcl extension) --------------------------------
# feStart: start the shared engine now (opt-in for persistence across $()).
#          Returns 0 if the engine is up, 1 if no awk is available. No output.
math.feStart() { math._fe_start; }
# feStop: shut the engine down. No output.
math.feStop()  { math._fe_stop; }
# feActive: is the engine currently running? echoes true/false.
math.feActive() {
    if [[ -n "$__MATH_FE_UP" ]] && kill -0 "$__MATH_FE_PID" 2>/dev/null; then
        echo true
    else
        echo false
    fi
}

# ===========================================================================
# P1 — integer/decimal core.
# Tier A (pure-bash, zero-fork) for comparison-based ops on plain numbers;
# the engine handles only float-epsilon predicates (isZero/sameValue), the
# CompareValue tolerance form, and exotic-notation operands (via _num_cmp).
# ===========================================================================

# Min/Max of two operands. FPC: a if a<b else b / a if a>b else b (ties -> b).
math.min() { math._num_cmp "$1" "$2"; (( REPLY < 0 )) && echo "$1" || echo "$2"; }
math.max() { math._num_cmp "$1" "$2"; (( REPLY > 0 )) && echo "$1" || echo "$2"; }

# Min/Max over the argument list (echoes the winning argument verbatim).
math.minValue() { local best=$1 x; shift; for x in "$@"; do math._num_cmp "$x" "$best"; (( REPLY < 0 )) && best=$x; done; echo "$best"; }
math.maxValue() { local best=$1 x; shift; for x in "$@"; do math._num_cmp "$x" "$best"; (( REPLY > 0 )) && best=$x; done; echo "$best"; }

# Integer-array reducers (pure integer arithmetic).
math.minIntValue() { local best=$1 x; shift; for x in "$@"; do (( x < best )) && best=$x; done; echo "$best"; }
math.maxIntValue() { local best=$1 x; shift; for x in "$@"; do (( x > best )) && best=$x; done; echo "$best"; }

# Sign: -1 / 0 / 1  (TValueSign).
math.sign() { math._num_cmp "$1" 0; echo "$REPLY"; }

# InRange: is value in the closed interval [min,max]?  echoes true/false.
math.inRange() {
    math._num_cmp "$1" "$2"; (( REPLY < 0 )) && { echo false; return; }
    math._num_cmp "$1" "$3"; (( REPLY > 0 )) && { echo false; return; }
    echo true
}

# EnsureRange: clamp value into [min,max].
math.ensureRange() {
    math._num_cmp "$1" "$2"; (( REPLY < 0 )) && { echo "$2"; return; }
    math._num_cmp "$1" "$3"; (( REPLY > 0 )) && { echo "$3"; return; }
    echo "$1"
}

# CompareValue: -1 / 0 / 1. Optional float tolerance `delta` (nonzero -> engine).
math.compareValue() {
    local delta=$3
    if [[ -n $delta && ! $delta =~ ^[+-]?0*[.]?0*$ ]]; then
        math._fe cmpd "$1" "$2" "$delta"
    else
        math._num_cmp "$1" "$2"
    fi
    echo "$REPLY"
}

# IfThen: ternary. cond is true/1 => iftrue, else iffalse (default 0).
math.ifThen() {
    if [[ "$1" == true || "$1" == 1 ]]; then echo "$2"; else echo "${3:-0}"; fi
}

# IsZero: |value| <= epsilon (default 1e-12, the FPC Double resolution).
# Integer, default-epsilon case is fork-free; decimals / explicit epsilon use
# the engine (a float-tolerance predicate).
math.isZero() {
    if [[ -z "$2" ]] && math._is_int "$1"; then
        [[ "$1" == 0 || "$1" == -0 || "$1" == +0 ]] && echo true || echo false
        return
    fi
    math._fe iszero "$1" "${2:-0}"; echo "$REPLY"
}

# SameValue: |a-b| <= epsilon, epsilon defaulting to FPC's
# Max(Min(|a|,|b|)*1e-12, 1e-12). Float-tolerance predicate -> engine.
math.sameValue() { math._fe samev "$1" "$2" "${3:-0}"; echo "$REPLY"; }

# ===========================================================================
# P2 — rounding & number conversion.
# Tier A (pure-bash, zero-fork): ceil/ceil64/floor/floor64, divMod, and integer
# intPower. Tier B (engine, exact FPC-Double parity): roundTo (banker's),
# simpleRoundTo (arithmetic), fmod, and float/negative-exponent intPower.
# ===========================================================================

# Ceil: round toward +inf. FPC Trunc(x)+ord(Frac(x)>0).
math.ceil() {
    local x=$1
    [[ $x == *[![:digit:].+-]* ]] && { math._fe ceil "$x"; echo "$REPLY"; return; }
    math._trunc "$x"; local t=$REPLY
    math._frac "$x"; [[ $REPLY != 0 && $REPLY != -* ]] && t=$(( t + 1 ))
    echo "$t"
}
math.ceil64() { math.ceil "$1"; }

# Floor: round toward -inf. FPC Trunc(x)-ord(Frac(x)<0).
math.floor() {
    local x=$1
    [[ $x == *[![:digit:].+-]* ]] && { math._fe floor "$x"; echo "$REPLY"; return; }
    math._trunc "$x"; local t=$REPLY
    math._frac "$x"; [[ $REPLY == -* ]] && t=$(( t - 1 ))
    echo "$t"
}
math.floor64() { math.floor "$1"; }

# DivMod: integer division + remainder (truncation toward zero; remainder takes
# the dividend's sign — matches Pascal div/mod and bash / %). Echoes "quot rem".
math.divMod() {
    (( $2 == 0 )) && return 1
    echo "$(( $1 / $2 )) $(( $1 % $2 ))"
}

# RoundTo: Round(value/10^digits)*10^digits — banker's (half-to-even). Engine
# (awk sprintf %.0f is round-half-to-even -> exact FPC-Double parity).
math.roundTo() { math._fe roundto "$1" "$2"; echo "$REPLY"; }

# SimpleRoundTo: Int(value*RV +/- 0.5)/RV, RV=10^(-digits) — arithmetic rounding
# (half away from zero). Default digits = -2. Engine.
math.simpleRoundTo() {
    if [[ -n "$2" ]]; then math._fe sround "$1" "$2"; else math._fe sround "$1"; fi
    echo "$REPLY"
}

# FMod: floating-point modulo, a - b*Int(a/b). Engine.
math.fmod() { math._fe fmod "$1" "$2"; echo "$REPLY"; }

# IntPower: base^exponent (integer exponent) by squaring. Integer base with a
# non-negative exponent is exact pure-bash; float base or negative exponent
# (fractional result) uses the engine.
math.intPower() {
    if math._is_int "$1" && math._is_int "$2" && (( $2 >= 0 )); then
        echo $(( $1 ** $2 ))
    else
        math._fe ipow "$1" "$2"; echo "$REPLY"
    fi
}

# ===========================================================================
# P3 — angle conversions (engine; π is irrational and FPC returns Double).
# 1 cycle = 360 deg = 400 grad = 2π rad.
# ===========================================================================
math.degToRad()    { math._fe d2r "$1"; echo "$REPLY"; }
math.radToDeg()    { math._fe r2d "$1"; echo "$REPLY"; }
math.gradToRad()   { math._fe g2r "$1"; echo "$REPLY"; }
math.radToGrad()   { math._fe r2g "$1"; echo "$REPLY"; }
math.degToGrad()   { math._fe d2g "$1"; echo "$REPLY"; }
math.gradToDeg()   { math._fe g2d "$1"; echo "$REPLY"; }
math.cycleToDeg()  { math._fe c2d "$1"; echo "$REPLY"; }
math.degToCycle()  { math._fe d2c "$1"; echo "$REPLY"; }
math.cycleToGrad() { math._fe c2g "$1"; echo "$REPLY"; }
math.gradToCycle() { math._fe g2c "$1"; echo "$REPLY"; }
math.cycleToRad()  { math._fe c2r "$1"; echo "$REPLY"; }
math.radToCycle()  { math._fe r2c "$1"; echo "$REPLY"; }
# DegNormalize: wrap degrees into [0,360). Deg - Int(Deg/360)*360, +360 if <0.
math.degNormalize() { math._fe dnorm "$1"; echo "$REPLY"; }

# ===========================================================================
# P4 — trig, inverse trig, hyperbolic, area (all engine).
# sin/cos/arcTan are System-unit elementaries (not in math.pp) exposed for
# convenience. ArcSin/ArcCos use the numerically-stable sqrt((1-x)(1+x)) form;
# tanh is FPC's robust large-x formula; ArcSinH preserves sign.
# ===========================================================================
math.sin()      { math._fe sin "$1";    echo "$REPLY"; }
math.cos()      { math._fe cos "$1";    echo "$REPLY"; }
math.tan()      { math._fe tan "$1";    echo "$REPLY"; }
math.cotan()    { math._fe cotan "$1";  echo "$REPLY"; }
math.cot()      { math._fe cotan "$1";  echo "$REPLY"; }
math.sinCos()   { math._fe sincos "$1"; echo "$REPLY"; }   # echoes "sin cos"
math.secant()   { math._fe sec "$1";    echo "$REPLY"; }
math.cosecant() { math._fe csc "$1";    echo "$REPLY"; }
math.sec()      { math._fe sec "$1";    echo "$REPLY"; }
math.csc()      { math._fe csc "$1";    echo "$REPLY"; }
math.arcSin()   { math._fe asin "$1";   echo "$REPLY"; }
math.arcCos()   { math._fe acos "$1";   echo "$REPLY"; }
math.arcTan()   { math._fe atan "$1";   echo "$REPLY"; }
math.arcTan2()  { math._fe atan2 "$1" "$2"; echo "$REPLY"; }
math.cosh()     { math._fe cosh "$1";   echo "$REPLY"; }
math.sinh()     { math._fe sinh "$1";   echo "$REPLY"; }
math.tanh()     { math._fe tanh "$1";   echo "$REPLY"; }
math.secH()     { math._fe sech "$1";   echo "$REPLY"; }
math.cscH()     { math._fe csch "$1";   echo "$REPLY"; }
math.cotH()     { math._fe coth "$1";   echo "$REPLY"; }
math.arcCosH()  { math._fe arcosh "$1"; echo "$REPLY"; }
math.arcSinH()  { math._fe arsinh "$1"; echo "$REPLY"; }
math.arcTanH()  { math._fe artanh "$1"; echo "$REPLY"; }
math.arCosH()   { math._fe arcosh "$1"; echo "$REPLY"; }
math.arSinH()   { math._fe arsinh "$1"; echo "$REPLY"; }
math.arTanH()   { math._fe artanh "$1"; echo "$REPLY"; }
math.arcSec()   { math._fe arcsec "$1"; echo "$REPLY"; }
math.arcCsc()   { math._fe arccsc "$1"; echo "$REPLY"; }
math.arcCot()   { math._fe arccot "$1"; echo "$REPLY"; }
math.arcSecH()  { math._fe arcsech "$1"; echo "$REPLY"; }
math.arcCscH()  { math._fe arccsch "$1"; echo "$REPLY"; }
math.arcCotH()  { math._fe arccoth "$1"; echo "$REPLY"; }

# ===========================================================================
# P5 — logarithms, exponentials, powers, misc (engine; integer ** via P2 intPower).
# The float ** operator maps to power. sqrt/exp/ln are System-unit elementaries.
# ===========================================================================
math.log10() { math._fe log10 "$1";      echo "$REPLY"; }
math.log2()  { math._fe log2 "$1";       echo "$REPLY"; }
math.logN()  { math._fe logn "$1" "$2";  echo "$REPLY"; }   # logN base value
math.lnXP1() { math._fe lnxp1 "$1";      echo "$REPLY"; }   # ln(1+x), accurate near 0
math.expM1() { math._fe expm1 "$1";      echo "$REPLY"; }   # exp(x)-1, accurate near 0
math.power() { math._fe power "$1" "$2"; echo "$REPLY"; }
math.hypot() { math._fe hypot "$1" "$2"; echo "$REPLY"; }
math.frexp() { math._fe frexp "$1";      echo "$REPLY"; }   # echoes "mantissa exponent"
math.ldexp() { math._fe ldexp "$1" "$2"; echo "$REPLY"; }   # x * 2^p
math.sqrt()  { math._fe sqrt "$1";       echo "$REPLY"; }
math.exp()   { math._fe exp "$1";        echo "$REPLY"; }
math.ln()    { math._fe ln "$1";         echo "$REPLY"; }

# ===========================================================================
# P6 — statistics. Arrays are passed as the argument list; the engine computes
# each statistic in one awk pass. sumInt is pure-bash integer (zero-fork).
# Sample Variance/StdDev use N-1; PopnVariance/PopnStdDev use N.
# ===========================================================================
math.sum()            { math._fe asum "$@";       echo "$REPLY"; }
math.mean()           { math._fe amean "$@";      echo "$REPLY"; }
math.sumOfSquares()   { math._fe asumsq "$@";     echo "$REPLY"; }
math.sumsAndSquares() { math._fe asumsandsq "$@"; echo "$REPLY"; }   # "sum sumOfSquares"
math.variance()       { math._fe avariance "$@";  echo "$REPLY"; }   # sample (N-1)
math.totalVariance()  { math._fe atotvar "$@";    echo "$REPLY"; }   # Sum((x-mean)^2)
math.popnVariance()   { math._fe apopnvar "$@";   echo "$REPLY"; }   # population (N)
math.stdDev()         { math._fe astddev "$@";    echo "$REPLY"; }
math.popnStdDev()     { math._fe apopnstddev "$@"; echo "$REPLY"; }
math.meanAndStdDev()  { math._fe ameanstddev "$@"; echo "$REPLY"; }  # "mean stddev"
math.momentSkewKurtosis() { math._fe amoments "$@"; echo "$REPLY"; } # "m1 m2 m3 m4 skew kurtosis"
math.norm()           { math._fe anorm "$@";      echo "$REPLY"; }   # euclidean L2
math.randG()          { math._fe randg "$1" "$2"; echo "$REPLY"; }   # gaussian(mean,stddev)
# SumInt: pure-bash integer sum (exact, zero-fork).
math.sumInt() { local s=0 x; for x in "$@"; do s=$(( s + x )); done; echo "$s"; }

# ===========================================================================
# P7 — financial (annuity), RNG, IEEE predicates, FPU stubs.
# Financial: engine. APaymentTime is a 0/1 flag (0=ptEndOfPeriod default,
# 1=ptStartOfPeriod). RNG + predicates are pure-bash (zero-fork).
# ===========================================================================
math.futureValue()     { math._fe fv "$1" "$2" "$3" "$4" "${5:-0}"; echo "$REPLY"; }   # rate n payment presentValue [ptype]
math.presentValue()    { math._fe pv "$1" "$2" "$3" "$4" "${5:-0}"; echo "$REPLY"; }   # rate n payment futureValue [ptype]
math.payment()         { math._fe pmt "$1" "$2" "$3" "$4" "${5:-0}"; echo "$REPLY"; }  # rate n presentValue futureValue [ptype]
math.interestRate()    { math._fe irate "$1" "$2" "$3" "$4" "${5:-0}"; echo "$REPLY"; } # nPeriods payment presentValue futureValue [ptype]
math.numberOfPeriods() { math._fe nper "$1" "$2" "$3" "$4" "${5:-0}"; echo "$REPLY"; } # rate payment presentValue futureValue [ptype]

# RandomRange: uniform integer in [min(from,to), max(from,to)) — upper-exclusive
# (FPC Random(Abs(from-to))+Min). Pure-bash 30-bit RNG (two $RANDOM), zero-fork.
math.randomRange() {
    local from=$1 to=$2 lo hi n
    (( from < to )) && { lo=$from; hi=$to; } || { lo=$to; hi=$from; }
    n=$(( hi - lo ))
    (( n == 0 )) && { echo "$lo"; return; }
    echo $(( lo + (RANDOM<<15 | RANDOM) % n ))
}

# RandomFrom: a random element of the argument list. Zero-fork.
math.randomFrom() {
    local -a vals=("$@")
    local n=${#vals[@]}
    (( n == 0 )) && return 1
    local idx=$(( (RANDOM<<15 | RANDOM) % n ))
    echo "${vals[idx]}"
}

# IsNan / IsInfinite: test for the nan / +/-inf tokens the engine emits. Pure-bash.
math.isNan()      { local re='^[+-]?[nN]a[nN]$';            [[ $1 =~ $re ]] && echo true || echo false; }
math.isInfinite() { local re='^[+-]?([iI]nf|[iI]nfinity)$'; [[ $1 =~ $re ]] && echo true || echo false; }

# FPU control — WONTFIX: bash has no FPU control word. Getters report the
# conventional default (informational only); setters return 1; clearExceptions
# is a no-op (there are no pending FPU exceptions in bash). See PLAN.md / ledger.
math.getRoundMode()     { echo "rmNearest"; }
math.setRoundMode()     { return 1; }
math.getPrecisionMode() { echo "pmDouble"; }
math.setPrecisionMode() { return 1; }
math.getExceptionMask() { echo "[exInvalidOp,exDenormalized,exZeroDivide,exOverflow,exUnderflow,exPrecision]"; }
math.setExceptionMask() { return 1; }
math.clearExceptions()  { return 0; }

build math
