import std/[macros]


type
  Task* = object ## `Task` contains the callback and its arguments.
    callback: proc (args: pointer) {.nimcall.}
    args: pointer

proc invoke*(task: Task) {.inline.} =
  ## Invokes the `task`.
  ##
  ## .. warning:: `task` can only be used once.
  task.callback(task.args)

macro toTask*(e: typed{nkCall | nkCommand}): Task =
  ## Converts the call and its arguments to `Task`.
  runnableExamples:
    proc hello(a: int) = echo a

    let b = toTask hello(13)
    assert b is Task

  template addAllNode =
    let scratchDotExpr = newDotExpr(scratchIdent, formalParams[i][0])
    case e[i].kind
    of nnkSym:
      scratchAssignList.add newCall(newIdentNode("=sink"), scratchDotExpr, e[i])
    else:
      scratchAssignList.add newAssignment(scratchDotExpr, e[i])

    let tempNode = genSym(kind = nskTemp, ident = "")
    callNode.add nnkExprEqExpr.newTree(formalParams[i][0], tempNode)
    tempAssignList.add newLetStmt(tempNode, newCall(transferProc, newDotExpr(objTemp, formalParams[i][0])))

  doAssert getTypeInst(e).typeKind == ntyVoid

  if e.len > 1:
    let scratchIdent = genSym(kind = nskTemp, ident = "scratch")
    let impl = e[0].getTypeInst

    echo impl.treeRepr
    echo e.treeRepr
    let formalParams = impl[0]

    var
      scratchRecList = newNimNode(nnkRecList)
      scratchAssignList: seq[NimNode]
      tempAssignList: seq[NimNode]
      callNode: seq[NimNode]

    let
      objTemp = genSym(ident = "obj")
      transferProc = newIdentNode("move") # template transfer[T: not ref](x: T): T = move(x)

    for i in 1 ..< formalParams.len:
      let param = formalParams[i][1]

      case param.kind
      of nnkVarTy:
        error("'toTask'ed function cannot have a 'var' parameter")
      of nnkBracketExpr:
        if param[0].eqIdent("sink"):
          scratchRecList.add newIdentDefs(newIdentNode(formalParams[i][0].strVal), param[1])
          addAllNode()
        elif param[0].eqIdent("typeDesc"):
          callNode.add nnkExprEqExpr.newTree(formalParams[i][0], e[i])
        elif param[0].eqIdent("varargs") or param[0].eqIdent("openArray"):
          let
            seqType = nnkBracketExpr.newTree(newIdentNode("seq"), param[1])
            scratchDotExpr = newDotExpr(scratchIdent, formalParams[i][0])
            seqCallNode = newcall("@", e[i])

          case e[i].kind
          of nnkSym:
            scratchAssignList.add newCall(newIdentNode("=sink"), scratchDotExpr, seqCallNode)
          else:
            scratchAssignList.add newAssignment(scratchDotExpr, seqCallNode)

          let tempNode = genSym(kind = nskTemp)
          callNode.add nnkExprEqExpr.newTree(formalParams[i][0], tempNode)
          tempAssignList.add newLetStmt(tempNode, newCall(transferProc, newDotExpr(objTemp, formalParams[i][0])))
          scratchRecList.add newIdentDefs(newIdentNode(formalParams[i][0].strVal), seqType)
        else:
          scratchRecList.add newIdentDefs(newIdentNode(formalParams[i][0].strVal), param)
          addAllNode()
      of nnkBracket, nnkObjConstr:
        # passing by static parameters
        # so we pass them directly instead of passing by scratchObj
        callNode.add nnkExprEqExpr.newTree(formalParams[i][0], e[i])
      of nnkSym, nnkPtrTy:
        scratchRecList.add newIdentDefs(newIdentNode(formalParams[i][0].strVal), param)
        addAllNode()
      of nnkCharLit..nnkNilLit:
        # TODO params doesn't work for static string
        callNode.add nnkExprEqExpr.newTree(formalParams[i][0], e[i])
      else:
        error("not supported type kinds")

    let stmtList = newStmtList()
    let scratchObjType = genSym(kind = nskType, ident = "ScratchObj")
    let scratchObj = nnkTypeSection.newTree(
                      nnkTypeDef.newTree(
                        scratchObjType,
                        newEmptyNode(),
                        nnkObjectTy.newTree(
                          newEmptyNode(),
                          newEmptyNode(),
                          scratchRecList
                        )
                      )
                    )


    let scratchVarSection = nnkVarSection.newTree(
      nnkIdentDefs.newTree(
        scratchIdent,
        scratchObjType,
        newEmptyNode()
      )
    )

    stmtList.add(scratchObj)
    stmtList.add(scratchVarSection)
    stmtList.add(scratchAssignList)

    var functionStmtList = newStmtList()
    let funcCall = newCall(e[0], callNode)
    functionStmtList.add tempAssignList
    functionStmtList.add funcCall

    let funcName = genSym(nskProc, e[0].strVal)

    result = quote do:
      `stmtList`

      proc `funcName`(args: pointer) {.nimcall.} =
        let `objTemp` = cast[ptr `scratchObjType`](args)
        `functionStmtList`

      Task(callback: `funcName`, args: addr(`scratchIdent`))
  else:
    let funcCall = newCall(e[0])
    let funcName = genSym(nskProc, e[0].strVal)

    result = quote do:
      proc `funcName`(args: pointer) {.nimcall.} =
        `funcCall`

      Task(callback: `funcName`, args: nil)

  echo "-------------------------------------------------------------"
  echo result.repr


