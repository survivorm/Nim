#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Thread var support for crappy architectures that lack native support for
## thread local storage. (**Thank you Mac OS X!**)

# included from cgen.nim

proc emulatedThreadVars(conf: ConfigRef): bool =
  result = {optThreads, optTlsEmulation} <= conf.globalOptions

proc accessThreadLocalVar(p: BProc, s: PSym) =
  if emulatedThreadVars(p.config) and not p.threadVarAccessed:
    p.threadVarAccessed = true
    incl p.module.flags, usesThreadVars
    addf(p.procSec(cpsLocals), "\tNimThreadVars* NimTV_;$n", [])
    add(p.procSec(cpsInit),
      ropecg(p.module, "\tNimTV_ = (NimThreadVars*) #GetThreadLocalVars();$n"))

var
  nimtv: Rope                 # Nim thread vars; the struct body
  nimtvDeps: seq[PType] = @[]  # type deps: every module needs whole struct
  nimtvDeclared = initIntSet() # so that every var/field exists only once
                               # in the struct

# 'nimtv' is incredibly hard to modularize! Best effort is to store all thread
# vars in a ROD section and with their type deps and load them
# unconditionally...

# nimtvDeps is VERY hard to cache because it's not a list of IDs nor can it be
# made to be one.

proc declareThreadVar(m: BModule, s: PSym, isExtern: bool) =
  if emulatedThreadVars(m.config):
    # we gather all thread locals var into a struct; we need to allocate
    # storage for that somehow, can't use the thread local storage
    # allocator for it :-(
    if not containsOrIncl(nimtvDeclared, s.id):
      nimtvDeps.add(s.loc.t)
      addf(nimtv, "$1 $2;$n", [getTypeDesc(m, s.loc.t), s.loc.r])
  else:
    if isExtern: add(m.s[cfsVars], "extern ")
    if optThreads in m.config.globalOptions: add(m.s[cfsVars], "NIM_THREADVAR ")
    add(m.s[cfsVars], getTypeDesc(m, s.loc.t))
    addf(m.s[cfsVars], " $1;$n", [s.loc.r])

proc generateThreadLocalStorage(m: BModule) =
  if nimtv != nil and (usesThreadVars in m.flags or sfMainModule in m.module.flags):
    for t in items(nimtvDeps): discard getTypeDesc(m, t)
    addf(m.s[cfsSeqTypes], "typedef struct {$1} NimThreadVars;$n", [nimtv])

proc generateThreadVarsSize(m: BModule) =
  if nimtv != nil:
    let externc = if m.config.cmd == cmdCompileToCpp or
                       sfCompileToCpp in m.module.flags: "extern \"C\" "
                  else: ""
    addf(m.s[cfsProcs],
      "$#NI NimThreadVarsSize(){return (NI)sizeof(NimThreadVars);}$n",
      [externc.rope])
