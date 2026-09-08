#!/bin/bash

# ===========================================================================
# math — a bash port of Free Pascal's Math unit (kcl static class).
#
# Source of truth: FPC 3.2.2 `rtl/objpas/math.pp`
#   (https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/rtl/objpas/math.pp)
# Plan / ledger: kcl/math/PLAN.md, kcl/math/math_ledger.json
#
# ---- The hybrid model ------------------------------------------------------
# FPC's Math is ~80% floating point (trig, log, exp, hyperbolic, statistics,
# financial). Bash has no float type, so this port splits the unit by
# feasibility:
#
#   Tier A  integer/decimal core  — everything bash computes EXACTLY and
#           fork-free (Min/Max/Sign/InRange/EnsureRange/DivMod/Ceil/Floor/
#           CompareValue/IfThen/SumInt/RandomRange/...). Exact FPC parity.
#   Tier B  transcendental        — delegated to a persistent `awk` float
#           engine. One fork per process (lazy), then sub-ms pipe round-trips.
#           awk == C double == FPC Double on the x86-64 targets, so results
#           match to ~1-2 ulps.
#   Tier C  FPU/precision control — no bash analogue; wontfix (see PLAN.md).
#
# ---- The float engine ------------------------------------------------------
# math._fe_start spawns ONE `awk` co-process (bash `coproc`) LAZILY, on the
# first Tier-B call, and keeps it alive for the process. math._fe writes one
# request line "op args..." and reads one "%.17g" answer line.
#
# R11 (2026-09-08) — THE ENGINE NEVER DIES, and no call is ever answered by
# silence:
#   * every division in the awk prelude goes through `_dv()`, which returns
#     +inf / -inf / nan instead of letting gawk abort on a zero denominator
#     (M1: `fmod 5 0`, `cotan 0`, `logN 1 5`, `mean` with no data, ... each
#     used to kill the co-process and answer an empty line with rc 0);
#   * `_frexp` is bounded, so `frexp inf|nan|1e308` answers instead of
#     spinning forever (M2);
#   * every argument is validated by `math._is_num` BEFORE it is written, so a
#     newline can never split one request into two and desynchronise the pipe
#     for the rest of the process (M3);
#   * the answer is read with `read -t` (`$__MATH_FE_TIMEOUT`, default 10 s):
#     a genuinely wedged engine is dropped and reported, never waited on;
#   * `inf`/`nan` tokens are normalised on the way in (gawk parses a bare
#     `inf` as 0 — it needs the sign) and on the way out (gawk emits `+inf`
#     and `-nan`), so the tokens this unit publishes are the tokens it
#     accepts (M5);
#   * awk runs under `LC_ALL=C`, so `%.17g` prints `2.5`, never `2,5` (M15);
#   * the program reaches awk through PROCESS SUBSTITUTION (`awk -f <(...)`),
#     which leaves nothing on disk (M6). Both bashes on this machine were
#     probed and keep the substitution alive for the co-process's lifetime; if
#     it ever fails the code falls back to a temp file plus an EXIT trap that
#     CHAINS the caller's own EXIT handler instead of replacing it;
#   * a restart reaps the old co-process first, so bash never prints
#     `execute_coproc: coproc [pid:MATH_FE] still exists` (M9);
#   * with no awk at all a Tier-B member is rc 1 + RESULT='' + silence (M10);
#     the whole Tier-A core is unaffected.
#
# Persistence & command substitution: a `$( math.sin ... )` subshell inherits
# a parent-started co-process and reuses it (verified: exactly one awk
# process). If the FIRST engine call is itself inside `$( )` with no prior
# start, the co-process lives only for that substitution — call `math.feStart`
# once (e.g. at script top) to guarantee a single shared engine.
#
# ---- Return contract (D3) --------------------------------------------------
# Every member is a `static proc` that answers through RESULT and prints
# NOTHING on a direct call; inside `$( )` it prints its value exactly once.
# That is `math._ret`, the unit-local form of `kk._return` — a `static func`
# would echo on EVERY call, because kklass's thin static dispatcher re-prints
# the returned value unconditionally (kcl/README.md §1.1, same pattern as
# tpath/tfile/tdirectory/dateutils). Booleans answer with their EXIT STATUS
# and carry the word true/false in RESULT (R8). Errors are rc 1 + RESULT=''
# with nothing on stdout or stderr; rc 2 is a malformed CALL (§1.2).
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
if [[ -n "${_MATH_SOURCED:-}" ]]; then
    return
fi
declare -g _MATH_SOURCED=1

# Character semantics are part of the kcl contract (README §1.6); an empty
# environment means the C locale. math itself is ASCII-only, but a caller that
# sources it first must not inherit a broken ctype from it.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
MATH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MATH_DIR/../../kklass/kklass_pascal.sh"

# ---- Mathematical + IEEE constants (readonly __MATH_* process globals) ------
# Pi/E to Extended precision (FPC values). The IEEE range constants are
# INFORMATIONAL string tokens (bash cannot overflow/denormalise a native
# float); NaN/±Inf are the literal tokens the engine emits and IsNan/IsInfinite
# recognise. They are also the tokens the engine ACCEPTS (math._is_num
# normalises them to the signed form gawk understands).
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

# Largest / smallest int64 — the boundary the pure-bash exact paths must not
# cross silently (M8). $(( )) is intmax_t and wraps past these.
__MATH_INT64_MAX=9223372036854775807
__MATH_INT64_MIN=-9223372036854775808
readonly __MATH_INT64_MAX __MATH_INT64_MIN

# ---- Float-engine state (MUTABLE globals — not readonly) --------------------
__MATH_FE_UP=""       # non-empty once the co-process has been spawned
__MATH_FE_IN=""       # fd to write requests to (awk stdin)
__MATH_FE_OUT=""      # fd to read answers from (awk stdout)
__MATH_FE_PID=""      # awk co-process pid
__MATH_FE_PROGFILE="" # temp file holding the awk program (fallback path only)
__MATH_FE_TRAPPED=""  # non-empty once the EXIT trap chain has been armed
# Answer timeout in seconds, used on the start probe always and on every call
# when __MATH_FE_STRICT is non-empty (see math._fe for why it is not the
# default: `read -t` costs ~410 us a call on this platform).
__MATH_FE_TIMEOUT=10
__MATH_FE_STRICT="${__MATH_FE_STRICT:-}"
# The awk prelude: derived functions built from awk primitives + a dispatch
# loop. Single-quoted so awk's $1/$2 fields are NOT expanded by bash.
#
# R11 — THE ENGINE NEVER DIES. gawk treats a division by zero as a FATAL
# error, so a single `1/0` anywhere in here killed the co-process and every
# later call answered an empty line (M1). Therefore: this program divides ONLY
# through _dv(), which returns the IEEE value FPC's FPU would produce with the
# zero-divide exception masked (+inf / -inf / nan). `math/tests/014` asserts
# structurally that no other `/` survives in this string.
#
# The non-finite values themselves are built in BEGIN (1e308*10 overflows to
# +inf; inf-inf is nan) rather than written as literals, because gawk parses a
# bare `inf` token as 0.
__MATH_AWK_PROG='
function _dv(a,b) { if (b == 0) { if (a == 0) return _NAN; return (a < 0 ? _NINF : _INF) } return a/b }
function _isnan(x,  s){ s=sprintf("%g",x); return (index(s,"nan") > 0) }
function _nf(x,     s){ s=sprintf("%g",x); return (index(s,"nan") > 0 || index(s,"inf") > 0) }
function _pn(x)     { if (x == 0) x = 0; printf "%.17g\n", x }
function _pd(x,  ax){ if (_isnan(x)) { print "nan"; return } ax=(x<0?-x:x); if (ax >= 9.2233720368547758e18) { printf "%.17g\n", x; return } if (x == 0) x = 0; printf "%d\n", x }
function _pi(       ) { return 4*atan2(1,1) }
function _tan(x     ) { return _dv(sin(x),cos(x)) }
function _hypot(x,y, t,r){ x=(x<0?-x:x); y=(y<0?-y:y); if(x<y){t=x;x=y;y=t} if(x==0)return 0; r=_dv(y,x); return x*sqrt(1+r*r) }
function _log10(x   ) { return _dv(log(x),log(10)) }
function _log2(x    ) { return _dv(log(x),log(2)) }
function _ipow(b,e,  r){ if(e<0){b=_dv(1.0,b);e=-e} r=1.0; while(e>0){ if(e%2==1) r=r*b; e=int(_dv(e,2)); b=b*b } return r }
function _cosh(x)   { return _dv(exp(x)+exp(-x),2) }
function _sinh(x)   { return _dv(exp(x)-exp(-x),2) }
function _tnh(x,  t){ if(x>10)return 1; if(x<-10)return -1; if(x<0){t=exp(2*x);return _dv(t-1,1+t)} t=exp(-2*x); return _dv(1-t,1+t) }
function _asin(x)   { return atan2(x, sqrt((1-x)*(1+x))) }
function _acos(x)   { return atan2(sqrt((1-x)*(1+x)), x) }
function _arsinh(x) { return (x<0?-1:1)*log((x<0?-x:x)+sqrt(1+x*x)) }
function _arcosh(x) { return log(x+sqrt((x-1)*(x+1))) }
function _artanh(x) { return 0.5*log(_dv(1+x,1-x)) }
function _lnxp1(x,  y,r){ if(x>=4) return log(1+x); y=1+x; if(y==1) return x; r=log(y); if(y>0) r+=_dv(x-(y-1),y); return r }
function _expm1(x,  u){ u=exp(x); if(u==1) return x; if(u-1==-1) return -1; return _dv((u-1)*x,log(u)) }
function _power(b,e){ if(e==0) return 1; if(b==0 && e>0) return 0; if(e==int(e) && e<=2147483647 && e>=-2147483647) return _ipow(b,int(e)); return exp(e*log(b)) }
function _frexp(x,  a){ if(x==0 || _nf(x)){ _fr_m=x; _fr_e=0; return }
  _fr_m=x; _fr_e=0; a=(x<0?-x:x)
  while(a>=1){ if(a>=_P256){_fr_m=_fr_m*_M256;_fr_e+=256} else if(a>=_P32){_fr_m=_fr_m*_M32;_fr_e+=32} else {_fr_m=_fr_m*0.5;_fr_e+=1} a=(_fr_m<0?-_fr_m:_fr_m) }
  while(a<0.5){ if(a<_M256){_fr_m=_fr_m*_P256;_fr_e-=256} else if(a<_M32){_fr_m=_fr_m*_P32;_fr_e-=32} else {_fr_m=_fr_m*2;_fr_e-=1} a=(_fr_m<0?-_fr_m:_fr_m) } }
