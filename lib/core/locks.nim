#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains Nim's support for locks and condition vars.

#[
for js, for now we treat locks as noop's to avoid pushing `when defined(js)`
in client code that uses locks.
]#

when not compileOption("threads") and not defined(nimdoc):
  when false: # fix #12330
    {.error: "Locks requires --threads:on option.".}

const insideRLocksModule = false
include "system/syslocks"

type
  Lock* = SysLock ## Nim lock; whether this is re-entrant
                  ## or not is unspecified!
  Cond* = SysCond ## Nim condition variable

{.push stackTrace: off.}

proc initLock*(lock: var Lock) {.inline.} =
  ## Initializes the given lock.
  when not defined(js):
    initSysLock(lock)

proc deinitLock*(lock: var Lock) {.inline.} =
  ## Frees the resources associated with the lock.
  deinitSys(lock)

proc tryAcquire*(lock: var Lock): bool =
  ## Tries to acquire the given lock. Returns `true` on success.
  result = tryAcquireSys(lock)

proc acquire*(lock: var Lock) =
  ## Acquires the given lock.
  when not defined(js):
    acquireSys(lock)

proc release*(lock: var Lock) =
  ## Releases the given lock.
  when not defined(js):
    releaseSys(lock)


proc initCond*(cond: var Cond) {.inline.} =
  ## Initializes the given condition variable.
  initSysCond(cond)

proc deinitCond*(cond: var Cond) {.inline.} =
  ## Frees the resources associated with the condition variable.
  deinitSysCond(cond)

proc wait*(cond: var Cond, lock: var Lock) {.inline.} =
  ## Waits on the condition variable `cond`.
  waitSysCond(cond, lock)

proc signal*(cond: var Cond) {.inline.} =
  ## Sends a signal to the condition variable `cond`.
  signalSysCond(cond)

proc broadcast*(cond: var Cond) {.inline.} =
  ## Unblocks all threads currently blocked on the
  ## specified condition variable `cond`.
  broadcastSysCond(cond)

template withLock*(a: Lock, body: untyped) =
  ## Acquires the given lock, executes the statements in body and
  ## releases the lock after the statements finish executing.
  mixin acquire, release
  acquire(a)
  {.locks: [a].}:
    try:
      body
    finally:
      release(a)

{.pop.}