runnableExamples:
  var num = 0
  proc hello(a: int) = inc num, a

  let b = toTask hello(13)
  b.invoke()

  assert num == 13

when isMainModule:

  block:
    proc hello(a: int or string) =
      echo a

    let x = "!2"
    let b = toTask hello(x)
    b.invoke()

  when defined(testing):
    import std/strformat


    block:
      proc hello(typ: typedesc) =
        echo typ(12)

      let b = toTask hello(int)
      b.invoke()

    block:
      proc hello(typ: typedesc) =
        echo typ(12)

      let b = toTask hello(int)
      b.invoke()

    block:
      proc hello(a: int or seq[string]) =
        echo a

      let x = @["1", "2", "3", "4"]
      let b = toTask hello(x)
      b.invoke()

    block:
      proc hello(a: int or string) =
        echo a

      let x = "!2"
      let b = toTask hello(x)
      b.invoke()


    block:
      proc hello(a: int or string) =
        echo a

      let b = toTask hello(12)
      b.invoke()

    block:
      proc hello(c: seq[int], a: int) =
        echo a
        echo c

      let x = 12
      var y = @[1, 3, 1, 4, 5, x, 1]
      let b = toTask hello(y, 12)
      b.invoke()

    block:
      proc hello(c: seq[int], a: int) =
        echo a
        echo c

      var x = 2
      let b = toTask hello(@[1, 3, 1, 4, 5, x, 1], 12)
      b.invoke()

    block:
      proc hello(c: array[7, int], a: int) =
        echo a
        echo c

      let b = toTask hello([1, 3, 1, 4, 5, 2, 1], 12)
      b.invoke()

    block:
      proc hello(c: seq[int], a: int) =
        echo a
        echo c

      let b = toTask hello(@[1, 3, 1, 4, 5, 2, 1], 12)
      b.invoke()

    block:
      proc hello(a: int, c: seq[int]) =
        echo a
        echo c

      let b = toTask hello(8, @[1, 3, 1, 4, 5, 2, 1])
      b.invoke()

      let c = toTask 8.hello(@[1, 3, 1, 4, 5, 2, 1])
      c.invoke()


    block:
      proc hello(a: int, c: openArray[seq[int]]) =
        echo a
        echo c

      let b = toTask hello(8, @[@[3], @[4], @[5], @[6], @[12], @[7]])
      b.invoke()

    block:
      proc hello(a: int, c: openArray[int]) =
        echo a
        echo c

      let b = toTask hello(8, @[3, 4, 5, 6, 12, 7])
      b.invoke()

    block:
      proc hello(a: int, c: static varargs[int]) =
        echo a
        echo c

      let b = toTask hello(8, @[3, 4, 5, 6, 12, 7])
      b.invoke()

    block:
      proc hello(a: int, c: static varargs[int]) =
        echo a
        echo c

      let b = toTask hello(8, [3, 4, 5, 6, 12, 7])
      b.invoke()

    block:
      proc hello(a: int, c: varargs[int]) =
        echo a
        echo c

      let x = 12
      let b = toTask hello(8, 3, 4, 5, 6, x, 7)
      b.invoke()

    block:
      var x = 12

      proc hello(x: ptr int) =
        echo x[]

      let b = toTask hello(addr x)
      b.invoke()

      let c = toTask x.addr.hello
      invoke(c)
    block:
      type
        Test = ref object
          id: int
      proc hello(a: int, c: static Test) =
        echo a

      let b = toTask hello(8, Test(id: 12))
      b.invoke()

    block:
      type
        Test = object
          id: int
      proc hello(a: int, c: static Test) =
        echo a

      let b = toTask hello(8, Test(id: 12))
      b.invoke()

    block:
      proc hello(a: int, c: static seq[int]) =
        echo a

      let b = toTask hello(8, @[3, 4, 5, 6, 12, 7])
      b.invoke()

    block:
      proc hello(a: int, c: static array[5, int]) =
        echo a

      let b = toTask hello(8, [3, 4, 5, 6, 12])
      b.invoke()

    block:
      var aVal = 0
      var cVal = ""

      proc hello(a: int, c: static string) =
        aVal += a
        cVal.add c

      var x = 1314
      let b = toTask hello(x, "hello")
      b.invoke()

      doAssert aVal == x
      doAssert cVal == "hello"

    block:
      var aVal = ""

      proc hello(a: static string) =
        aVal.add a
      let b = toTask hello("hello")
      b.invoke()

      doAssert aVal == "hello"

    block:
      var aVal = 0
      var cVal = ""

      proc hello(a: static int, c: static string) =
        aVal += a
        cVal.add c
      let b = toTask hello(8, "hello")
      b.invoke()

      doAssert aVal == 8
      doAssert cVal == "hello"

    block:
      var aVal = 0
      var cVal = 0

      proc hello(a: static int, c: int) =
        aVal += a
        cVal += c

      let b = toTask hello(c = 0, a = 8)
      b.invoke()

      doAssert aVal == 8
      doAssert cVal == 0

    block:
      var aVal = 0
      var cVal = 0

      proc hello(a: int, c: static int) =
        aVal += a
        cVal += c

      let b = toTask hello(c = 0, a = 8)
      b.invoke()

      doAssert aVal == 8
      doAssert cVal == 0

    block:
      var aVal = 0
      var cVal = 0

      proc hello(a: static int, c: static int) =
        aVal += a
        cVal += c

      let b = toTask hello(0, 8)
      b.invoke()

      doAssert aVal == 0
      doAssert cVal == 8

    block:
      proc hello(x: int, y: seq[string], d = 134) =
        echo fmt"{x=} {y=} {d=}"

      proc ok() =
        echo "ok"

      proc main() =
        var x = @["23456"]
        let t = toTask hello(2233, x)
        t.invoke()

      main()


    block:
      proc hello(x: int, y: seq[string], d = 134) =
        echo fmt"{x=} {y=} {d=}"

      proc ok() =
        echo "ok"

      proc main() =
        var x = @["23456"]
        let t = toTask hello(2233, x)
        t.invoke()
        t.invoke()

      main()

      var x = @["4"]
      let m = toTask hello(2233, x)
      m.invoke()

      let n = toTask ok()
      n.invoke()

    block:
      var called = 0
      block:
        proc hello() =
          inc called

        let a = toTask hello()
        invoke(a)

      doAssert called == 1

      block:
        proc hello(a: int) =
          inc called, a

        let b = toTask hello(13)
        let c = toTask hello(a = 14)
        b.invoke()
        c.invoke()

      doAssert called == 28

      block:
        proc hello(a: int, c: int) =
          inc called, a

        let b = toTask hello(c = 0, a = 8)
        b.invoke()

      doAssert called == 36