function _asum(    i,s){ s=0; for(i=2;i<=NF;i++) s+=$i; return s }
function _amean(      ){ return _dv(_asum(),NF-1) }
function _asumsq(  i,s){ s=0; for(i=2;i<=NF;i++) s+=$i*$i; return s }
function _atotvar(i,mu,s){ if(NF<2) return _NAN; mu=_amean(); s=0; for(i=2;i<=NF;i++) s+=($i-mu)*($i-mu); return s }
function _sgn(x){ return (x>0)-(x<0) }
function _fv(rate,n,pmt,pv,pt,   q,qn,f){ if(rate==0)return -pv-pmt*n; q=1+rate; qn=_ipow(q,int(n)); f=_dv(qn-1,q-1); if(pt==1)f=f*q; return -(pv*qn+pmt*f) }
function _pvf(rate,n,pmt,fv,pt,  q,qn,f){ if(rate==0)return -fv-pmt*n; q=1+rate; qn=_ipow(q,int(n)); f=_dv(qn-1,q-1); if(pt==1)f=f*q; return _dv(-(fv+pmt*f),qn) }
function _pmtf(rate,n,pv,fv,pt,  q,qn,f){ if(rate==0)return _dv(-(fv+pv),n); q=1+rate; qn=_ipow(q,int(n)); f=_dv(qn-1,q-1); if(pt==1)f=f*q; return _dv(-(fv+pv*qn),f) }
function _irate(n,pmt,pv,fv,pt,  r1,r2,dr,f1,f2,it){ it=0; r1=0.05; do{ r2=r1+0.001; f1=_fv(r1,n,pmt,pv,pt); f2=_fv(r2,n,pmt,pv,pt); dr=_dv(fv-f1,f2-f1)*0.001; r1=r1+dr; it++ }while(!((dr<0?-dr:dr)<1e-9||it>=20)); return r1 }
BEGIN { srand(); _INF=1e308*10; _NINF=-_INF; _NAN=_INF-_INF; _P32=2^32; _M32=2^-32; _P256=2^256; _M256=2^-256 }
{
  op=$1
  if      (op=="sin")    _pn(sin($2))
  else if (op=="cos")    _pn(cos($2))
  else if (op=="tan")    _pn(_tan($2))
  else if (op=="sqrt")   _pn(sqrt($2))
  else if (op=="exp")    _pn(exp($2))
  else if (op=="ln")     _pn(log($2))
  else if (op=="log10")  _pn(_log10($2))
  else if (op=="log2")   _pn(_log2($2))
  else if (op=="atan2")  _pn(atan2($2,$3))
  else if (op=="pow")    _pn($2^$3)
  else if (op=="hypot")  _pn(_hypot($2,$3))
  else if (op=="pi")     _pn(_pi())
  else if (op=="sincos") { printf "%.17g %.17g\n", sin($2), cos($2) }
  else if (op=="cmp")    { a=$2+0; b=$3+0; if(_isnan(a)||_isnan(b)) print "2"; else printf "%d\n", (a<b?-1:(a>b?1:0)) }
  else if (op=="cmpd")   { a=$2+0; b=$3+0; d=$4+0; e=a-b; if(e<0)e=-e; printf "%d\n", ((!_isnan(e) && e<=d)?0:(a<b?-1:1)) }
  else if (op=="iszero") { a=$2+0; e=$3+0; if(e==0)e=1e-12; aa=(a<0?-a:a); printf "%s\n", ((!_isnan(aa) && aa<=e)?"true":"false") }
  else if (op=="samev")  { a=$2+0; b=$3+0; e=$4+0; if(e==0){ma=(a<0?-a:a);mb=(b<0?-b:b);mn=(ma<mb?ma:mb);e=mn*1e-12; if(e<1e-12)e=1e-12} if(a>b) dd=a-b; else dd=b-a; printf "%s\n", ((!_isnan(dd) && dd<=e)?"true":"false") }
  else if (op=="ceil")   { x=$2+0; if(_nf(x)) _pn(x); else { t=int(x); _pd(x>t?t+1:t) } }
  else if (op=="floor")  { x=$2+0; if(_nf(x)) _pn(x); else { t=int(x); _pd(x<t?t-1:t) } }
  else if (op=="roundto"){ v=$2+0; rv=_ipow(10,int($3)); q=_dv(v,rv); if(_nf(q)) _pn(q*rv); else _pn((sprintf("%.0f",q)+0)*rv) }
  else if (op=="sround") { v=$2+0; d=(NF>=3?int($3):-2); rv=_ipow(10,-d); t=v*rv; if(_nf(t)) _pn(_dv(t,rv)); else { if(t<0) r=int(t-0.5); else r=int(t+0.5); _pn(_dv(r,rv)) } }
  else if (op=="fmod")   { a=$2+0; b=$3+0; if(b==0) _pn(_NAN); else if(_nf(a)) _pn(_NAN); else _pn(a-b*int(_dv(a,b))) }
  else if (op=="ipow")   _pn(_ipow($2+0, int($3)))
  else if (op=="d2r")    _pn($2*_dv(_pi(),180.0))
  else if (op=="r2d")    _pn($2*_dv(180.0,_pi()))
  else if (op=="g2r")    _pn($2*_dv(_pi(),200.0))
  else if (op=="r2g")    _pn($2*_dv(200.0,_pi()))
  else if (op=="d2g")    _pn($2*_dv(200.0,180.0))
  else if (op=="g2d")    _pn($2*_dv(180.0,200.0))
  else if (op=="c2d")    _pn($2*360.0)
  else if (op=="d2c")    _pn($2*_dv(1,360.0))
  else if (op=="c2g")    _pn($2*400.0)
  else if (op=="g2c")    _pn($2*_dv(1,400.0))
  else if (op=="c2r")    _pn($2*2*_pi())
  else if (op=="r2c")    _pn($2*_dv(1,2*_pi()))
  else if (op=="dnorm")  { x=$2+0; if(_nf(x)) _pn(_NAN); else { r=x-int(_dv(x,360))*360; if(r<0)r+=360; _pn(r) } }
  else if (op=="cotan")  _pn(_dv(cos($2),sin($2)))
  else if (op=="sec")    _pn(_dv(1,cos($2)))
  else if (op=="csc")    _pn(_dv(1,sin($2)))
  else if (op=="asin")   _pn(_asin($2))
  else if (op=="acos")   _pn(_acos($2))
  else if (op=="atan")   _pn(atan2($2,1))
  else if (op=="cosh")   _pn(_cosh($2))
  else if (op=="sinh")   _pn(_sinh($2))
  else if (op=="tanh")   _pn(_tnh($2))
  else if (op=="sech")   _pn(_dv(1,_cosh($2)))
  else if (op=="csch")   _pn(_dv(1,_sinh($2)))
  else if (op=="coth")   _pn(_dv(_cosh($2),_sinh($2)))
  else if (op=="arsinh") _pn(_arsinh($2))
  else if (op=="arcosh") _pn(_arcosh($2))
  else if (op=="artanh") _pn(_artanh($2))
  else if (op=="arcsec") _pn(_acos(_dv(1,$2)))
  else if (op=="arccsc") _pn(_asin(_dv(1,$2)))
  else if (op=="arccot") { x=$2+0; _pn(x==0 ? 2*atan2(1,1) : atan2(_dv(1,x),1)) }
  else if (op=="arcsech"){ x=$2+0; _pn(log(_dv(1+sqrt(1-x*x),x))) }
  else if (op=="arccsch"){ x=$2+0; _pn(log(_dv(1,x)+sqrt(_dv(1,x*x)+1))) }
  else if (op=="arccoth"){ x=$2+0; _pn(0.5*log(_dv(x+1,x-1))) }
  else if (op=="logn")   _pn(_dv(log($3),log($2)))
  else if (op=="lnxp1")  _pn(_lnxp1($2))
  else if (op=="expm1")  _pn(_expm1($2))
  else if (op=="power")  _pn(_power($2,$3))
  else if (op=="frexp")  { _frexp($2+0); printf "%.17g %d\n", _fr_m, _fr_e }
  else if (op=="ldexp")  _pn($2*(2^int($3)))
  else if (op=="asum")      _pn(_asum())
  else if (op=="amean")     _pn(_amean())
  else if (op=="asumsq")    _pn(_asumsq())
  else if (op=="asumsandsq"){ printf "%.17g %.17g\n", _asum(), _asumsq() }
  else if (op=="atotvar")   _pn(_atotvar())
  else if (op=="avariance") { n=NF-1; _pn(n<1 ? _NAN : (n==1?0:_dv(_atotvar(),n-1))) }
  else if (op=="apopnvar")  { n=NF-1; _pn(n<1 ? _NAN : _dv(_atotvar(),n)) }
  else if (op=="astddev")   { n=NF-1; _pn(n<1 ? _NAN : sqrt(n==1?0:_dv(_atotvar(),n-1))) }
  else if (op=="apopnstddev"){ n=NF-1; _pn(n<1 ? _NAN : sqrt(_dv(_atotvar(),n))) }
  else if (op=="ameanstddev"){ n=NF-1; printf "%.17g %.17g\n", _amean(), (n<1 ? _NAN : sqrt(n==1?0:_dv(_atotvar(),n-1))) }
  else if (op=="anorm")     _pn(sqrt(_asumsq()))
  else if (op=="amoments")  { n=NF-1; if(n<1){ printf "%.17g %.17g %.17g %.17g %.17g %.17g\n", _NAN,_NAN,_NAN,_NAN,_NAN,_NAN } else { mu=_amean(); tm2=0;tm3=0;tm4=0; for(i=2;i<=NF;i++){d=$i-mu;d2=d*d;tm2+=d2;tm3+=d2*d;tm4+=d2*d2} m2=_dv(tm2,n);m3=_dv(tm3,n);m4=_dv(tm4,n); printf "%.17g %.17g %.17g %.17g %.17g %.17g\n", mu,m2,m3,m4, _dv(m3,sqrt(m2)*m2), _dv(m4,m2*m2) } }
  else if (op=="randg")     { do{u1=2*rand()-1;u2=2*rand()-1;s2=u1*u1+u2*u2}while(s2>=1||s2==0); _pn(sqrt(_dv(-2*log(s2),s2))*u1*$3+$2) }
  else if (op=="fv")     _pn(_fv($2,$3,$4,$5,$6))
  else if (op=="pv")     _pn(_pvf($2,$3,$4,$5,$6))
  else if (op=="pmt")    _pn(_pmtf($2,$3,$4,$5,$6))
  else if (op=="irate")  _pn(_irate($2,$3,$4,$5,$6))
  else if (op=="nper")   { r=$2+0;pmt=$3+0;pv=$4+0;fv=$5+0;pt=$6+0; if(r==0){_pn(_dv(-(pv+fv),pmt))} else {q=1+r; if(pt==1)pmt=pmt*q; x1=pmt-fv*r; x2=pmt+pv*r; if(x2==0||_sgn(x1)*_sgn(x2)<0) _pn(_INF); else _pn(_dv(log(_dv(x1,x2)),log(q)))} }
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

# ---- Return contract (D3, kcl/README.md §1.1) ------------------------------

# math._ret VALUE [STATUS]
#   RESULT = VALUE; print it ONLY inside a $( ) subshell; return STATUS.
math._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# math._retBool 0|nonzero — R8: the exit status IS the answer, RESULT carries
# the word so `$( )` callers keep working. math._ret's two lines are INLINED
# here: every boolean member goes through this, and a second function call is
# ~5 us on a shell this size.
math._retBool() {
    if [[ "$1" == "0" ]]; then
        RESULT="true"
        if (( BASH_SUBSHELL > 0 )); then printf '%s' "true"; fi
        return 0
    fi
    RESULT="false"
    if (( BASH_SUBSHELL > 0 )); then printf '%s' "false"; fi
    return 1
}

# math._err — the one error exit: rc 1, RESULT cleared, nothing printed (§1.2).
math._err() { RESULT=""; return 1; }

# ---- Numeric argument validation (D1 + M14) --------------------------------

# math._is_num VALUE -> rc 0 and __m_num = the token to send to the engine.
# kk.isNum owns real numbers (and deliberately refuses inf/nan, which are this
# unit's business). gawk parses a BARE `inf`/`nan` as 0 and only recognises the
# signed spellings, so the token is normalised to `+inf` / `-inf` / `+nan`.
math._is_num() {
    if kk.isNum "${1:-}"; then __m_num="$__KK_NUM"; return 0; fi
    local __m_t="${1:-}" __m_sgn='+'
    case $__m_t in
        -*) __m_sgn='-'; __m_t="${__m_t#-}" ;;
        +*) __m_t="${__m_t#+}" ;;
    esac
    case $__m_t in
        [iI][nN][fF]|[iI][nN][fF][iI][nN][iI][tT][yY]) __m_num="${__m_sgn}inf"; return 0 ;;
        [nN][aA][nN])                                  __m_num="${__m_sgn}nan"; return 0 ;;
    esac
    __m_num=""
    return 1
}

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
    if (( as < 0 )); then REPLY=$(( -REPLY )); fi
    return 0                    # X-SETE (M7): never fail the caller under set -e
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
    return 0                    # X-SETE (M7): never fail the caller under set -e
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

