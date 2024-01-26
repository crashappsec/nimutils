## This wraps my C-based lock-free, wait-free hash table
## implementation.  I don't know much about Nim's multi-threading at
## this point, made worse by the fact that there are so many different
## memory managers in Nim.
##
## So I'm not sure how to use it (you'll definitely want anything
## passed in to be shared memory), nor do I know what memory managers
## it will work with.
##
## That's because my purpose for wrapping this is to enable the con4m
## data store to be accessible via C API, from mulitple
## threads. Con4m, for the forseeable future, should only ever need a
## single thread accessing the store.
##
## This hash table does require any new thread to call registerThread().
##
## Memory management approach:
##
## For most primitive types, we store a 64-bit value that neither Nim
## nor the underlying implementation needs to memory manage. That includes
## all int and float types, bools, enums, etc.
##
## For objects (things that are references and should thus be heap
## allocated in nim) we can GC_ref() them and store them directly.
##
## Strings in nim are generally three-tier. There's a stack-allocated
## value that has the length, and a pointer to a heap-allocated value,
## which contains a capacity and a pointer to the actual c-string.
##
## To deal with this, we create our own heap-allocated data structure
## that keeps the data we need to re-assemble the string when we remove
## it. We also GC_ref() the heap-allocated payload (and unref it when
## ejecting).
##
## We could also ensure a heap-allocated string by sticking it inside
## of a ref object and copying it in, but it's an extra layer of
## indirection for computing the hash value... for strings, we want to
## do that by treating it as a null-terminated C string, not a pointer.
##
## With C strings, we currently bundle them in a Nim string to simplify
## memory management. This may change soon, so don't count on it. Note
## here that, in Nim's FFI, $(x) copies the string, but cstring(s) does
## not.  The 'sink' modifier passes 'ownership'.
##
## For everything else, we'll generally see it stack-allocated, and
## won't necessarily have access to a consistent storage location, even
## if it never leaves the stack. That makes such data objects
## unsuitable for being hash keys (though, we could support custom
## per-type hash functions in the future).
##
## However, we can store such things as *values* by wrapping them in a
## heap allocated object that we then incref. We'll then hold a copy of
## that object.
##
## When anything gets ejected from the hash table other than a
## primitive ordinal or float type, we GC_unref() if it was allocated
## from Nim, and currently ignore otherwise.


import sugar, os, macros, options

{.pragma: hatc, cdecl, importc.}

type
<<<<<<< HEAD
  RawDict* = pointer

  Dict*[T, V] = ref object
    raw*:      ptr RawDict
    metadata*: pointer

=======
  Dict*[T, V] {. importc: "hatrack_dict_t", header: "crownhash.h", nodecl.} = object
  DictRef*[T, V] = ref Dict[T, V]
