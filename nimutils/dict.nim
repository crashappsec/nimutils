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


import sugar, os, macros, options, libwrap
export libwrap



proc newDict*[T, V]: Dict[T, V] =

  when T is SomeOrdinal:
    result = dict_new(cint(KtInt))
  elif T is SomeFloat:
    return dict_new(cint(KtFloat))
  elif T is SomeString:
    result = dict_new(cint(KtCStr))
  elif T is SomeRef:
    return dict_new(cint(KtPtr))
  else:
    static:
      error("Cannot currently have keys of seq or object types")


proc `[]=`*[T, V](d: Dict[T, V], key: T, value: sink V) =
  ## This assigns, whether or not there was a previous value
  ## associated with the passed key.

  assert d != nil

  var p: pointer
  when T is SomeString:
    p = c4str(key)
  else:
    p = cast[pointer](key)

  when V is SomeOrdinal:
    d.hatrack_dict_put(p, cast[pointer](int64(value)))
  elif V is SomeFloat:
    d.hatrack_dict_put(p, cast[pointer](float(value)))
  elif V is SomeString:
    d.hatrack_dict_put(p, cast[pointer](cstring(value)))
  elif V is ref:
    GC_ref(value)
    d.hatrack_dict_put(p, cast[pointer](value))
  elif V is pointer:
    d.hatrack_dict_put(p, cast[pointer](value))
  else:
    d.hatrack_dict_put(p, cast[pointer](value.toStackBox()))

proc replace*[T, V](d: Dict[T, V], key: T, value: sink V): bool =
  ## This replaces the value associated with a given key.  If the key
  ## has not yet been set, then `false` is returned and no value is
  ## set.

  var p: pointer
  when T is SomeString:
    p = c4str(key)
  else:
    p = cast[pointer](key)

  when V is SomeOrdinal:
    return d.hatrack_dict_replace(p, cast[pointer](int64(value))) != 0
  elif V is SomeFloat:
    return d.hatrack_dict_replace(p, cast[pointer](float(value))) != 0
  elif V is SomeString:
    return d.hatrack_dict_replace(p, c4str(value)) != 0
  elif V is ref:
    GC_ref(value)
    return d.hatrack_dict_replace(p, cast[pointer](value)) != 0
  elif V is pointer:
    return d.hatrack_dict_replace(p, cast[pointer](value)) != 0
  else:
    return d.hatrack_dict_replace(p, cast[pointer](value.toStackBox())) != 0

proc add*[T, V](d: Dict[T, V], key: T, value: sink V): bool =
  ## This sets a value associated with a given key, but only if the
  ## key does not exist in the hash table at the time of the
  ## operation.

  var p: pointer
  when T is SomeString:
    p = cast[pointer](cstring(key))
  else:
    p = cast[pointer](key)

  when V is SomeOrdinal:
    return d.hatrack_dict_add(p, cast[pointer](int64(value))) != 0
  elif V is SomeFloat:
    return d.hatrack_dict_add(p, cast[pointer](float(value))) != 0
  elif V is SomeString:
    return d.hatrack_dict_add(p, c4str(value)) != 0
  elif V is ref:
    GC_ref(value)
    return d.hatrack_dict_add(p, cast[pointer](value)) != 0
  elif V is pointer:
    return d.hatrack_dict_add(p, cast[pointer](value)) != 0
  else:
    return d.hatrack_dict_add(p, cast[pointer](value.toStackBox())) != 0

proc lookup*[T, V](d: Dict[T, V], key: T): Option[V] =
  ## Retrieve the value associated with a key, wrapping it in
  ## an option. If the key isn't present, then returns `none`.
  ##
  ## See the [] operator for a version that throws an exception
  ## if the key is not present in the table.

  var
    found: cint
    p:     pointer

  when T is SomeString:
    p = c4str(key)
  else:
    p = cast[pointer](key)

  var retp = d.hatrack_dict_get(p, addr found)

  if found != 0:
    when V is SomeOrdinal:
      var x: int64 = cast[int64](retp)
      result = some(V(x))
    elif V is SomeFloat:
      var x: float = cast[float](retp)
      result = some(V(x))
    elif V is string:
      var cstr = cast[cstring](retp)
      result = some($(cstr))
    elif V is cstring:
      result = some(cstring(retp))
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
    raise newException(KeyError, "Dictionary key " & $(key) & " was not found.")

proc toDict*[T, V](pairs: openarray[(T, V)]): Dict[T, V] =
  ## Use this to convert a nim {} literal to a Dict.
  result = newDict[T, V]()

  for (k, v) in pairs:
    result[k] = v

proc del*[T, V](d: Dict[T, V], key: T): bool {.discardable.} =
  ## Deletes any value associated with a given key.
  ##
  ## Note that this does *not* throw an exception if the item is not present,
  ## as multiple threads might be attempting parallel deletes. Instead,
  ## if you care about the op succeeding, check the return value.

  var
    p: pointer

  when T is SomeString:
    p = cast[pointer](cstring(key))
  else:
    p = cast[pointer](key)

  return d.hatrack_dict_remove(p) != 0

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

  when T is SomeString:
    var p: ptr UncheckedArray[cstring]
  elif T is SomeOrdinal:
    var p: ptr UncheckedArray[int64]
  elif T is SomeFloat:
    var p: ptr UncheckedArray[float]
  else:
    var p: ptr UncheckedArray[T]

  var
    n: uint64

  if sort:
    p = cast[typeof(p)](hatrack_dict_keys_sort(d, addr n))
  else:
    p = cast[typeof(p)](hatrack_dict_keys_nosort(d, addr n))

  for i in 0 ..< n:
    when T is string:
      result.add(`$`(p[i]))
    elif T is cstring:
      result.add(p[i])
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
      p: ptr UncheckedArray[cstring]
  else:
    var
      p: ptr UncheckedArray[StackBox[V]]

  var n: uint64

  if sort:
    p = cast[typeof(p)](hatrack_dict_values_sort(d, addr n))
  else:
    p = cast[typeof(p)](hatrack_dict_values_nosort(d, addr n))

  for i in 0 ..< n:
    when V is SomeOrdinal or V is SomeFloat:
      result.add(V(p[i]))
    elif V is SomeRef:
      var r = p[i]
      result.add(r)
    elif V is string:
      result.add(`$`(cstring(p[i])))
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

  var
    p:    ptr UncheckedArray[RawItem]
    n:    uint64
    item: tuple[key: T, value: V]

  if sort:
    p = cast[typeof(p)](hatrack_dict_items_sort(d, addr n))
  else:
    p = cast[typeof(p)](hatrack_dict_items_nosort(d, addr n))

  for i in 0 ..< n:
    var uncast = p[i]

    when T is string:
      item.key = `$`(cast[cstring](uncast.key))
    elif T is cstring:
      item.key = cstring(cast[cstring](uncast.key))
    elif T is SomeOrdinal:
      item.key = T(cast[int64](uncast.key))
    elif T is SomeFloat:
      item.key = T(cast[float](uncast.key))
    else: # T is SomeRef
      item.key = uncast.key

    when V is string:
      item.value = `$`(cast[cstring](uncast.value))
    elif V is cstring:
      item.value = cstring(cast[cstring](uncast.value))
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