# base^exp by squaring, EXACT in int64. <base> <exp>=0 -> __m_ip, or rc 1 when
# the result (or an intermediate square that is still needed) leaves int64
# (M8). FPC's IntPower returns a FLOAT (math.pp:1044), so overflow is not a
# wrap there and must not be one here: the caller falls through to the engine.
math._ipow_i() {
    local __m_b=$1 __m_e=$2 __m_r=1 __m_t
    while (( __m_e > 0 )); do
        if (( __m_e % 2 == 1 )); then
            __m_t=$(( __m_r * __m_b ))
            if (( __m_b != 0 && (__m_t / __m_b != __m_r || (__m_b == -1 && __m_r == __MATH_INT64_MIN)) )); then
                return 1
            fi
            __m_r=$__m_t
        fi
        __m_e=$(( __m_e / 2 ))
        if (( __m_e > 0 )); then
            __m_t=$(( __m_b * __m_b ))
            if (( __m_b != 0 && __m_t / __m_b != __m_b )); then return 1; fi
            __m_b=$__m_t
        fi
    done
    __m_ip=$__m_r
    return 0
}

# Numeric compare with engine fallback for exotic operands (exponent, inf, nan).
# <a> <b> -> REPLY -1|0|1|2, rc 1 when either operand is not a number.
# REPLY=2 means UNORDERED (a NaN is involved): FPC's comparisons are all false
# there, so each caller decides what that means for it — Min/Max take the
# second operand (math.pp:2033 `if a>b then a else b`), Sign is 0 (:729
# `ord(v>0)-ord(v<0)`), InRange is false (:2157), EnsureRange passes the value
# through (:2185) and CompareValue is GreaterThanValue (:2576).
math._num_cmp() {
    # integer fast path (the common case): plain integers within 64-bit are
    # compared with arithmetic — much faster than the decimal split, and the
    # pattern itself is the validation.
    if [[ $1 =~ ^[+-]?[0-9]{1,18}$ && $2 =~ ^[+-]?[0-9]{1,18}$ ]]; then
        # The regex admits leading zeros, and `(( 08 ))` is an octal parse error,
        # not 8 (M4). `10#` cannot follow a sign, so the sign is lifted out of
        # the base prefix: `-10#08` is unary minus applied to `10#08`.
        # `return 0`: a bare `return` here reports the last arithmetic status and
        # aborts the caller under `set -e` (M7).
        local __m_a=$(( ${1%%[0-9]*}10#${1#[-+]} )) __m_b=$(( ${2%%[0-9]*}10#${2#[-+]} ))
        (( __m_a < __m_b )) && REPLY=-1 || { (( __m_a > __m_b )) && REPLY=1 || REPLY=0; }
        return 0
    fi
    # plain decimal path: exact, fork-free, and the test IS the validation
    # (M14 — `abc`, `0x10`, `1.2.3`, `+-5` used to reach the engine as 0).
    # Globs, not `[[ =~ ]]`: an ERE costs ~12 us against ~6 us for this pair of
    # case tests, and _num_cmp is the hottest Tier-A helper in the unit.
    local __m_dec=1
    case $1 in ""|*[!0-9.+-]*) __m_dec=0 ;;
               *) case ${1#[-+]} in ""|.|*[-+]*|*.*.*) __m_dec=0 ;; esac ;; esac
    case $2 in ""|*[!0-9.+-]*) __m_dec=0 ;;
               *) case ${2#[-+]} in ""|.|*[-+]*|*.*.*) __m_dec=0 ;; esac ;; esac
    if (( __m_dec )); then
        math._dec_cmp "$1" "$2"
        return 0
    fi
    # exponent / inf / nan: validate, then let the engine compare as Doubles
    local __m_x __m_y
    math._is_num "${1:-}" || { REPLY=0; return 1; }; __m_x="$__m_num"
    math._is_num "${2:-}" || { REPLY=0; return 1; }; __m_y="$__m_num"
    math._fe cmp "$__m_x" "$__m_y" || { REPLY=0; return 1; }
    return 0
}

