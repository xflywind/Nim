import std/os

runnableExamples:
  doAssert urandom(0).len == 0
  doAssert urandom(10).len == 10
  doAssert urandom(20).len == 20
  doAssert urandom(120).len == 120


when defined(posix):
  import std/posix

  template processReadBytes(readBytes: int, p: pointer) =
    if readBytes == 0:
      break
    elif readBytes > 0:
      inc(result, readBytes)
      cast[ptr pointer](p)[] = cast[pointer](cast[ByteAddress](p) + readBytes)
    else:
      if osLastError().int in {EINTR, EAGAIN}:
        discard
      else:
        result = -1
        break

  proc getDevUrandom(p: pointer, size: int): int =
    let fd = posix.open("/dev/urandom", O_RDONLY)

    if fd > 0:
      var stat: Stat
      if fstat(fd, stat) != -1 and S_ISCHR(stat.st_mode):
        while result < size:
          let readBytes = posix.read(fd, p, size - result)
          processReadBytes(readBytes, p)

      discard posix.close(fd)

when defined(windows):
  import std/winlean

  type
    PVOID = pointer
    BCRYPT_ALG_HANDLE = PVOID
    PUCHAR = ptr cuchar
    NTSTATUS = clong

  const
    STATUS_SUCCESS = 0x00000000
    BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x00000002

  proc bCryptGenRandom(
    hAlgorithm: BCRYPT_ALG_HANDLE,
    pbBuffer: PUCHAR,
    cbBuffer: ULONG,
    dwFlags: ULONG
  ): NTSTATUS {.stdcall, importc: "BCryptGenRandom", dynlib: "Bcrypt.dll".}


  proc randomBytes(pbBuffer: pointer, cbBuffer: int): int =
    bCryptGenRandom(nil, cast[PUCHAR](pbBuffer), ULONG(cbBuffer),
                            BCRYPT_USE_SYSTEM_PREFERRED_RNG)

  proc urandom*[T: byte | char](p: var openArray[T]): int =
    let size = p.len
    if size > 0:
      result = randomBytes(addr p[0], size)

  proc urandom*(size: Natural): string =
    result = newString(size)
    if urandom(result) != STATUS_SUCCESS:
      raiseOsError(osLastError())

elif defined(linux):
  let SYS_getrandom {.importc: "SYS_getrandom", header: "<syscall.h>".}: clong

  proc syscall(n: clong, buf: pointer, bufLen: cint, flags: cuint): int {.importc: "syscall", header: "syscall.h".}

  proc randomBytes(p: pointer, size: int): int =
    while result < size:
      let readBytes = syscall(SYS_getrandom, p, cint(size - result), 0)
      processReadBytes(readBytes, p)

  proc urandom*[T: byte | char](p: var openArray[T]): int =
    let size = p.len
    if size > 0:
      result = randomBytes(p, size)
      if result < 0:
        result = getDevUrandom(p, size)

  proc urandom*(size: Natural): string =
    result = newString(size)
    if urandom(result) < 0:
      raiseOsError(osLastError())

else:
  proc urandom*[T: byte | char](p: var openArray[T]): int =
    let size = p.len
    if size > 0:
      result = getDevUrandom(addr p[0], size)

  proc urandom*(size: Natural): string =
    result = newString(size)
    if urandom(result) < 0:
      raiseOsError(osLastError())