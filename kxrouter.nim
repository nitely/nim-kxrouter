import std/[strutils, tables]
when defined(js):
  include pkg/karax/prelude
else:
  import pkg/karax/[karaxdsl, vdom]

export tables

type ViewParams* = TableRef[string, string]

proc newViewParams: ViewParams =
  newTable[string, string]()

type 
  ViewLoadUnload* = proc (ctx: ViewContext) {.closure, raises: [].}
  ViewContext* = ref object
    mount, tick, load, unload: seq[ViewLoadUnload]
    loaded, unloaded: bool
    path*, qry*: string
    params*: ViewParams
  ViewContainer = ref object
    ctx: ViewContext

proc newViewContext(path, qry: string, params: ViewParams): ViewContext {.raises: [].} =
  ViewContext(
    mount: @[],
    tick: @[],
    load: @[],
    unload: @[],
    loaded: false,
    unloaded: false,
    path: path,
    qry: qry,
    params: params
  )

proc newViewContext: ViewContext {.raises: [].} =
  newViewContext("", "", newViewParams())

proc newViewContainer: ViewContainer {.raises: [].} =
  ViewContainer(ctx: newViewContext())

proc isUnloaded*(ctx: ViewContext): bool {.raises: [].} =
  ctx.unloaded

proc onMount*(ctx: ViewContext, cb: ViewLoadUnload) {.raises: [].} =
  if ctx.loaded:
    return
  doAssert cb notin ctx.mount
  ctx.mount.add cb

proc onNextTick*(ctx: ViewContext, cb: ViewLoadUnload) {.raises: [].} =
  if ctx.unloaded:
    return
  if cb notin ctx.tick:
    ctx.tick.add cb

proc onLoad*(ctx: ViewContext, cb: ViewLoadUnload) {.raises: [].} =
  if ctx.loaded:
    return
  doAssert cb notin ctx.load
  ctx.load.add cb
  cb ctx

proc onUnload*(ctx: ViewContext, cb: ViewLoadUnload) {.raises: [].} =
  if ctx.loaded:
    return
  doAssert cb notin ctx.unload
  ctx.unload.add cb

proc doMount(ctx: ViewContext) {.raises: [].} =
  for cb in ctx.mount:
    cb ctx
  ctx.mount.setLen 0

proc doNextTick(ctx: ViewContext) {.raises: [].} =
  for cb in ctx.tick:
    cb ctx
  ctx.tick.setLen 0

proc doLoad(ctx: ViewContext) {.raises: [].} =
  doAssert not ctx.loaded
  ctx.loaded = true
  ctx.load.setLen 0

proc doUnload(ctx: ViewContext) {.raises: [].} =
  ctx.unloaded = true
  try:
    for cb in ctx.unload:
      cb ctx
  finally:
    # break cycles
    ctx.mount.setLen 0
    ctx.tick.setLen 0
    ctx.load.setLen 0
    ctx.unload.setLen 0

type RouteCallback* = proc (ctx: ViewContext): VNode {.nimcall, raises: [].}
type Route* = tuple[path: string, view: RouteCallback]
type Renderer* = proc (path, qry: string): VNode

proc countSlashes(s: string): int {.raises: [].} =
  result = 0
  var i = 0
  while true:
    i = find(s, '/', start = i)
    if i == -1:
      break
    inc result
    inc i

iterator parts(pathA, pathB: string): (string, string) {.inline, raises: [].} =
  doAssert countSlashes(pathA) == countSlashes(pathB)
  var a1 = 0
  var a2 = 0
  var b1 = 0
  var b2 = 0
  while a1 < pathA.len or b1 < pathB.len:
    a2 = find(pathA, '/', start = a1)
    if a2 == -1:
      a2 = pathA.len
    b2 = find(pathB, '/', start = b1)
    if b2 == -1:
      b2 = pathB.len
    yield (pathA[a1 ..< a2], pathB[b1 ..< b2])
    a1 = min(pathA.len, a2+1)
    b1 = min(pathB.len, b2+1)

proc match(rpath, path: string, params: ViewParams): bool {.raises: [].} =
  if countSlashes(rpath) != countSlashes(path):
    return false
  for (p1, p2) in parts(rpath, path):
    if p1.startsWith("{") and p1.endsWith("}") and p2.len > 0:
      params[p1[1 ..< p1.len-1]] = p2
    elif p1 != p2:
      return false
  return true