# ---- Float engine (Tier B) ------------------------------------------------

# Reap the co-process and forget it, so the next start is clean and silent
# (M9: bash warns `execute_coproc: coproc [pid:MATH_FE] still exists` if the
# slot is still occupied).
math._fe_drop() {
    if [[ -n "$__MATH_FE_PID" ]]; then
        kill "$__MATH_FE_PID" 2>/dev/null
        wait "$__MATH_FE_PID" 2>/dev/null
    fi
    if [[ -n "$__MATH_FE_IN" ]]; then eval "exec ${__MATH_FE_IN}>&-" 2>/dev/null; fi
    if [[ -n "$__MATH_FE_OUT" ]]; then eval "exec ${__MATH_FE_OUT}<&-" 2>/dev/null; fi
    __MATH_FE_UP=""; __MATH_FE_IN=""; __MATH_FE_OUT=""; __MATH_FE_PID=""
    return 0
}

# Remove the fallback temp file (no-op on the process-substitution path).
math._fe_cleanup() {
    if [[ -n "$__MATH_FE_PROGFILE" ]]; then
        rm -f -- "$__MATH_FE_PROGFILE" 2>/dev/null
        __MATH_FE_PROGFILE=""
    fi
    return 0
}

# Arm the EXIT trap for the fallback temp file, CHAINING whatever the caller
# had installed rather than replacing it (§1.9).
math._fe_arm_trap() {
    [[ -n "$__MATH_FE_TRAPPED" ]] && return 0
    __MATH_FE_TRAPPED=1
    local __m_prev
    __m_prev="$(trap -p EXIT)"
    if [[ -n "$__m_prev" ]]; then
        # `trap -p` prints  trap -- 'BODY' EXIT
        __m_prev="${__m_prev#*\'}"
        __m_prev="${__m_prev%\'*}"
        trap "math._fe_cleanup; $__m_prev" EXIT
    else
        trap 'math._fe_cleanup' EXIT
    fi
    return 0
}

# Start the awk co-process if not already running. Reuses an inherited,
# still-alive co-process (so a $() subshell doesn't spawn a second one).
# Returns 1 (no spawn) when awk is unavailable.
math._fe_start() {
    if [[ -n "$__MATH_FE_UP" ]] && kill -0 "$__MATH_FE_PID" 2>/dev/null; then
        return 0
    fi
    [[ -n "$__MATH_FE_PID" ]] && math._fe_drop
    command -v awk >/dev/null 2>&1 || { __MATH_FE_UP=""; return 1; }

    # Preferred: hand the program to awk through PROCESS SUBSTITUTION. Nothing
    # is written to disk (M6), and a large program cannot be truncated the way
    # a command-line argument is on cygwin. Probed on bash 5.2.37 and 5.3.9 on
    # this machine: awk reads /dev/fd/N to EOF at start-up and the co-process
    # then lives independently of the substitution.
    # LC_ALL=C (M15): gawk honours LC_NUMERIC under POSIXLY_CORRECT and would
    # print `2,5` in a comma locale.
    coproc MATH_FE { LC_ALL=C awk -f <(printf '%s\n' "$__MATH_AWK_PROG") 2>/dev/null; }
    __MATH_FE_IN=${MATH_FE[1]}; __MATH_FE_OUT=${MATH_FE[0]}; __MATH_FE_PID=$MATH_FE_PID
    local __m_probe
    if printf 'pi\n' >&"$__MATH_FE_IN" 2>/dev/null \
       && IFS= read -r -t "$__MATH_FE_TIMEOUT" -u "$__MATH_FE_OUT" __m_probe 2>/dev/null \
       && [[ -n "$__m_probe" ]]; then
        __MATH_FE_UP=1
        return 0
    fi
    math._fe_drop

    # Fallback: a temp file plus an EXIT trap. Some setups resolve /tmp
    # differently for bash and for a native awk, so each candidate directory is
    # PROBED rather than assumed.
    local __m_d
    for __m_d in "${TMPDIR:-/tmp}" "$MATH_DIR" /tmp; do
        [[ -d "$__m_d" && -w "$__m_d" ]] || continue
        __MATH_FE_PROGFILE="$__m_d/.math_fe_$$.awk"
        printf '%s\n' "$__MATH_AWK_PROG" > "$__MATH_FE_PROGFILE" 2>/dev/null \
            || { __MATH_FE_PROGFILE=""; continue; }
        math._fe_arm_trap
        coproc MATH_FE { LC_ALL=C awk -f "$__MATH_FE_PROGFILE" 2>/dev/null; }
        __MATH_FE_IN=${MATH_FE[1]}; __MATH_FE_OUT=${MATH_FE[0]}; __MATH_FE_PID=$MATH_FE_PID
        if printf 'pi\n' >&"$__MATH_FE_IN" 2>/dev/null \
           && IFS= read -r -t "$__MATH_FE_TIMEOUT" -u "$__MATH_FE_OUT" __m_probe 2>/dev/null \
           && [[ -n "$__m_probe" ]]; then
            __MATH_FE_UP=1
            return 0
        fi
        math._fe_drop
        math._fe_cleanup
    done
    __MATH_FE_UP=""
    return 1
}