>>>>>>> 516dc45 (Jtv/strcontainer (#41))
  DictKeyType* = enum
    KTInt, KTFloat, KtCStr, KtPtr, KtObjInt, KtObjReal, KtObjCstr,
    KtObjPtr, KtObjCustom, KtForce32Bits = 0x0fffffff

  StackBox[T] = ref object of RootRef
    ownedByNim: bool
    contents:   T
  StrBoxObj = object
    data:       cstring
    str:        string
    ownedByNim: bool
  StrBox    = ref StrBoxObj
  SomeString  = string | cstring # String box.
  SomeRef     = ref or pointer  # Not boxed.
  SomeNumber  = SomeOrdinal or SomeFloat
  RawItem     = object
    key:   pointer
    value: pointer

proc toStrBox(s: string): StrBox =
  new result

  result.data       = cstring(s)
  result.str        = s
  result.ownedByNim = true
  GC_ref(result)

proc toStrBox(s: cstring): StrBox =
  return toStrBox($(s))

proc unboxStr(s: StrBox): string =
  return s.str

proc ejectStrBox(s: StrBox) =
  if s.ownedByNim:
    GC_unref(s)

proc toStackBox[T](o: T): StackBox[T] =
  result = StackBox[T](contents: o, ownedByNim: true)
  GC_ref(result)

proc unboxStackObj[T](box: StackBox[T]): T =
  return box.contents

proc ejectStackBox[T](s: StackBox[T]) =
  if s.ownedByNim:
    GC_unref(s)

<<<<<<< HEAD
proc hatrack_dict_new*(a: DictKeyType): ptr RawDict {.hatc.};
proc hatrack_dict_init*(ctx: ptr RawDict, key_type: DictKeyType) {.hatc.}
proc hatrack_dict_cleanup*(ctx: ptr RawDict) {.hatc.}
proc hatrack_dict_set_consistent_views*(ctx: ptr RawDict, yes: bool) {.hatc.}
proc hatrack_dict_get_consistent_views*(ctx: ptr RawDict): bool {.hatc.}
proc hatrack_dict_set_hash_offset*(ctx: ptr RawDict, offset: cint) {.hatc.}
proc hatrack_dict_get*(ctx: ptr RawDict, key: pointer, found: var bool):
                     pointer {.hatc.}
proc hatrack_dict_put*(ctx: ptr RawDict, key: pointer, value: pointer) {.hatc.}
proc hatrack_dict_replace*(ctx: ptr RawDict, key: pointer, value: pointer):
=======
proc hatrack_dict_new*(a: DictKeyType): pointer {.hatc.};
proc hatrack_dict_init*(ctx: var Dict, key_type: DictKeyType) {.hatc.}
proc hatrack_dict_cleanup*(ctx: ptr Dict) {.hatc.}
proc hatrack_dict_set_consistent_views*(ctx: var Dict, yes: bool) {.hatc.}
proc hatrack_dict_get_consistent_views*(ctx: var Dict): bool {.hatc.}
proc hatrack_dict_set_hash_offset*(ctx: var Dict, offset: cint) {.hatc.}
proc hatrack_dict_get*(ctx: var Dict, key: pointer, found: var bool):
                     pointer {.hatc.}
proc hatrack_dict_put*(ctx: var Dict, key: pointer,
                       value: pointer) {.hatc.}
proc hatrack_dict_replace*(ctx: var Dict, key: pointer, value: pointer):
>>>>>>> 516dc45 (Jtv/strcontainer (#41))
                     bool {.hatc.}
proc hatrack_dict_add*(ctx: ptr RawDict, key: pointer, value: pointer):
                     bool {.hatc.}
<<<<<<< HEAD
proc hatrack_dict_remove*(ctx: ptr RawDict, key: pointer): bool {.hatc.}
proc hatrack_dict_keys_sort*(ctx: ptr RawDict, n: ptr uint64): pointer {.hatc.}
proc hatrack_dict_values_sort*(ctx: ptr RawDict, n: ptr uint64):
                             pointer {.hatc.}
proc hatrack_dict_items_sort*(ctx: ptr RawDict, n: ptr uint64): pointer {.hatc.}
proc hatrack_dict_keys_nosort*(ctx: ptr RawDict, n: ptr uint64):
                             pointer {.hatc.}
proc hatrack_dict_values_nosort*(ctx: ptr RawDict, n: ptr uint64):
                               pointer {.hatc.}
proc hatrack_dict_items_nosort*(ctx: ptr RawDict, n: ptr uint64):
                              pointer {.hatc.}
proc hatrack_dict_set_free_handler*(ctx: ptr RawDict, cb: pointer) {.hatc.}
=======
proc hatrack_dict_remove*(ctx: var Dict, key: pointer): bool {.hatc.}
proc hatrack_dict_keys_sort*(ctx: var Dict, n: ptr uint64):
                           pointer {.hatc.}
proc hatrack_dict_values_sort*(ctx: var Dict, n: ptr uint64):
                             pointer {.hatc.}
proc hatrack_dict_items_sort*(ctx: var Dict, n: ptr uint64):
                            pointer {.hatc.}
proc hatrack_dict_keys_nosort*(ctx: var Dict, n: ptr uint64):
                             pointer {.hatc.}
proc hatrack_dict_values_nosort*(ctx: var Dict, n: ptr uint64):
                               pointer {.hatc.}
proc hatrack_dict_items_nosort*(ctx: var Dict, n: ptr uint64):
                              pointer {.hatc.}
proc hatrack_dict_set_free_handler*[T, V](ctx: var Dict[T, V],
                       cb: (var Dict[T, V], ptr RawItem) -> void) {.hatc.}
>>>>>>> 516dc45 (Jtv/strcontainer (#41))
proc register_thread() {.cdecl, importc: "mmm_register_thread" .}

proc decrefDictItems[T, V](dict: RawDict, p: ptr RawItem) =
  when T is SomeString:
    ejectStrBox(cast[StrBox](p[].key))
  elif T is ref:
    GC_unref(cast[T](p[].value))

  when V is SomeString:
    ejectStrBox(cast[StrBox](p[].value))
  elif V is ref:
    GC_unref(cast[V](p[].value))
  elif not (V is SomeNumber or V is pointer):
    ejectStackBox(cast[StackBox[seq[int]]](p[].value))

proc decrefStrNil(d: RawDict, p: ptr RawItem) =
  ejectStrBox(cast[StrBox](p[].key))

proc decrefStrStr(d: RawDict, p: ptr RawItem) =
  ejectStrBox(cast[StrBox](p[].key))
  ejectStrBox(cast[StrBox](p[].value))

proc decrefStrRef(d: RawDict, p: ptr RawItem) =
  ejectStrBox(cast[StrBox](p[].key))
  GC_unref(cast[RootRef](p[].value))

proc decrefStrObj(d: RawDict, p: ptr RawItem) =
  ejectStrBox(cast[StrBox](p[].key))
  ejectStackBox(cast[StackBox[seq[int]]](p[].value))

proc decrefRefNil(d: RawDict, p: ptr RawItem) =
  GC_unref(cast[RootRef](p[].key))

proc decrefRefStr(d: RawDict, p: ptr RawItem) =
  GC_unref(cast[RootRef](p[].key))
  ejectStrBox(cast[StrBox](p[].value))

proc decrefRefRef(d: RawDict, p: ptr RawItem) =
  GC_unref(cast[RootRef](p[].key))
  GC_unref(cast[RootRef](p[].value))

proc decrefRefObj(d: RawDict, p: ptr RawItem) =
  GC_unref(cast[RootRef](p[].key))
  ejectStackBox(cast[StackBox[seq[int]]](p[].value))

proc decrefNilStr(d: RawDict, p: ptr RawItem) =
  ejectStrBox(cast[StrBox](p[].value))

proc decrefNilRef(d: RawDict, p: ptr RawItem) =
  GC_unref(cast[RootRef](p[].value))

proc decrefNilObj(d: RawDict, p: ptr RawItem) =
  ejectStackBox(cast[StackBox[seq[int]]](p[].value))

once:
  # Auto-register the main thread.
  registerThread()

proc initDict*[T, V](dict: var Dict[T, V]) =
  assert dict == nil

  dict = Dict[T, V]()

  var
    options: array[3, pointer]
    ix: int

  when V is SomeString:
    options = [
      cast[pointer](decrefStrStr),
      cast[pointer](decrefRefStr),
      cast[pointer](decrefNilStr)
    ]
  elif V is SomeRef:
    options = [
      cast[pointer](decrefStrRef),
      cast[pointer](decrefRefRef),
      cast[pointer](decrefNilRef)
    ]
  elif V is SomeNumber or V is pointer:
    options = [
      cast[pointer](decrefStrNil),
      cast[pointer](decrefRefNil),
      nil
    ]
  else:
    options = [
      cast[pointer](decrefStrObj),
      cast[pointer](decrefRefObj),
      cast[pointer](decrefNilObj)
    ]

  when T is SomeOrdinal:
    dict.raw = hatrack_dict_new(KtInt)
    ix       = 2
  elif T is SomeFloat:
    dict.raw = hatrack_dict_new(KtFloat)
    ix       = 2
  elif T is SomeString:
    dict.raw = hatrack_dict_new(KtObjCStr)
    ix       = 0
    hatrack_dict_set_hash_offset(dict.raw, 0)
  elif T is SomeRef:
    dict.raw = hatrack_dict_new(KtPtr)
    ix       = 1
  else:
    static:
      error("Cannot currently have keys of seq or object types")

  dict.raw.hatrack_dict_set_consistent_views(true)

  let fn = options[ix]

  if fn != nil:
    dict.raw.hatrack_dict_set_free_handler(fn)

proc `[]=`*[T, V](d: Dict[T, V], key: T, value: sink V) =
  ## This assigns, whether or not there was a previous value
  ## associated with the passed key.

  assert d.raw != nil

  var p: pointer
  when T is SomeString:
    p = cast[pointer](key.toStrBox())
  else:
    p = cast[pointer](key)

  when V is SomeOrdinal:
    d.raw.hatrack_dict_put(p, cast[pointer](int64(value)))
  elif V is SomeFloat:
    d.raw.hatrack_dict_put(p, cast[pointer](float(value)))
  elif V is SomeString:
    d.raw.hatrack_dict_put(p, cast[pointer](value.toStrBox()))
  elif V is ref:
    GC_ref(value)
    d.raw.hatrack_dict_put(p, cast[pointer](value))
  elif V is pointer:
    d.raw.hatrack_dict_put(p, cast[pointer](value))
  else:
    d.raw.hatrack_dict_put(p, cast[pointer](value.toStackBox()))

proc replace*[T, V](d: Dict[T, V], key: T, value: sink V): bool =
  ## This replaces the value associated with a given key.  If the key
  ## has not yet been set, then `false` is returned and no value is
  ## set.

  assert d.raw != nil

  var p: pointer
  when T is SomeString:
    p = cast[pointer](key.toStrBox())
  else:
    p = cast[pointer](key)

  when V is SomeOrdinal:
    return d.raw.hatrack_dict_replace(p, cast[pointer](int64(value)))
  elif V is SomeFloat:
    return d.raw.hatrack_dict_replace(p, cast[pointer](float(value)))
  elif V is SomeString:
    return d.raw.hatrack_dict_replace(p, cast[pointer](value.toStrBox()))
  elif V is ref:
    GC_ref(value)
    return d.raw.hatrack_dict_replace(p, cast[pointer](value))
  elif V is pointer:
    return d.raw.hatrack_dict_replace(p, cast[pointer](value))
  else:
    return d.raw.hatrack_dict_replace(p, cast[pointer](value.toStackBox()))

proc add*[T, V](d: Dict[T, V], key: T, value: sink V): bool =
  ## This sets a value associated with a given key, but only if the
  ## key does not exist in the hash table at the time of the
  ## operation.

  assert d.raw != nil

  var p: pointer
  when T is SomeString:
    p = cast[pointer](key.toStrBox())
  else:
    p = cast[pointer](key)

  when V is SomeOrdinal:
<<<<<<< HEAD
    return d.raw.hatrack_dict_add(p, cast[pointer](int64(value)))
  elif V is SomeFloat:
    return d.raw.hatrack_dict_add(p, cast[pointer](float(value)))
  elif V is SomeString:
    return d.raw.hatrack_dict_add(p, cast[pointer](value.toStrBox()))
  elif V is ref:
    GC_ref(value)
    return d.raw.hatrack_dict_add(p, cast[pointer](value))
  elif V is pointer:
    return d.raw.hatrack_dict_add(p, cast[pointer](value))
  else:
    return d.raw.hatrack_dict_add(p, cast[pointer](value.toStackBox()))
=======
    return dict.hatrack_dict_add(p, cast[pointer](int64(value)))
  elif V is SomeFloat:
    return dict.hatrack_dict_add(p, cast[pointer](float(value)))
  elif V is SomeString:
    return dict.hatrack_dict_add(p, cast[pointer](value.toStrBox()))
  elif V is ref:
    GC_ref(value)
    return dict.hatrack_dict_add(p, cast[pointer](value))
  elif V is pointer:
    return dict.hatrack_dict_add(p, cast[pointer](value))
  else:
    return dict.hatrack_dict_add(p, cast[pointer](value.toStackBox()))
>>>>>>> 516dc45 (Jtv/strcontainer (#41))

proc lookup*[T, V](d: Dict[T, V], key: T): Option[V] =
  ## Retrieve the value associated with a key, wrapping it in
  ## an option. If the key isn't present, then returns `none`.
  ##
  ## See the [] operator for a version that throws an exception
  ## if the key is not present in the table.

  assert d.raw != nil

  var
    found: bool
    p:     pointer

  when T is SomeString:
    p = cast[pointer](key.toStrBox())
  else:
    p = cast[pointer](key)

  var retp = d.raw.hatrack_dict_get(p, found)

  if found:
    when V is SomeOrdinal:
      var x: int64 = cast[int64](retp)
      result = some(V(x))
    elif V is SomeFloat:
      var x: float = cast[float](retp)
      result = some(V(x))
    elif V is string:
      var box = cast[StrBox](retp)
      result = some(box.unboxStr())
    elif V is cstring:
      var
        box = cast[StrBox](retp)
        str = box.unboxStr()
      result = some(cstring(str))
    elif V is SomeRef:
      # No need to worry about possible incref; the type will cause
      # the right thing to happen here.
      result = some(cast[V](retp))
    else:
      var box = cast[StackBox[V]](retp)
      result = some(box.contents)

proc contains*[T, V](d: Dict[T, V], key: T): bool =
  ## In a multi-threaded environment, this shouldn't be used when
  ## there might be any sort of race condition.  Use lookup() instead.
  return d.lookup(key).isSome()

proc `[]`*[T, V](d: Dict[T, V], key: T) : V =
  ## Retrieve the value associated with a key, or else throws an error
  ## if it's not present.
  ##
  ## See `lookup` for a version that returns an Option, and thus
  ## will not throw an error when the item is not found.

  var optRet: Option[V] = d.lookup(key)

  if optRet.isSome():
    return optRet.get()
  else:
    raise newException(KeyError, "Dictionary key was not found.")

proc toDict*[T, V](pairs: openarray[(T, V)]): Dict[T, V] =
  ## Use this to convert a nim {} literal to a Dict.
  result = Dict[T, V]()
  for (k, v) in pairs:
    result[k] = v

proc newDict*[T, V](): Dict[T, V] =
  ## Heap-allocate a DictRef
  initDict[T, V](result)

proc del*[T, V](d: Dict[T, V], key: T): bool {.discardable.} =
  ## Deletes any value associated with a given key.
  ##
  ## Note that this does *not* throw an exception if the item is not present,
  ## as multiple threads might be attempting parallel deletes. Instead,
  ## if you care about the op succeeding, check the return value.

  assert d.raw != nil

  var
    p: pointer

  when T is SomeString:
    p = cast[pointer](key.toStrBox())
  else:
    p = cast[pointer](key)

  return d.raw.hatrack_dict_remove(p)

proc delete*[T, V](dict: Dict[T, V], key: T): bool {.discardable.} =
  return del[T, V](dict, key)


proc keys*[T, V](d: Dict[T, V], sort = false): seq[T] =
  ## Returns a consistent view of all keys in a dictionary at some
  ## moment in time during the execution of the function.
  ##
  ## Note that this is *not* an iterator. This is intentional. The
  ## only way to get a consistent view in a parallel environment is to
  ## create a consistent copy; we already have the copy, so having an
  ## extra layer of cursor state is definitely not needed.
  ##
  ## Memory is cheap and plentyful; you'll survive.

  assert d.raw != nil

  when T is SomeString:
    var p: ptr UncheckedArray[StrBox]
  elif T is SomeOrdinal:
    var p: ptr UncheckedArray[int64]
  elif T is SomeFloat:
    var p: ptr UncheckedArray[float]
  else:
    var p: ptr UncheckedArray[T]

  var
    n: uint64

  if sort:
    p = cast[typeof(p)](hatrack_dict_keys_sort(d.raw, addr n))
  else:
    p = cast[typeof(p)](hatrack_dict_keys_nosort(d.raw, addr n))

  for i in 0 ..< n:
    when T is string:
      result.add(unboxStr(p[i]))
    elif T is cstring:
      result.add(cstring(unboxStr(p[i])))
    else:
      result.add(T(p[i]))

proc values*[T, V](d: Dict[T, V], sort = false): seq[V] =
  ## Returns a consistent view of all values in a dictionary at some
  ## moment in time during the execution of the function.
  ##
  ## Note that this is *not* an iterator. This is intentional. The
  ## only way to get a consistent view in a parallel environment is to
  ## create a consistent copy; we already have the copy, so having an
  ## extra layer of cursor state is definitely not needed.
  ##
  ## Memory is cheap and plentyful; you'll survive.

  assert d.raw != nil

  when V is SomeOrdinal:
    var
      p: ptr UncheckedArray[int64]
  elif V is SomeFloat:
    var
      p: ptr UncheckedArray[float]
  elif V is SomeRef:
    var
      p: ptr UncheckedArray[V]
  elif V is SomeString:
    var
      p: ptr UncheckedArray[StrBox]
  else:
    var
      p: ptr UncheckedArray[StackBox[V]]

  var n: uint64

  if sort:
    p = cast[typeof(p)](hatrack_dict_values_sort(d.raw, addr n))
  else:
    p = cast[typeof(p)](hatrack_dict_values_nosort(d.raw, addr n))

  for i in 0 ..< n:
    when V is SomeOrdinal or V is SomeFloat:
      result.add(V(p[i]))
    elif V is SomeRef:
      var r = V(p[i])
      result.add(r)
    elif V is string:
      result.add(unboxStr(p[i]))
    elif V is cstring:
      result.add(cstring(unboxStr(p[i])))
    else:
      result.add(unboxStackObj[V](p[i]))

proc items*[T, V](d: Dict[T, V], sort = false): seq[(T, V)] =
  ## Returns a consistent view of all key, value pairs in a dictionary
  ## at some moment in time during the execution of the function.
  ##
  ## Note that this is *not* an iterator. This is intentional. The
  ## only way to get a consistent view in a parallel environment is to
  ## create a consistent copy; we already have the copy, so having an
  ## extra layer of cursor state is definitely not needed.
  ##
  ## Memory is cheap and plentyful; you'll survive.

  assert d.raw != nil

  var
    p:    ptr UncheckedArray[RawItem]
    n:    uint64
    item: tuple[key: T, value: V]

  if sort:
    p = cast[typeof(p)](hatrack_dict_items_sort(d.raw, addr n))
  else:
    p = cast[typeof(p)](hatrack_dict_items_nosort(d.raw, addr n))

  for i in 0 ..< n:
    var uncast = p[i]

    when T is string:
      item.key = unboxStr(cast[StrBox](uncast.key))
    elif T is cstring:
      item.key = cstring(unboxStr(cast[StrBox](uncast.key)))
    elif T is SomeOrdinal:
      item.key = T(cast[int64](uncast.key))
    elif T is SomeFloat:
      item.key = T(cast[float](uncast.key))
    else: # T is SomeRef
      item.key = T(uncast.key)

    when V is string:
      item.value = unboxStr(cast[StrBox](uncast.value))
    elif V is cstring:
      item.value = cstring(unboxStr(cast[StrBox](uncast.value)))
    elif V is SomeOrdinal:
      item.value = V(cast[int64](uncast.value))
    elif V is SomeFloat:
      item.value = T(cast[float](uncast.value))
    elif V is SomeRef:
      item.value = cast[V](uncast.value)
    else:
      item.value = unboxStackObj[V](cast[StackBox[V]](uncast.value))



    result.add(item)

proc `$`*[T, V](d: Dict[T, V]): string =
  let view = d.items()
  result = "{ "
  for i, (k, v) in view:
    if i != 0:
      result &= ", "
    when T is SomeString:
      result &= "\"" & $(k) & "\" : "
    else:
      result &= $(k) & " : "
    when V is SomeString:
      result &= "\"" & $(v) & "\""
    else:
      result &= $(v)
  result &= " }"

proc deepEquals*[T, V](dict1: Dict[T, V], dict2: Dict[T, V]): bool =
  ## This operation doesn't make too much sense in most cases; we'll
  ## leave == to default to a pointer comparison (for dictrefs).
  let
    view1 = dict1.items[T, V](sort = true)
    view2 = dict2.items[T, V](sort = true)

  if view1.len() != view2.len():
    return false

  for i in 0 ..< view1.len():
    let
      (k1, v1) = view1[i]
      (k2, v2) = view2[i]
    if k1 != k2 or v1 != v2:
      return false

  return true