proc router(routes: seq[Route], notFound: RouteCallback, ctr: ViewContainer): Renderer {.raises: [].} =
  template ctx: untyped = ctr.ctx
  var view = notFound
  proc (path, qry: string): VNode =
    if path == ctx.path:
      ctx.qry = qry
      return view ctx
    let params = newViewParams()
    for r in routes:
      params.clear()
      if match(r.path, path, params):
        ctx.doUnload()
        view = r.view
        ctx = newViewContext(path, qry, params)
        let vnode = view ctx
        ctx.doLoad()
        return vnode
    ctx.doUnload()
    view = notFound
    ctx = newViewContext(path, qry, newViewParams())
    let vnode = view ctx
    ctx.doLoad()
    return vnode

proc router*(routes: seq[Route], notFound: RouteCallback): Renderer {.raises: [].} =
  let ctr = newViewContainer()
  return router(routes, notFound, ctr)

when defined(js):
  proc kxRouter*(routes: seq[Route], notFound: RouteCallback) =
    let ctr = newViewContainer()
    let render = router(routes, notFound, ctr)
    proc postRender(data: RouterData) {.raises: [].} =
      ctr.ctx.doMount()
      ctr.ctx.doNextTick()
    proc renderer(data: RouterData): VNode =
      render($data.hashPart, $data.queryString)
    setRenderer(renderer, "ROOT", postRender)