# Normalise the engine's IEEE spellings to this unit's tokens: gawk prints
# `+inf` / `-inf` / `-nan`, the unit publishes `inf` / `-inf` / `nan` (M5), and
# a multi-field answer is normalised field by field. `-0` is already folded to
# `0` by the prelude's _pn (M11); a multi-field answer is folded here.
math._fe_norm() {
    local IFS=$' \t\n'
    local __m_o="" __m_t
    for __m_t in $REPLY; do
        case $__m_t in
            +inf|inf|+Inf|Inf|+INF|INF|+infinity|infinity) __m_t=inf ;;
            -inf|-Inf|-INF|-infinity)                      __m_t=-inf ;;
            nan|+nan|-nan|NaN|+NaN|-NaN|NAN|+NAN|-NAN)     __m_t=nan ;;
            -0|-0.0)                                       __m_t=0 ;;
        esac
        __m_o+="${__m_o:+ }$__m_t"
    done
    REPLY="$__m_o"
    return 0
}

# One request/response round-trip. <op> [args...] -> REPLY (answer line).
# Returns 1 if the engine is unavailable, the request is unsendable, or the
# answer does not arrive within $__MATH_FE_TIMEOUT seconds. Arguments are
# expected to be pre-validated tokens (math._is_num); the newline guard is the
# belt to that brace, because ONE stray newline desynchronises the pipe for the
# rest of the process (M3).
math._fe() {
    math._fe_start || { REPLY=""; return 1; }
    local __m_req="$*"
    case $__m_req in
        *$'\n'*) REPLY=""; return 1 ;;
    esac
    printf '%s\n' "$__m_req" >&"$__MATH_FE_IN" 2>/dev/null || {
        math._fe_drop; REPLY=""; return 1
    }
    # `read -t` costs ~410 us per call on BOTH bashes here (measured 5.2.37 and
    # 5.3.9, and the figure does not depend on the timeout value — bash's timed
    # read polls per byte), against ~105 us for the whole round trip. It is
    # therefore used where it buys something and not on the hot path:
    #   * the START PROBE always uses it, so a co-process that never speaks is
    #     caught at birth;
    #   * a DEAD engine needs no timeout at all — the pipe is closed, `read`
    #     sees EOF and fails at once, which is the case R11 is really about;
    #   * `__MATH_FE_STRICT=1` turns it on for every call, for a caller whose
    #     awk might be stopped or wedged from outside.
    # No `2>/dev/null` on the read: the fd was just validated by _fe_start, and
    # EOF (the engine died) makes `read` fail SILENTLY. The printf above keeps
    # its redirect because a write to a broken pipe does talk.
    if [[ -n "${__MATH_FE_STRICT:-}" ]]; then
        if ! IFS= read -r -t "$__MATH_FE_TIMEOUT" -u "$__MATH_FE_OUT" REPLY; then
            math._fe_drop; REPLY=""; return 1
        fi
    elif ! IFS= read -r -u "$__MATH_FE_OUT" REPLY; then
        math._fe_drop; REPLY=""; return 1
    fi
    case $REPLY in
        ""|ERR)          REPLY=""; return 1 ;;
        *[!0-9.eE+-]*)   math._fe_norm ;;
    esac
    return 0
}

# Stop the co-process (it also dies with the shell).
math._fe_stop() {
    math._fe_drop
    math._fe_cleanup
    return 0
}

# ---- Tier-B call shims -----------------------------------------------------
# Validate, call, answer. One shim per arity keeps the 90 Tier-B bodies to one
# line each and makes "every argument is validated" a property of four
# functions instead of ninety.

# math._fe1 OP A
math._fe1() {
    math._is_num "${2:-}" || { RESULT=""; return 1; }
    math._fe "$1" "$__m_num" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}

# math._fe2 OP A B
math._fe2() {
    local __m_a
    math._is_num "${2:-}" || { RESULT=""; return 1; }; __m_a="$__m_num"
    math._is_num "${3:-}" || { RESULT=""; return 1; }
    math._fe "$1" "$__m_a" "$__m_num" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}

# math._feN OP ARG... — the statistics family (the array IS the argument list).
math._feN() {
    local __m_op="$1" __m_x; shift
    local -a __m_args=()
    for __m_x in "$@"; do
        math._is_num "$__m_x" || { RESULT=""; return 1; }
        __m_args+=("$__m_num")
    done
    math._fe "$__m_op" "${__m_args[@]}" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}

# math._feFin OP A B C D [PTYPE] — the annuity family: four numbers plus the
# 0/1 TPaymentTime flag.
math._feFin() {
    local __m_op="$1" __m_x; shift
    local -a __m_args=()
    local __m_i
    for __m_i in 1 2 3 4; do
        math._is_num "${!__m_i:-}" || { RESULT=""; return 1; }
        __m_args+=("$__m_num")
    done
    local __m_pt="${5:-0}"
    [[ "$__m_pt" == 0 || "$__m_pt" == 1 ]] || { RESULT=""; return 1; }
    math._fe "$__m_op" "${__m_args[@]}" "$__m_pt" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}

# ===========================================================================
# Public method bodies. All are `static proc`s on the D3 return contract:
# RESULT + silence, print once under $( ), rc 1 + RESULT='' on error.
# ===========================================================================

# ---- constant getters ------------------------------------------------------
math.pi()          { math._ret "$__MATH_PI"; }
math.e()           { math._ret "$__MATH_E"; }
math.infinity()    { math._ret "$__MATH_INFINITY"; }
math.negInfinity() { math._ret "$__MATH_NEG_INFINITY"; }
math.nan()         { math._ret "$__MATH_NAN"; }
math.minSingle()   { math._ret "$__MATH_MIN_SINGLE"; }
math.maxSingle()   { math._ret "$__MATH_MAX_SINGLE"; }
math.minDouble()   { math._ret "$__MATH_MIN_DOUBLE"; }
math.maxDouble()   { math._ret "$__MATH_MAX_DOUBLE"; }
math.minExtended() { math._ret "$__MATH_MIN_EXTENDED"; }
math.maxExtended() { math._ret "$__MATH_MAX_EXTENDED"; }

# ---- float-engine lifecycle (kcl extension) --------------------------------
# feStart: start the shared engine now (opt-in for persistence across $()).
#          rc 0 if the engine is up, 1 if no awk is available. No value.
math.feStart() { math._fe_start; }
# feStop: shut the engine down and remove anything it left on disk. rc 0.
math.feStop()  { math._fe_stop; }
# feActive: is the engine running? rc (R8) + true/false in RESULT.
math.feActive() {
    if [[ -n "$__MATH_FE_UP" ]] && kill -0 "$__MATH_FE_PID" 2>/dev/null; then
        math._retBool 0
    else
        math._retBool 1
    fi
}

# ===========================================================================
# P1 — integer/decimal core.
# Tier A (pure-bash, zero-fork) for comparison-based ops on plain numbers;
# the engine handles only float-epsilon predicates (isZero/sameValue), the
# CompareValue tolerance form, and exotic-notation operands (via _num_cmp).
# REPLY == 2 from _num_cmp means UNORDERED (NaN); each member below follows
# what FPC's `<` / `>` chain does in that case — see math._num_cmp.
# ===========================================================================

# Min/Max of two operands. FPC math.pp:2033 `if a>b then a else b`
# (ties and unordered pairs -> the SECOND operand).
math.min() {
    math._num_cmp "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( REPLY == -1 )); then math._ret "$1"; else math._ret "$2"; fi
}
math.max() {
    math._num_cmp "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( REPLY == 1 )); then math._ret "$1"; else math._ret "$2"; fi
}

