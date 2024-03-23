import options

{.pragma: hatc, cdecl, importc.}

type
  FlexArrayObj* = pointer

  FlexArray*[T] = ref object
    arr*:      ptr FlexArrayObj
    metadata*: pointer

  FlexView = pointer

proc flexarray_init*(arr: ptr FlexArrayObj, n: uint64) {.hatc.}
proc flexarray_new*(n: uint64): ptr FlexArrayObj {.hatc.}
proc flexarray_set_ret_callback*(arr: ptr FlexArrayObj,
                                   fn: pointer) {.hatc.}
proc flexarray_set_eject_callback*(arr: ptr FlexArrayObj,
                                     fn: pointer) {.hatc.}
proc flexarray_cleanup*(arr: ptr FlexArrayObj) {.hatc.}
proc flexarray_delete*(arr: ptr FlexArrayObj) {.hatc.}
proc flexarray_get*(arr: ptr FlexArrayObj, ix: uint64,
                      err: ptr cint): pointer {.hatc.}
proc flexarray_set*(arr: ptr FlexArrayObj, ix: uint64,
                      val: pointer): bool {.hatc.}
proc flexarray_grow*(arr: ptr FlexArrayObj, sz: uint64) {.hatc.}
proc flexarray_shrink*(arr: ptr FlexArrayObj, sz: uint64) {.hatc.}
proc flexarray_len*(arr: ptr FlexArrayObj): csize_t {.hatc.}
proc flexarray_view*(arr: ptr FlexArrayObj): ptr FlexView {.hatc.}
proc flexarray_view_next*(view: ptr FlexView, done: ptr bool): pointer {.hatc.}
proc flexarray_view_delete*(view: ptr FlexView) {.hatc.}
proc flexarray_view_get*(view: ptr FlexView, ix: uint64,
                           err: ptr cint) {.hatc.}
proc flexarray_view_len*(view: ptr FlexView) {.hatc.}
proc flexarray_add*(a1, a2: ptr FlexArrayObj): ptr FlexArrayObj {.hatc.}

proc arrayItemDecref[T](item: T) =
  GC_unref(item)

proc newArray*[T](n = 0): FlexArray[T] =
  result     = FlexArray[T]()
  result.arr = flexarray_new(uint64(n))

  when T is ref:
    result.arr.flexarray_set_eject_callback(cast[pointer](arrayItemDecref[T]))

proc get*[T](fa: FlexArray[T], ix: int): Option[T] =
  var code: cint
  let p = flexarray_get(fa.arr, uint64(ix), addr code)
  if code == 0:
    return some(cast[T](p))
  else:
    return none(T)

proc `[]`*[T](fa: FlexArray[T], ix: int): T =
  var code: cint
  let p = flexarray_get(fa.arr, uint64(ix), addr code)

  if code == 0:
    return cast[T](p)
  else:
    raise newException(ValueError, "Array index out of bounds")

proc `[]=`*[T](fa: FlexArray[T], ix: int, item: T) =
  when T is ref:
    GC_ref(item)
  if not flexarray_set(fa.arr, uint64(ix), cast[pointer](item)):
    raise newException(ValueError, "Array index out of bounds")

proc put*[T](fa: FlexArray[T], ix: int, item: T): bool {.discardable.} =
  when T is ref:
    GC_ref(item)
  return flexarray_set(fa.arr, uint64(ix), cast[pointer](item))

proc newArrayFromSeq*[T](s: seq[T]): FlexArray[T] =
  result = FlexArray[T]()
  result.arr = flexarray_new(uint64(s.len()))

  when T is ref:
    result.arr.flexarray_set_eject_callback(cast[pointer](arrayItemDecref[T]))

  for item in s:
    when T is ref:
      GC_ref(item)

  for i, item in s:
    discard flexarray_set(result.arr, uint64(i), cast[pointer](item))

proc items*[T](fa: FlexArray[T]): seq[T] =
  var
    found: bool
    view  = fa.arr.flexarray_view()

  result = @[]

  while true:
    let item = view.flexarray_view_next(addr found)
    if not found:
      break
    result.add(cast[T](item))

  view.flexarray_view_delete()

proc `+`*[T](arr1, arr2: FlexArray[T]): FlexArray[T] =
  result     = FlexArray[T]()
  result.arr = flexarray_add(arr1.arr, arr2.arr)

proc len*[T](arr: FlexArray[T]): int {.cdecl, exportc.} =
  return int(arr.arr.flexarray_len())