when isMainModule:
  import std/sequtils

  type Router2 = proc (path: string): VNode
  proc noQry(rr: Renderer): Router2 =
    proc (path: string): VNode =
      rr(path, "")
  proc notFoundView(ctx: ViewContext): VNode =
    buildHtml text("not_found")
  block:
    proc myView(ctx: ViewContext): VNode =
      buildHtml text("my_view")
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert "my_view" in $router("#/my_path")
    doAssert "my_view" notin $router("#/bad_path")
    doAssert "not_found" in $router("#/bad_path")
    doAssert "not_found" in $router("#/")
    doAssert "not_found" in $router("#")
    doAssert "not_found" in $router("")
    doAssert "not_found" in $router("#/a/")
    doAssert "not_found" in $router("#/a/b")
    doAssert "not_found" in $router("#/a/b/")
  block:
    proc myView(ctx: ViewContext): VNode =
      buildHtml text("my_view1")
    proc myView2(ctx: ViewContext): VNode =
      buildHtml text("my_view2")
    let router = router(@[("#/my_path1", myView), ("#/my_path2", myView2)], notFoundView).noQry
    doAssert "my_view1" in $router("#/my_path1")
    doAssert "my_view1" notin $router("#/my_path2")
    doAssert "my_view2" in $router("#/my_path2")
    doAssert "my_view2" notin $router("#/my_path1")
  block:
    proc myView(ctx: ViewContext): VNode =
      buildHtml text(ctx.params["foo"])
    let router = router(@[("#/my_view/{foo}", myView)], notFoundView).noQry
    doAssert "foo" in $router("#/my_view/foo")
    doAssert "bar" in $router("#/my_view/bar")
    for _ in 0 .. 5:
      doAssert "baz" in $router("#/my_view/baz")
  block:
    var count = 0
    proc myView(ctx: ViewContext): VNode =
      ctx.onLoad proc (ctx: ViewContext) =
        inc count
      buildHtml text("my_view")
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert count == 0
    discard $router("#/my_path")
    doAssert count == 1
    discard $router("#/my_path")
    doAssert count == 1
    discard $router("#/bad_path_123")
    doAssert count == 1
    discard $router("#/bad_path_123")
    doAssert count == 1
    discard $router("#/my_path")
    doAssert count == 2
    discard $router("#/my_path")
    doAssert count == 2
  block:
    var count = 0
    proc myView(ctx: ViewContext): VNode =
      ctx.onUnload proc (ctx: ViewContext) =
        inc count
      buildHtml text("my_view")
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert count == 0
    discard $router("#/my_path")
    doAssert count == 0
    discard $router("#/my_path")
    doAssert count == 0
    discard $router("#/bad_path_123")
    doAssert count == 1
    discard $router("#/bad_path_123")
    doAssert count == 1
    discard $router("#/my_path")
    doAssert count == 1
    discard $router("#/my_path")
    doAssert count == 1
    discard $router("#/bad_path_123")
    doAssert count == 2
  block:
    var prevCtx: ViewContext
    proc myView(ctx: ViewContext): VNode =
      let eq = ctx == prevCtx
      prevCtx = ctx
      buildHtml text($eq)
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert "false" in $router("#/my_path")
    doAssert "true" in $router("#/my_path")
    doAssert "true" in $router("#/my_path")
    discard $router("#/bad_path_123")
    doAssert "false" in $router("#/my_path")
    doAssert "true" in $router("#/my_path")
    doAssert "true" in $router("#/my_path")
  block:
    var count = 0
    proc myView(ctx: ViewContext): VNode =
      ctx.onMount proc (ctx: ViewContext) = inc count
      result = buildHtml text("my_view")
      ctx.doMount()
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert count == 0
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 1
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 1
  block:
    var count = 0
    proc myView(ctx: ViewContext): VNode =
      ctx.onNextTick proc (ctx: ViewContext) = inc count
      result = buildHtml text("my_view")
      ctx.doNextTick()
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert count == 0
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 1
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 2
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 3
  block:
    var count = 0
    proc myView(ctx: ViewContext): VNode =
      ctx.onNextTick proc (ctx: ViewContext) = inc count
      result = buildHtml text("my_view")
      ctx.doNextTick()
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    doAssert count == 0
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 1
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 2
    doAssert "my_view" in $router("#/my_path")
    doAssert count == 3
  block:
    var ctx2: ViewContext
    proc myView(ctx: ViewContext): VNode =
      ctx2 = ctx
      buildHtml text "foo"
    let router = router(@[("#/my_path", myView)], notFoundView).noQry
    discard $router("#/my_path")
    doAssert not ctx2.isUnloaded
    discard $router("#/bad_path_123")
    doAssert ctx2.isUnloaded
  block:
    var count = 0
    let ctx = newViewContext()
    ctx.onNextTick proc (ctx2: ViewContext) = inc count
    doAssert count == 0
    ctx.doNextTick()
    ctx.doNextTick()
    ctx.doNextTick()
    doAssert count == 1
  block:
    var count = 0
    let ctx = newViewContext()
    ctx.onNextTick proc (ctx: ViewContext) = inc count
    ctx.doNextTick()
    doAssert count == 1
    ctx.onNextTick proc (ctx: ViewContext) = inc count
    ctx.doNextTick()
    doAssert count == 2
  block:
    # "" and "/" should not match 
    doAssert countSlashes("") == 0
    doAssert countSlashes("/") == 1
    doAssert countSlashes("/a") == 1
    doAssert countSlashes("/a/") == 2
    doAssert countSlashes("/a//") == 3
    doAssert countSlashes("/a/b") == 2
    doAssert countSlashes("/a/b/") == 3
    doAssert countSlashes("a") == 0
    doAssert countSlashes("a/") == 1
  block:
    doAssert toSeq(parts("", "")) == @[]
    doAssert toSeq(parts("/", "/")) == @[("", "")]
    doAssert toSeq(parts("//", "//")) == @[("", ""), ("", "")]
    doAssert toSeq(parts("/", "/a")) == @[("", ""), ("", "a")]
    doAssert toSeq(parts("/", "a/")) == @[("", "a")]
    doAssert toSeq(parts("/a", "/b")) == @[("", ""), ("a", "b")]
    doAssert toSeq(parts("a/", "/b")) == @[("a", ""), ("", "b")]
    doAssert toSeq(parts("/a", "b/")) == @[("", "b"), ("a", "")]
    doAssert toSeq(parts("a/b", "/c")) == @[("a", ""), ("b", "c")]
    doAssert toSeq(parts("a/", "b/c")) == @[("a", "b"), ("", "c")]
    doAssert toSeq(parts("a", "a")) == @[("a", "a")]
    doAssert toSeq(parts("a", "b")) == @[("a", "b")]
    doAssert toSeq(parts("/a/b", "/a/c")) == @[("", ""), ("a", "a"), ("b", "c")]
    doAssert toSeq(parts("/abc", "abc/")) == @[("", "abc"), ("abc", "")]
    doAssert toSeq(parts("abc/", "/abc")) == @[("abc", ""), ("", "abc")]
    doAssert toSeq(parts("ab/ac", "/abc")) == @[("ab", ""), ("ac", "abc")]
    doAssert toSeq(parts("ab/ac", "abc/")) == @[("ab", "abc"), ("ac", "")]
  echo "ok"