# Min/Max over the argument list (returns the winning argument verbatim).
math.minValue() {
    local __m_best="${1:-}" __m_x
    (( $# > 0 )) || { RESULT=""; return 1; }
    shift
    for __m_x in "$@"; do
        math._num_cmp "$__m_x" "$__m_best" || { RESULT=""; return 1; }
        if (( REPLY == -1 )); then __m_best="$__m_x"; fi
    done
    math._num_cmp "$__m_best" "$__m_best" || { RESULT=""; return 1; }
    math._ret "$__m_best"
}
math.maxValue() {
    local __m_best="${1:-}" __m_x
    (( $# > 0 )) || { RESULT=""; return 1; }
    shift
    for __m_x in "$@"; do
        math._num_cmp "$__m_x" "$__m_best" || { RESULT=""; return 1; }
        if (( REPLY == 1 )); then __m_best="$__m_x"; fi
    done
    math._num_cmp "$__m_best" "$__m_best" || { RESULT=""; return 1; }
    math._ret "$__m_best"
}

# Integer-array reducers (pure integer arithmetic).
math.minIntValue() {
    local __m_best __m_x
    kk.isInt "${1:-}" __m_best || { RESULT=""; return 1; }
    shift
    for __m_x in "$@"; do
        kk.isInt "$__m_x" __m_x || { RESULT=""; return 1; }
        if (( __m_x < __m_best )); then __m_best=$__m_x; fi
    done
    math._ret "$__m_best"
}
math.maxIntValue() {
    local __m_best __m_x
    kk.isInt "${1:-}" __m_best || { RESULT=""; return 1; }
    shift
    for __m_x in "$@"; do
        kk.isInt "$__m_x" __m_x || { RESULT=""; return 1; }
        if (( __m_x > __m_best )); then __m_best=$__m_x; fi
    done
    math._ret "$__m_best"
}

# Sign: -1 / 0 / 1 (TValueSign). FPC math.pp:729 `ord(v>0)-ord(v<0)`, so an
# unordered (NaN) operand is 0.
math.sign() {
    math._num_cmp "${1:-}" 0 || { RESULT=""; return 1; }
    if (( REPLY == 2 )); then math._ret 0; else math._ret "$REPLY"; fi
}

# InRange: FPC math.pp:2157 `(v>=min) and (v<=max)` — false for NaN. R8.
math.inRange() {
    math._num_cmp "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( REPLY == -1 || REPLY == 2 )); then math._retBool 1; return $?; fi
    math._num_cmp "${1:-}" "${3:-}" || { RESULT=""; return 1; }
    if (( REPLY == 1 || REPLY == 2 )); then math._retBool 1; else math._retBool 0; fi
}

# EnsureRange: FPC math.pp:2185 — clamp with `<` and `>` only, so NaN passes
# through untouched.
math.ensureRange() {
    math._num_cmp "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( REPLY == -1 )); then math._ret "$2"; return 0; fi
    math._num_cmp "${1:-}" "${3:-}" || { RESULT=""; return 1; }
    if (( REPLY == 1 )); then math._ret "$3"; else math._ret "$1"; fi
}

# CompareValue: FPC math.pp:2576 — GreaterThanValue unless |a-b| <= delta
# (EqualsValue) or a < b (LessThanValue). An unordered pair is therefore 1.
math.compareValue() {
    local __m_d="${3:-}"          # X-SETU (D7): the tolerance is optional
    if [[ -n $__m_d && ! $__m_d =~ ^[+-]?0*[.]?0*$ ]]; then
        local __m_a __m_b
        math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_a="$__m_num"
        math._is_num "${2:-}" || { RESULT=""; return 1; }; __m_b="$__m_num"
        math._is_num "$__m_d" || { RESULT=""; return 1; }
        math._fe cmpd "$__m_a" "$__m_b" "$__m_num" || { RESULT=""; return 1; }
        math._ret "$REPLY"
        return $?
    fi
    math._num_cmp "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( REPLY == 2 )); then math._ret 1; else math._ret "$REPLY"; fi
}

# IfThen: ternary. cond is true/1 => iftrue, else iffalse (default 0).
# `${3-0}` and not `${3:-0}` (M12): an EXPLICIT empty third argument is a
# value the caller chose, not an absent argument.
math.ifThen() {
    if [[ "${1:-}" == true || "${1:-}" == 1 ]]; then
        math._ret "${2:-}"
    else
        math._ret "${3-0}"
    fi
}

# IsZero: |value| <= epsilon (default 1e-12, the FPC Double resolution).
# FPC math.pp:2222 `Abs(A) <= Epsilon` — false for NaN. R8.
math.isZero() {
    if [[ -z "${2:-}" ]] && math._is_int "${1:-}"; then
        case "$1" in
            0|-0|+0) math._retBool 0; return $? ;;
            *)       math._retBool 1; return $? ;;
        esac
    fi
    local __m_a __m_e=0
    math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_a="$__m_num"
    if [[ -n "${2:-}" ]]; then
        math._is_num "$2" || { RESULT=""; return 1; }
        __m_e="$__m_num"
    fi
    math._fe iszero "$__m_a" "$__m_e" || { RESULT=""; return 1; }
    if [[ "$REPLY" == true ]]; then math._retBool 0; else math._retBool 1; fi
}

# SameValue: FPC math.pp:2382 — epsilon defaults to
# Max(Min(|a|,|b|)*1e-12, 1e-12); the comparison is one-sided, so NaN is
# false. Float-tolerance predicate -> engine. R8.
math.sameValue() {
    local __m_a __m_b __m_e=0
    math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_a="$__m_num"
    math._is_num "${2:-}" || { RESULT=""; return 1; }; __m_b="$__m_num"
    if [[ -n "${3:-}" ]]; then
        math._is_num "$3" || { RESULT=""; return 1; }
        __m_e="$__m_num"
    fi
    math._fe samev "$__m_a" "$__m_b" "$__m_e" || { RESULT=""; return 1; }
    if [[ "$REPLY" == true ]]; then math._retBool 0; else math._retBool 1; fi
}

# ===========================================================================
# P2 — rounding & number conversion.
# Tier A (pure-bash, zero-fork): ceil/ceil64/floor/floor64, divMod, and integer
# intPower. Tier B (engine, exact FPC-Double parity): roundTo (banker's),
# simpleRoundTo (arithmetic), fmod, and float/negative-exponent intPower.
# ===========================================================================

# Ceil: round toward +inf. FPC math.pp:1077 Trunc(x)+ord(Frac(x)>0).
math.ceil() {
    local __m_t __m_dec=1
    case ${1:-} in ""|*[!0-9.+-]*) __m_dec=0 ;;
                   *) case ${1#[-+]} in ""|.|*[-+]*|*.*.*) __m_dec=0 ;; esac ;; esac
    if (( __m_dec )); then
        math._trunc "$1"; __m_t=$REPLY
        math._frac "$1"
        if [[ $REPLY != 0 && $REPLY != -* ]]; then __m_t=$(( __m_t + 1 )); fi
        math._ret "$__m_t"
        return 0
    fi
    math._is_num "${1:-}" || { RESULT=""; return 1; }
    math._fe ceil "$__m_num" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}
math.ceil64() { math.ceil "${1:-}"; }

# Floor: round toward -inf. FPC math.pp:1089 Trunc(x)-ord(Frac(x)<0).
math.floor() {
    local __m_t __m_dec=1
    case ${1:-} in ""|*[!0-9.+-]*) __m_dec=0 ;;
                   *) case ${1#[-+]} in ""|.|*[-+]*|*.*.*) __m_dec=0 ;; esac ;; esac
    if (( __m_dec )); then
        math._trunc "$1"; __m_t=$REPLY
        math._frac "$1"
        if [[ $REPLY == -* ]]; then __m_t=$(( __m_t - 1 )); fi
        math._ret "$__m_t"
        return 0
    fi
    math._is_num "${1:-}" || { RESULT=""; return 1; }
    math._fe floor "$__m_num" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}
math.floor64() { math.floor "${1:-}"; }

