discard """
  matrix: "--threads:on --gc:refc; --threads:on --gc:orc"
"""

import std/mutexes

type
  PassObj = object
    id: int
    m: Mutex

  Pass = ptr PassObj

block:
  proc worker(p: Pass) {.thread.} =
    acquire(p.m)
    inc p.id
    release(p.m)

  var p = PassObj()
  init(p.m)
  var ts = newSeq[Thread[Pass]](10)
  for i in 0..<ts.len:
    createThread(ts[i], worker, addr p)

  joinThreads(ts)
  doAssert p.id == 10
  echo p.id