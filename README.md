# KxRouter

KxRouter is a [karax](https://github.com/karaxnim/karax) router with life-time events.

## Usage

```nim
include pkg/karax/prelude
import pkg/kxrouter

proc notFoundView(ctx: ViewContext): VNode =
  buildHtml text("Not found")

proc home(ctx: ViewContext): VNode =
  buildHtml text("Hello world!")

proc events(ctx: ViewContext): VNode =
  ctx.onLoad proc (ctx: ViewContext) = echo "Loaded"
  ctx.onUnload proc (ctx: ViewContext) = echo "Unloaded"
  ctx.onMount proc (ctx: ViewContext) = echo "Mounted"
  ctx.onNextTick proc (ctx: ViewContext) = echo "Next Tick"
  buildHtml text("Events")

proc params(ctx: ViewContext): VNode =
  let foo = ctx.params.getOrDefault "foo"
  buildHtml text(foo)

kxRouter(@[
  ("#/home", home),
  ("#/events", events),
  ("#/params/{foo}", params)
], notFoundView)
```

## Events

The events run for the given view. There are no global events. The received `ctx` callback parameter is always the one used to register the callback.

- Use `onLoad` for initialization.
- Use `onUnload` for cleaning up.
- Use `onMount` to run in the next post-render only once.
- Use `onNextTick` to run in the next post-render. Useful for changing some element after fetching resources, for example scrolling down an element.

The event callbacks need to be registered the first time the view is rendered. Except for `onNextTick` which can be used any time.

## ajaxGet/fetch

When fetching resources, the "done" callback may run after the user has navigating to a different route. Use `if ctx.isUnloaded: return` to return early and avoid undesired side-effects.

```nim
include pkg/karax/prelude
import pkg/karax/kajax
import pkg/kxrouter

var books = newSeq[string]()

proc loadBooks(ctx: ViewContext) {.raises: [].} =
  books.setLen 0
  ajaxGet("/book/list", @[], proc (status: int, response: cstring) =
    if ctx.isUnloaded:
      return
    if status == 200:
      let data = parse response
      for book in data["books"]:
        books.add book.getStr()
    else:
      console.log "err"

proc shelf(ctx: ViewContext): VNode =
  ctx.onLoad loadBooks
  buildHtml tdiv(class="books"):
    for book in books:
      tdiv(class="book"):
        text book
```

## SSR

Server side rendering:

```nim
import pkg/karax/[karaxdsl, vdom]
import pkg/kxrouter

proc notFoundView(ctx: ViewContext): VNode =
  buildHtml text("Not found")

proc books(ctx: ViewContext): VNode =
  buildHtml text("books")

let router = router(@[("#/books", books)], notFoundView)
doAssert "books" in $router("#/books", "book=foo&page=1")
```

These life-time events are ignored in SSR: `onMount` and `onNextTick`.

## LICENSE

MIT