# DivMod: integer division + remainder. FPC math.pp:2463 negates BOTH result
# and remainder for a negative dividend, i.e. truncation toward zero with the
# remainder taking the dividend's sign — exactly bash `/` and `%`.
# Returns "quot rem"; division by zero is rc 1 (FPC raises EDivByZero).
math.divMod() {
    local __m_a __m_b
    kk.isInt "${1:-}" __m_a || { RESULT=""; return 1; }
    kk.isInt "${2:-}" __m_b || { RESULT=""; return 1; }
    if (( __m_b == 0 )); then RESULT=""; return 1; fi
    math._ret "$(( __m_a / __m_b )) $(( __m_a % __m_b ))"
}

# RoundTo: FPC math.pp:2606 `RV := IntPower(10,Digits); Round(AValue/RV)*RV`.
# Round is half-to-even, and so is awk's sprintf("%.0f") -> exact parity.
math.roundTo() {
    local __m_v
    math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_v="$__m_num"
    kk.isInt "${2:-}" || { RESULT=""; return 1; }
    math._fe roundto "$__m_v" "$__KK_INT" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}

# SimpleRoundTo: Int(value*RV +/- 0.5)/RV, RV=10^(-digits) — arithmetic
# rounding (half away from zero). Default digits = -2. Engine.
math.simpleRoundTo() {
    local __m_v
    math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_v="$__m_num"
    if [[ -n "${2:-}" ]]; then
        kk.isInt "$2" || { RESULT=""; return 1; }
        math._fe sround "$__m_v" "$__KK_INT" || { RESULT=""; return 1; }
    else
        math._fe sround "$__m_v" || { RESULT=""; return 1; }
    fi
    math._ret "$REPLY"
}

# FMod: floating-point modulo, a - b*Int(a/b). A zero divisor is nan (IEEE);
# FPC with its default unmasked FPU exceptions raises EZeroDivide instead.
math.fmod() { math._fe2 fmod "${1:-}" "${2:-}"; }

# IntPower: base^exponent (integer exponent). FPC math.pp:1044 returns a
# FLOAT, so the exact integer path here is an optimisation, not the semantics:
# once the result leaves int64 the engine answers the Double (M8).
math.intPower() {
    local __m_b="${1:-}" __m_e="${2:-}" __m_ip __m_fast=1
    # Fast path: a plain 18-digit-or-less base and a small non-negative
    # exponent. The two case tests validate AND are ~20 us cheaper than two
    # kk.isInt calls, which matters because intPower is a Tier-A hot path.
    # 18 digits is the widest that cannot overflow int64 on the way IN; the
    # overflow of the RESULT is what math._ipow_i reports.
    local __m_bs="${__m_b#[-+]}"
    case $__m_bs in ""|*[!0-9]*) __m_fast=0 ;; esac
    case $__m_e  in ""|*[!0-9]*) __m_fast=0 ;; esac
    if (( __m_fast )) && (( ${#__m_bs} <= 18 && ${#__m_e} <= 3 )); then
        local __m_bi=$(( ${__m_b%%[0-9]*}10#$__m_bs )) __m_ei=$(( 10#$__m_e ))
        # |b| < 10^len, so |b|^e < 10^(len*e): when len*e <= 18 the result
        # cannot leave int64 and bash's own `**` is the cheapest exact answer.
        if (( ${#__m_bs} * __m_ei <= 18 )); then
            math._ret "$(( __m_bi ** __m_ei ))"
            return 0
        fi
        if math._ipow_i "$__m_bi" "$__m_ei"; then
            math._ret "$__m_ip"
            return 0
        fi
    fi
    local __m_x
    math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_x="$__m_num"
    kk.isInt "${2:-}" || { RESULT=""; return 1; }
    math._fe ipow "$__m_x" "$__KK_INT" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}

# ===========================================================================
# P3 — angle conversions (engine; pi is irrational and FPC returns Double).
# 1 cycle = 360 deg = 400 grad = 2pi rad.
# ===========================================================================
math.degToRad()    { math._fe1 d2r "${1:-}"; }
math.radToDeg()    { math._fe1 r2d "${1:-}"; }
math.gradToRad()   { math._fe1 g2r "${1:-}"; }
math.radToGrad()   { math._fe1 r2g "${1:-}"; }
math.degToGrad()   { math._fe1 d2g "${1:-}"; }
math.gradToDeg()   { math._fe1 g2d "${1:-}"; }
math.cycleToDeg()  { math._fe1 c2d "${1:-}"; }
math.degToCycle()  { math._fe1 d2c "${1:-}"; }
math.cycleToGrad() { math._fe1 c2g "${1:-}"; }
math.gradToCycle() { math._fe1 g2c "${1:-}"; }
math.cycleToRad()  { math._fe1 c2r "${1:-}"; }
math.radToCycle()  { math._fe1 r2c "${1:-}"; }
# DegNormalize: wrap degrees into [0,360). Deg - Int(Deg/360)*360, +360 if <0.
math.degNormalize() { math._fe1 dnorm "${1:-}"; }

# ===========================================================================
# P4 — trig, inverse trig, hyperbolic, area (all engine).
# sin/cos/arcTan are System-unit elementaries (not in math.pp) exposed for
# convenience. ArcSin/ArcCos use FPC's numerically-stable sqrt((1-x)(1+x))
# form (math.pp:900); tanh is FPC's robust large-x formula; ArcSinH preserves
# sign. Cotan/Sec/Csc divide by sin/cos, so their poles answer +-inf (R11)
# where FPC raises EZeroDivide.
# ===========================================================================
math.sin()      { math._fe1 sin "${1:-}"; }
math.cos()      { math._fe1 cos "${1:-}"; }
math.tan()      { math._fe1 tan "${1:-}"; }
math.cotan()    { math._fe1 cotan "${1:-}"; }
math.cot()      { math._fe1 cotan "${1:-}"; }
math.sinCos()   { math._fe1 sincos "${1:-}"; }   # returns "sin cos"
math.secant()   { math._fe1 sec "${1:-}"; }
math.cosecant() { math._fe1 csc "${1:-}"; }
math.sec()      { math._fe1 sec "${1:-}"; }
math.csc()      { math._fe1 csc "${1:-}"; }
math.arcSin()   { math._fe1 asin "${1:-}"; }
math.arcCos()   { math._fe1 acos "${1:-}"; }
math.arcTan()   { math._fe1 atan "${1:-}"; }
math.arcTan2()  { math._fe2 atan2 "${1:-}" "${2:-}"; }
math.cosh()     { math._fe1 cosh "${1:-}"; }
math.sinh()     { math._fe1 sinh "${1:-}"; }
math.tanh()     { math._fe1 tanh "${1:-}"; }
math.secH()     { math._fe1 sech "${1:-}"; }
math.cscH()     { math._fe1 csch "${1:-}"; }
math.cotH()     { math._fe1 coth "${1:-}"; }
math.arcCosH()  { math._fe1 arcosh "${1:-}"; }
math.arcSinH()  { math._fe1 arsinh "${1:-}"; }
math.arcTanH()  { math._fe1 artanh "${1:-}"; }
math.arCosH()   { math._fe1 arcosh "${1:-}"; }
math.arSinH()   { math._fe1 arsinh "${1:-}"; }
math.arTanH()   { math._fe1 artanh "${1:-}"; }
math.arcSec()   { math._fe1 arcsec "${1:-}"; }
math.arcCsc()   { math._fe1 arccsc "${1:-}"; }
math.arcCot()   { math._fe1 arccot "${1:-}"; }
math.arcSecH()  { math._fe1 arcsech "${1:-}"; }
math.arcCscH()  { math._fe1 arccsch "${1:-}"; }
math.arcCotH()  { math._fe1 arccoth "${1:-}"; }

# ===========================================================================
# P5 — logarithms, exponentials, powers, misc (engine; integer ** via P2
# intPower). sqrt/exp/ln are System-unit elementaries.
# ===========================================================================
math.log10() { math._fe1 log10 "${1:-}"; }
math.log2()  { math._fe1 log2 "${1:-}"; }
math.logN()  { math._fe2 logn "${1:-}" "${2:-}"; }   # logN base value
math.lnXP1() { math._fe1 lnxp1 "${1:-}"; }           # ln(1+x), accurate near 0
math.expM1() { math._fe1 expm1 "${1:-}"; }           # exp(x)-1, accurate near 0
math.power() { math._fe2 power "${1:-}" "${2:-}"; }
math.hypot() { math._fe2 hypot "${1:-}" "${2:-}"; }
# Frexp: FPC math.pp:1118 halves/doubles X until |X| is in [0.5,1). That loop
# never terminates for +-inf, so this port takes the C `frexp` answer for the
# non-finite cases instead: the value itself with exponent 0 (M2).
math.frexp() { math._fe1 frexp "${1:-}"; }           # returns "mantissa exponent"
math.ldexp() {                                        # x * 2^p, p an integer
    local __m_x
    math._is_num "${1:-}" || { RESULT=""; return 1; }; __m_x="$__m_num"
    kk.isInt "${2:-}" || { RESULT=""; return 1; }
    math._fe ldexp "$__m_x" "$__KK_INT" || { RESULT=""; return 1; }
    math._ret "$REPLY"
}
math.sqrt()  { math._fe1 sqrt "${1:-}"; }
math.exp()   { math._fe1 exp "${1:-}"; }
math.ln()    { math._fe1 ln "${1:-}"; }

# ===========================================================================
# P6 — statistics. Arrays are passed as the argument list; the engine computes
# each statistic in one awk pass. sumInt is pure-bash integer (zero-fork).
# Sample Variance/StdDev use N-1; PopnVariance/PopnStdDev use N. An EMPTY
# argument list divides by zero in FPC (math.pp:1249 `mean := sum/N`); here it
# answers nan, except sum/sumOfSquares/norm, which are 0 over an empty set.
# ===========================================================================
math.sum()            { math._feN asum "$@"; }
math.mean()           { math._feN amean "$@"; }
math.sumOfSquares()   { math._feN asumsq "$@"; }
math.sumsAndSquares() { math._feN asumsandsq "$@"; }   # "sum sumOfSquares"
math.variance()       { math._feN avariance "$@"; }    # sample (N-1)
math.totalVariance()  { math._feN atotvar "$@"; }      # Sum((x-mean)^2)
math.popnVariance()   { math._feN apopnvar "$@"; }     # population (N)
math.stdDev()         { math._feN astddev "$@"; }
math.popnStdDev()     { math._feN apopnstddev "$@"; }
math.meanAndStdDev()  { math._feN ameanstddev "$@"; }  # "mean stddev"
math.momentSkewKurtosis() { math._feN amoments "$@"; } # "m1 m2 m3 m4 skew kurt"
math.norm()           { math._feN anorm "$@"; }        # euclidean L2
math.randG()          { math._fe2 randg "${1:-}" "${2:-}"; }  # gaussian(mean,sd)

# SumInt: FPC math.pp:1224 accumulates in Int64 and wraps. bash's $(( )) is
# intmax_t and wraps identically, but a wrapped total is indistinguishable
# from a real one, so P7/M8 routes an overflow to the engine and answers the
# Double (a deliberate divergence, README "Differences from FPC").
math.sumInt() {
    local __m_s=0 __m_x __m_t
    for __m_x in "$@"; do
        kk.isInt "$__m_x" __m_x || { RESULT=""; return 1; }
        __m_t=$(( __m_s + __m_x ))
        if (( (__m_s > 0 && __m_x > 0 && __m_t < 0) || (__m_s < 0 && __m_x < 0 && __m_t >= 0) )); then
            math._feN asum "$@"
            return $?
        fi
        __m_s=$__m_t
    done
    math._ret "$__m_s"
}

# ===========================================================================
# P7 — financial (annuity), RNG, IEEE predicates, FPU stubs.
# Financial: engine. APaymentTime is a 0/1 flag (0=ptEndOfPeriod default,
# 1=ptStartOfPeriod). RNG + predicates are pure-bash (zero-fork).
# ===========================================================================
math.futureValue()     { math._feFin fv "$@"; }     # rate n payment presentValue [ptype]
math.presentValue()    { math._feFin pv "$@"; }     # rate n payment futureValue [ptype]
math.payment()         { math._feFin pmt "$@"; }    # rate n presentValue futureValue [ptype]
math.interestRate()    { math._feFin irate "$@"; }  # nPeriods payment pv fv [ptype]
math.numberOfPeriods() { math._feFin nper "$@"; }   # rate payment pv fv [ptype]

# RandomRange: FPC math.pp:1405 `Random(Abs(aFrom-aTo)) + Min(aTo,aFrom)` —
# upper-exclusive. Pure bash, zero fork.
# M13: the old body drew 30 bits from two $RANDOM and took `% n`, so the top of
# any range wider than 2^30 was UNREACHABLE and every non-power-of-two range
# was biased. Now: 63 bits from five $RANDOM, masked down to the next power of
# two and REJECTION-SAMPLED, which is exactly uniform.
math.randomRange() {
    local __m_from __m_to __m_lo __m_hi __m_n __m_m __m_r
    kk.isInt "${1:-}" __m_from || { RESULT=""; return 1; }
    kk.isInt "${2:-}" __m_to   || { RESULT=""; return 1; }
    if (( __m_from < __m_to )); then __m_lo=$__m_from; __m_hi=$__m_to
    else                             __m_lo=$__m_to;   __m_hi=$__m_from; fi
    __m_n=$(( __m_hi - __m_lo ))
    # FPC computes the span in Int64 too and wraps for a span wider than
    # Int64; a wrapped span is not a range, so it is rc 1 here.
    if (( __m_n < 0 )); then RESULT=""; return 1; fi
    if (( __m_n == 0 )); then math._ret "$__m_lo"; return 0; fi
    (( __m_m = __m_n - 1,
       __m_m |= __m_m >> 1,  __m_m |= __m_m >> 2,  __m_m |= __m_m >> 4,
       __m_m |= __m_m >> 8,  __m_m |= __m_m >> 16, __m_m |= __m_m >> 32 )) || :
    while (( (__m_r = (((RANDOM & 7) << 60) | (RANDOM << 45) | (RANDOM << 30) \
                       | (RANDOM << 15) | RANDOM) & __m_m) >= __m_n )); do :; done
    math._ret "$(( __m_lo + __m_r ))"
}

# RandomFrom: a uniformly random element of the argument list. Zero-fork.
math.randomFrom() {
    local -a __m_vals=("$@")
    local __m_n=${#__m_vals[@]} __m_m __m_r
    if (( __m_n == 0 )); then RESULT=""; return 1; fi
    (( __m_m = __m_n - 1,
       __m_m |= __m_m >> 1,  __m_m |= __m_m >> 2,  __m_m |= __m_m >> 4,
       __m_m |= __m_m >> 8,  __m_m |= __m_m >> 16, __m_m |= __m_m >> 32 )) || :
    while (( (__m_r = (((RANDOM & 7) << 60) | (RANDOM << 45) | (RANDOM << 30) \
                       | (RANDOM << 15) | RANDOM) & __m_m) >= __m_n )); do :; done
    math._ret "${__m_vals[__m_r]}"
}

# IsNan / IsInfinite: test for the nan / +-inf tokens the engine emits, in
# every spelling it or a caller may use. Pure-bash predicates (R8).
math.isNan() {
    local __m_re='^[+-]?([nN][aA][nN])$'
    if [[ "${1:-}" =~ $__m_re ]]; then math._retBool 0; else math._retBool 1; fi
}
math.isInfinite() {
    local __m_re='^[+-]?([iI][nN][fF]|[iI][nN][fF][iI][nN][iI][tT][yY])$'
    if [[ "${1:-}" =~ $__m_re ]]; then math._retBool 0; else math._retBool 1; fi
}

# FPU control — WONTFIX: bash has no FPU control word. Getters report the
# conventional default (informational only); setters are rc 1;
# clearExceptions is a no-op (there are no pending FPU exceptions in bash).
math.getRoundMode()     { math._ret "rmNearest"; }
math.setRoundMode()     { math._err; }
math.getPrecisionMode() { math._ret "pmDouble"; }
math.setPrecisionMode() { math._err; }
math.getExceptionMask() { math._ret "[exInvalidOp,exDenormalized,exZeroDivide,exOverflow,exUnderflow,exPrecision]"; }
math.setExceptionMask() { math._err; }
math.clearExceptions()  { math._ret ""; }

build math
