{.pragma: hatc, cdecl, nodecl, importc.}

import "std"/[unicode, options, strutils, macros, terminal]

template outptr*(p: pointer, s: string = "") =
  echo toHex(cast[uint](p)), " ", s

{.emit: """
#include <stdint.h>

void *
con4m_flexarray(type_spec_t *t, int64_t l)
{
  return con4m_new(tspec_list(t), kw("length", ka(l)));
}

buffer_t *
con4m_buffer(int64_t l)
{
  return con4m_new(tspec_buffer(), kw("length", ka(l)));
}

tuple_t *
con4m_tuple(type_spec_t *t)
{
  return con4m_new(t);
}

mixed_t *
con4m_mixed(type_spec_t *t)
{
return con4m_new(tspec_mixed(), kw("type", ka(t)));
}

grid_t *
con4m_ordered_list(flexarray_t *l, char *bullet_style, char *item_style)
{
    return ordered_list(l, kw("bullet_style", ka(bullet_style),
                              "item_style",   ka(item_style)));
}

grid_t *
con4m_unordered_list(flexarray_t *l, char *bullet_style, char *item_style,
                     codepoint_t bullet)
{
    return unordered_list(l, kw("bullet_style", ka(bullet_style),
                                "item_style",   ka(item_style),
                                "bullet",       ka(bullet)));
}

utf32_t *
con4m_grid_to_str(grid_t *grid, int64_t width)
{
    xlist_t *lines = grid_render(grid, kw("width", ka(width)));

    return string_join(lines, utf32_repeat('\n', 1));
}

void
print_err(object_t obj)
{
  print(obj, kw("stream", ka(get_stderr())));
}

void
marshal_type_environment(stream_t *stream, dict_t *memos, int *ptr)
{
  con4m_sub_marshal(global_type_env, stream, memos, ptr);
}

void
unmarshal_type_environment(stream_t *stream, dict_t *memos)
{
  global_type_env = con4m_sub_unmarshal(stream, memos);
}


""".}

type
  RawList* {.final, pure, header: "con4m.h", importc: "flexarray_t".} = object
  RawXList* {.final, pure, header: "con4m.h", importc: "xlist_t".} = object
  RawDict* {.final, pure.} = object
  RawItem* = object
    key*: pointer
    value*: pointer
  RawBuffer* {.header: "con4m.h", importc: "buffer_t".} = object
    data*:      cstring
    flags*:     cint
    byte_len*:  cint
    alloc_len*: cint
  RawGrid* {.header: "con4m.h", importc: "grid_t".} = object
  Buffer* = ptr RawBuffer
  Grid* = ptr RawGrid
  Mixed* = pointer
  LitError* {.final, pure.} = object
    location*: uint # Not used RN.
    errcode*:  cint


  # For now, we will not parameterize trees, just make them all take strings.
  # And for tuples, we're just going to use pointers.
  Tree* = pointer
  C4TupObj* {.header: "con4m.h", importc: "tuple_t".} = object
    items*: ptr pointer
    num*:   cint

  CTuple* = ptr C4TupObj
  Color* = cint
  Alignment* = enum
    AlignIgnore       = 0,
    AlignLeft         = 1,
    AlignRight        = 2,
    AlignCenter       = 4,
    AlignTop          = 8,
    AlignTopLeft      = 9,
    AlignTopRight     = 10,
    AlignTopCenter    = 12,
    AlignBottom       = 16,
    AlignBottomLeft   = 17,
    AlignBottomRight  = 18,
    AlignBottomCenter = 20,
    AlignMiddle       = 32,
    AlignMidLeft      = 33,
    AlignMidRight     = 34,
    AlignMidCenter    = 36

  Dict*[T, V] = ptr RawDict
  List*[T]    = ptr RawList
  XList*[T]    = ptr RawXList
  TextStyle* = uint
  RenderStyle* = pointer
  BorderSet* = int8


  DictKeyType* = enum
    KTInt, KTFloat, KtCStr, KtPtr, KtObjInt, KtObjReal, KtObjCstr,
    KtObjPtr, KtObjCustom, KtForce32Bits = 0x0fffffff

  SomeString*  = string | cstring
  SomeRef*     = ref or pointer
  SomeNumber*  = SomeOrdinal or SomeFloat

  C4ObjBase* {.final, pure.} = object
  C4Obj* = ptr C4ObjBase

  C4StrObj* {.final, pure, header: "con4m.h", importc: "utf8_t".}  = object
    cp*:    cint
    bytes*: cint
    syles*: pointer
    data*:  cstring

  Rich* = ptr C4StrObj

  TypeEnvObj* {.final, pure.} = object
  TypeEnv* = ptr TypeEnvObj

  TypeDetailsObj* {.final, pure, header: "con4m.h",
                    importc: "type_details_t".} = object
    name*:      cstring
    base_type*: pointer
    params*:    pointer
    unused*:    pointer
    flags*:     uint8

  TypeSpecObj* {.final, pure, header: "con4m.h",
                 importc: "type_spec_t".} = object
    typeid*: int64
    details*: ptr TypeDetailsObj

  TypeSpec* = ptr TypeSpecObj

  StreamState* {.final, pure.} = object
  CStream* = ptr StreamState

  LibTid* = enum
    C4_TYPE_ERROR    = 0,
    C4_VOID          = 1,
    C4_BOOL          = 2,
    C4_I8            = 3,
    C4_BYTE          = 4,
    C4_I32           = 5,
    C4_CHAR          = 6,
    C4_U32           = 7,
    C4_INT           = 8,
    C4_UINT          = 9,
    C4_F32           = 10,
    C4_F64           = 11,
    C4_UTF8          = 12,
    C4_BUFFER        = 13,
    C4_UTF32         = 14,
    C4_GRID          = 15,
    C4_LIST          = 16,
    C4_TUPLE         = 17,
    C4_DICT          = 18,
    C4_SET           = 19,
    C4_TYPESPEC      = 20,
    C4_IPV4          = 21,
    C4_IPV6          = 22,
    C4_DURATION      = 23,
    C4_SIZE          = 24,
    C4_DATETIME      = 25,
    C4_DATE          = 26,
    C4_TIME          = 27,
    C4_URL           = 28,
    C4_CALLBACK      = 29,
    C4_QUEUE         = 30,
    C4_RING          = 31,
    C4_LOGRING       = 32,
    C4_STACK         = 33,
    C4_RENDERABLE    = 34,
    C4_XLIST         = 35, # single-threaded list.
    C4_RENDER_STYLE  = 36,
    C4_SHA           = 37,
    C4_EXCEPTION     = 38,
    C4_TYPE_ENV      = 39,
    C4_TREE          = 40,
    C4_FUNCDEF       = 41,
    C4_REF           = 42,
    C4_GENERIC       = 43,
    C4_STREAM        = 44,
    C4_KEYWORD       = 45

const
  BORDER_TOP*          = 0x01
  BORDER_BOTTOM*       = 0x02
  BORDER_LEFT*         = 0x04
  BORDER_RIGHT*        = 0x08
  INTERIOR_HORIZONTAL* = 0x10
  INTERIOR_VERTICAL*   = 0x20
  BT_NIL*: int32       = 0
  BT_PRIMATIVE*: int32 = 1
  BT_INTERNAL*: int32  = 2
  BT_TVAR*: int32      = 3
  BT_LIST*: int32      = 4
  BT_DICT*: int32      = 5
  BT_TUPLE*: int32     = 6
  BT_FUNC*: int32      = 7



proc xlist_get*[T](l: XList[T], ix: int, err: ptr cint): T {.hatc.}
proc xlist_len*[T](t: XList[T]): int {.hatc.}
proc len*[T](t: XList[T]): int =
  return xlist_len(t)
proc add*[T](t: Xlist[T], v: T) {.hatc, importc: "xlist_append".}
proc `&`*[T](t, v: XList[T]): Xlist[T] {.hatc, importc: "xlist_plus".}
proc `&=`*[T](t: var XList[T], v: XList[T]) {.hatc, importc: "xlist_plus_eq".}
proc xlist_set[T](t: XList[T], ix: int, v: pointer): cint {.hatc.}

proc `[]`*[T](l: XList[T], ix: int): T  =
  var err: cint = 0

  result = xlist_get[T](l, ix, addr err)
  if err != 0:
    raise newException(ValueError, "Invalid index.")

proc `[]=`*[T](l: XList[T], ix: int, v: pointer) =
    var err = xlist_set(l, ix, v)

    if err != 0:
      raise newException(ValueError, "Invalid index.")

proc list_get*[T](l: List[T], i: int, r: ptr bool):
             T {.hatc, importc: "flexarray_get", discardable .}
proc list_set*[T](l: List[T], i: int, val: T):
             bool {.hatc, importc: "flexarray_set", discardable .}

proc flexarray_view*[T](l: List[T]): pointer{.hatc.}
proc flexarray_view_len*(p: pointer): uint {.hatc.}
proc flexarray_view_next*(p: pointer, a: ptr int): pointer {.hatc.}

proc items*[T](l: List[T]): seq[T] =
  let
    view = flexarray_view(l)
    l    = flexarray_view_len(view)

  for i in 0 ..< l:
    result.add(cast[T](flexarray_view_next(view, nil)))

proc `[]`*[T](l: List[T], ix: int): T =
  return list_get(l, ix, cast [ptr bool](nil))

proc `[]=`*[T](l: List[T], ix: int, item: T) =
  return list_set(l, ix, item)

proc lookup_cell_style*(name: cstring): RenderStyle {.hatc.}

# Type system.

proc is_concrete*(t: TypeSpec):
                      bool {.hatc, importc: "type_spec_is_concrete".}

proc get_builtin_type*(n: LibTid): TypeSpec {.hatc.}

proc tspec_string*(): TypeSpec =
  return get_builtin_type(C4_UTF8)

proc tspec_utf8*(): TypeSpec =
  return get_builtin_type(C4_UTF8)

proc tspec_utf32*(): TypeSpec =
  return get_builtin_type(C4_UTF32)

proc tspec_ip*(): TypeSpec =
  return get_builtin_type(C4_IPV4)

proc tspec_error*(): TypeSpec {.hatc.}
proc tspec_list*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_xlist*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_queue*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_ring*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_stack*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_dict*(t1, t2: TypeSpec): TypeSpec {.hatc.}
proc tspec_set*(t1: TypeSpec): TypeSpec {.hatc.}
proc tspec_tuple*(l: XList[TypeSpec]):
                TypeSpec {.hatc, importc: "tspec_tuple_from_xlist".}
proc tspec_fn*(ret: TypeSpec, l: XList[TypeSpec], va: bool):
             TypeSpec {.hatc.}
proc tspec_varargs_fn*(ret: TypeSpec, n: int,
                       l: varargs[TypeSpec]): TypeSpec {.hatc.}
proc tspec_is_error*(t: TypeSpec): bool {.hatc, importc: "type_spec_is_error".}
proc tspec_is_locked*(t: TypeSpec):
                    bool {.hatc, importc: "type_spec_is_locked".}

template is_type_error*(t: TypeSpec): bool =
  t.tspec_is_error()
proc tspec_lock*(t: TypeSpec) {.hatc, importc: "type_spec_lock".}
proc tspec_unlock*(t: TypeSpec) {.hatc, importc: "type_spec_unlock".}
proc tspec_typevar*(): TypeSpec {.hatc.}
proc tspec_void*(): TypeSpec {.hatc.}
proc tspec_bool*(): TypeSpec {.hatc.}
proc tspec_byte*(): TypeSpec {.hatc.}
proc tspec_char*(): TypeSpec {.hatc.}
proc tspec_i8*(): TypeSpec {.hatc.}
proc tspec_u8*(): TypeSpec {.hatc.}
proc tspec_i32*(): TypeSpec {.hatc.}
proc tspec_u32*(): TypeSpec {.hatc.}
proc tspec_i64*(): TypeSpec {.hatc.}
proc tspec_u64*(): TypeSpec {.hatc.}
proc tspec_f64*(): TypeSpec {.hatc.}
proc tspec_buffer*(): TypeSpec {.hatc.}
proc tspec_grid*(): TypeSpec {.hatc.}
proc tspec_typespec*(): TypeSpec {.hatc.}
proc tspec_ipv4*(): TypeSpec {.hatc.}
proc tspec_duration*(): TypeSpec {.hatc.}
proc tspec_size*(): TypeSpec {.hatc.}
proc tspec_datetime*(): TypeSpec {.hatc.}
proc tspec_date*(): TypeSpec {.hatc.}
proc tspec_time*(): TypeSpec {.hatc.}
proc tspec_url*():  TypeSpec {.hatc.}
proc tspec_callback*(): TypeSpec {.hatc.}
proc tspec_hash*(): TypeSpec {.hatc.}
proc tspec_mixed*(): TypeSpec {.hatc.}
proc tspec_stream*(): TypeSpec {.hatc.}

proc unify*(t1, t2: TypeSpec): TypeSpec {.hatc, importc: "merge_types"}
proc tspec_compare*(t1, t2: TypeSpec):
                  bool {.hatc, importc: "tspecs_are_compat".}
template typeCheck*(t1, t2: TypeSpec): bool =
  tspec_compare(t1, t2)
proc tspec_get_parameters*(t: TypeSpec): Xlist[TypeSpec] {.hatc.}
proc num_params*(t: TypeSpec):
               cint {.hatc, importc: "type_spec_get_num_params".}
proc get_param*(t: TypeSpec, i: cint):
              TypeSpec {.hatc, importc: "tspec_get_param".}
proc get_my_type*(o: C4Obj): TypeSpec {.hatc.}
proc get_base_type_id*(o: C4Obj): int {.hatc.}
proc base_type_id*(t: TypeSpec): int {.hatc, importc: "tspec_get_base_tid".}
proc get_type_kind*(t: TypeSpec):
                  cint {.hatc, importc: "type_spec_get_type_kind".}

proc get_con4m_type*[T](x: T): TypeSpec

proc nim_type_hack*[T](item: List[T] | XList[T] | seq[T]): typedesc =
  return T

proc get_item_type*[T](l: List[T] | XList[T] | seq[T]): TypeSpec =
  return get_con4m_type(l[0])

proc get_key_type*[K, V](item: Dict[K, V]): TypeSpec =
  var key: K
  return get_con4m_type(key)

proc get_val_type*[K, V](item: Dict[K, V]): TypeSpec =
  var val: V
  return get_con4m_type(val)

proc nim_key_type*[K, V](d: Dict[K, V]): typedesc =
  return K

proc nim_val_type*[K, V](d: Dict[K, V]): typedesc =
  return V

proc nim_item_type*[T](l: List[T]): typedesc =
  return T

proc get_con4m_type*[T](x: T): TypeSpec =
  when T is int:
    return get_builtin_type(C4_INT)
  elif T is uint:
    return get_builtin_type(C4_UINT)
  elif T is Rune or T is cint:
    return get_builtin_type(C4_I32)
  elif T is cuint:
    return get_builtin_type(C4_U32)
  elif T is Grid:
    return get_builtin_type(C4_GRID)
  elif T is char:
    return get_builtin_type(C4_I8)
  elif T is uint8:
    return get_builtin_type(C4_U8)
  elif T is XList or T is seq or T is List:
    return tspec_xlist(get_con4m_type[T](x))
  elif T is Dict:
    let key_type = get_key_type(x)
    let val_type = get_val_type(x)
    return tspec_dict(key_type, val_type)
  elif T is SomeRef:
    return get_builtin_type(C4_REF)
  elif T is SomeString:
    return get_builtin_type(C4_UTF8)

proc con4m_xlist*(t: TypeSpec): ptr RawXList {.hatc.}

proc new_xlist*[T](t: TypeSpec = nil): XList[T] =
  return cast[XList[T]](con4m_xlist(t))

proc con4m_flexarray[T](t: TypeSpec, l: int): pointer {.importc, cdecl.}

proc new_list*[T](l: seq[T]): List[T] =
  result = cast[List[T]](con4m_flexarray[T](get_item_type(result), l.len()))

proc internal_ol[T](l: List[T], s1, s2: cstring):
                Grid {.cdecl, importc: "con4m_ordered_list" .}

proc internal_ul[T](l: List[T], s1, s2: cstring, r: Rune):
                Grid {.cdecl, importc: "con4m_unordered_list" .}

proc ol*[T: Grid | Rich](l: seq[T], bullet_style = "bullet",
                         item_style = "li"): Grid =
    var list = new_list[T](l)

    for i, item in l:
        list_set(list, i, item)

    return internal_ol[T](list, cstring(bullet_style),
                       cstring(item_style))

proc ul*[T: Grid | Rich](l: seq[T], bullet_style = "bullet",
                         item_style = "li", bullet = Rune(0x2022)): Grid =
    var list = new_list[T](l)

    for i, item in l:
        list_set(list, i, item)

    return internal_ul[T](list, cstring(bullet_style),
                       cstring(item_style), bullet)

proc toXList*[T](l: openarray[T]): XList[T] =
  result = new_xlist[T](get_item_type[T](result))

  for item in l:
      result.add(item)

proc toSeq*[T](l: XList[T]): seq[T] =
  result = @[]

  let len = l.xlist_len()

  for i in 0 ..< len:
    result.add(l.xlist_get(i, cast [ptr cint](nil)))

iterator items*[T](l: XList[T]): T =
  let len = l.xlist_len()

  for i in 0 ..< len:
      yield l.xlist_get(i, cast [ptr cint](nil))

proc `+`*(l1: ptr RawXList, l2: ptr RawXList):
               ptr RawXList {.importc: "xlist_plus", header: "con4m.h", hatc.}

proc `+=`*(l1: ptr RawXList, l2: ptr RawXList) {.importc: "xlist_plus_eq",
                                                 header: "con4m.h", hatc.}
proc contains*[T](x: XList[T], item: T): bool {.hatc, importc:"xlist_contains".}

proc new_tree*(s: Rich): Tree {.hatc, importc: "con4m_tree".}
proc add_node*(t: Tree, s: Rich): Tree {.hatc, importc: "tree_add_node".}
proc children*(t: Tree): XList[Tree] {.hatc, importc: "tree_children".}
proc get_child*(t: Tree, i: int): Tree {.hatc, importc: "tree_get_child".}
proc contents*(t: Tree): Rich {.hatc, importc: "tree_get_contents".}
proc len*(t: Tree): int {.hatc, importc: "tree_get_number_children".}
proc parent*(t: Tree): Tree {.hatc, importc: "tree_get_parent".}

proc install_default_styles*(){.hatc.}
# Raw interface, does not use markup. takes a C string and a syle name if any
proc con4m_rich*(s, t: pointer): Rich {.hatc.}

# This is the one that takes markup.
proc rich_lit*(s: cstring): Rich {.hatc.}

proc rich_len*(s: Rich): int {.hatc, importc: "string_codepoint_len".}
proc len*(s: Rich): int =
  return s.rich_len()

template rune_length*(s: Rich): int = s.rich_len()
proc con4m_grid*(r, c: cint, tt, th, td: cstring, hr, hc, stripe: cint):
               Grid {.nodecl, hatc.}
proc con4m_grid_to_str*(g: Grid, w: int): Rich {.hatc.}

proc grid_to_str*(g: Grid, w = terminalWidth()): Rich =
  g.con4m_grid_to_str(w)

proc grid_horizontal_flow*[T](l: XList[T], col: int, w: int, tstyle: cstring,
                           cstyle: cstring): Grid {.hatc.}

proc internal_grid_tree(l: Tree, zero: pointer):
                       Grid {.hatc, importc: "_grid_tree".}

proc grid_tree*(l: Tree): Grid =
  return internal_grid_tree(l, nil)

proc con4m_cstring*(s: cstring, l: int): Rich {.hatc.}
proc string_copy*(s: Rich): Rich {.hatc.}
proc string_concat*(s1: Rich, s2: Rich): Rich {.hatc.}

template `+`*(s1, s2: Rich): Rich =
  string_concat(s1, s2)

template `+=`*(s1: var Rich, s2: Rich) =
  s1 = s1 + s2

proc utf32_to_utf8*(s1: Rich): Rich {.hatc.}
proc utf8_to_utf32*(s1: Rich): Rich {.hatc.}
proc string_slice*(s: Rich, x, y: int): Rich {.hatc.}
proc utf8_repeat*(r: Rune, n: int): Rich {.hatc.}
proc utf32_repeat*(r: Rune, n: int): Rich {.hatc.}
proc string_strip*(s: Rich): Rich {.hatc, importc: "_string_strip".}
proc string_truncate*(s: Rich, n: int): Rich {.hatc,
                                               importc: "_string_truncate".}
proc string_join*(s: XList[Rich], sub: Rich):
                Rich {.hatc, importc: "_string_join".}
proc string_find*(s: Rich, sub: Rich) {.hatc, importc: "_string_find".}
proc string_split*(s, sub: Rich): ptr RawList {.hatc.}
proc split*[T](s, sub: Rich): XList[T] {.hatc, importc: "string_xsplit".}

proc con4m_repr*(o: pointer | Grid | TypeSpec):
               Rich {.importc: "con4m_value_obj_repr", cdecl, nodecl.}
proc full_repr*(o: pointer, s: TypeSpec, how: cint):
              Rich {.hatc, importc: "con4m_repr".}

proc con4m_repr*(p: pointer, t: TypeSpec): Rich =
  return full_repr(p, t, 0)

proc add_row*(g: Grid, p: pointer) {.importc: "grid_add_row", nodecl, cdecl.}

proc c4str*(s: string): Rich =
  if s == "":
    return nil
  result = con4m_cstring(cstring(s), s.len())

template text*(s: string): Rich =
  c4str(s)

proc c4str*(s: cstring): Rich =
  if s == "":
    return nil
  return con4m_cstring(s, s.len())

template c4*(s: string): Rich =
  con4m_cstring(s, s.len())

template r*(s: string): Rich =
  rich_lit(cstring(s))

template rich*(s: static[string]): Rich =
  rich_lit(cstring(s))

proc c4bool*(b: bool): cint =
  if b:
    return 1
  else:
    return 0

proc rich_new*(s: SomeString, t: SomeString = "td"): Rich =
  return con4m_rich(c4str(s), c4str(t))

template new_rich*(s: SomeString, t: SomeString = "td"): Rich =
  rich_new(s, t)


proc h1*(s: Somestring): Rich =
  return rich_new(s, "h1")

proc h2*(s: Somestring): Rich =
  return rich_new(s, "h2")

proc h3*(s: Somestring): Rich =
  return rich_new(s, "h3")

proc h4*(s: Somestring): Rich =
  return rich_new(s, "h4")

proc h5*(s: Somestring): Rich =
  return rich_new(s, "h5")

proc h6*(s: Somestring): Rich =
  return rich_new(s, "h6")

proc grid_new*(start_rows = 0, start_cols = 0, table_tag = "table",
               th_tag = "", td_tag = "", header_rows = 0, header_cols = 0,
               stripe = false): Grid =
    return con4m_grid(cint(start_rows), cint(start_cols), cstring(table_tag),
                      cstring(th_tag), cstring(td_tag), cint(header_rows),
                      cint(header_cols), c4bool(stripe))

proc cell*(s: string, tag: string = "td"): Grid =
  result = grid_new(table_tag = tag, td_tag = tag)
  add_row(result, rich_new(s, tag))

proc cell*(s: Rich, tag: string = "td"): Grid =
  result = grid_new(table_tag = tag, td_tag = tag)
  add_row(result, s)

proc cell*(s: Grid, tag: string): Grid =
  result = grid_new(start_rows = 1, start_cols = 1, table_tag = tag)
  add_row(result, s)

proc flow*(components: seq[Grid]): Grid =
  result = grid_new(start_rows = components.len(), table_tag = "flow")
  for item in components:
    add_row(result, item)

proc hatrack_dict_cleanup*(ctx: ptr RawDict) {.hatc.}
proc hatrack_dict_set_consistent_views*(ctx: ptr RawDict, yes: cint) {.hatc.}
proc hatrack_dict_get_consistent_views*(ctx: ptr RawDict): cint {.hatc.}
proc hatrack_dict_set_hash_offset*(ctx: ptr RawDict, offset: cint) {.hatc.}
proc hatrack_dict_get*(ctx: ptr RawDict, key: pointer, found: ptr cint):
                     pointer {.hatc.}
proc hatrack_dict_put*(ctx: ptr RawDict, key: pointer, value: pointer) {.hatc.}
proc hatrack_dict_replace*(ctx: ptr RawDict, key: pointer, value: pointer):
                     cint {.hatc.}
proc hatrack_dict_add*(ctx: ptr RawDict, key: pointer, value: pointer):
                     bool {.hatc.}
proc hatrack_dict_remove*(ctx: ptr RawDict, key: pointer): cint {.hatc.}
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

proc add*[K, V](d: Dict[K, V], key: K, value: V): bool =
    var
      p: pointer

    when V is SomeString:
      p = cast[pointer](c4str(value))
    elif V is seq:
      p = cast[pointer](toXList(value))
    elif V is ref:
      GC_ref(value)
      p = cast[pointer](value)
    elif V is ptr or V is SomeOrdinal or V is SomeFloat or V is pointer:
      p = cast[pointer](value)
    else:
      static:
        error("Value type not supported for dictionaries." & $(V))

    when K is SomeString:
      return hatrack_dict_add(d, c4str(key), p)
    elif K is SomeOrdinal:
      return hatrack_dict_add(d, cast[pointer](int64(key)), p)
    elif K is ref:
      GC_ref(key)
      return hatrack_dict_add(d, key, p)
    elif K is ptr or K is Rich or K is SomeFloat or K is pointer:
      return hatrack_dict_add(d, cast[pointer](key), p)
    else:
      static:
        error("Key type not supported for dictionaries: " & K)


proc con4m_new*[T](t: TypeSpec, p: pointer = nil):
              T {.hatc, importc: "_con4m_new".}

proc to_cstring*(r: Rich): cstring {.hatc.}

template to_nim_str*(r: Rich): string =
  $(to_cstring(r))

proc initDict*[K, V](d: var Dict[K, V]) =
  var m = d
  let t = get_con4m_type(m)
  d = con4m_new[Dict[K, V]](t)

proc `[]`*[K, V](d: Dict[K, V], item: K): V =
  var
    found: cint = 0
    p:     pointer = nil

  when K is SomeString:
    p = hatrack_dict_get(d, c4str(item), addr found)
  elif K is SomeOrdinal:
    p = hatrack_dict_get(d, cast[pointer](int64(item)), addr found)
  else:
    p = hatrack_dict_get(d, cast[pointer](item), addr found)

  if found == 0:
    raise newException(ValueError, "Dictionary key not found.")

  when V is cstring:
    return to_cstring(cast[Rich](p))
  elif V is string:
    return $(to_cstring(cast[Rich](p)))
  elif V is seq:
    var l = cast[XList[nim_type_hack(result)]](p)
    result = toSeq[nim_type_hack(result)](l)
  elif V is XList:
    return cast[V](p)
  elif V is List:
    return cast[V](p)
  else:
    return cast[V](result)

proc `[]=`*[K, V](d: Dict[K, V], key: K, value: V) =
    var
      p: pointer

    when V is string or V is cstring:
      p = cast[pointer](c4str(value))
    elif V is seq:
      p = cast[pointer](toXList(value))
    elif V is ref:
      GC_ref(value)
      p = cast[pointer](value)
    elif V is ptr or V is SomeOrdinal or V is SomeFloat or V is pointer:
      p = cast[pointer](value)
    else:
      static:
        error("Value type not supported for dictionaries: " & $(V))

    when K is SomeString:
      hatrack_dict_put(d, c4str(key), p)
    elif K is SomeOrdinal:
      hatrack_dict_put(d, cast[pointer](int64(key)), p)
    elif K is ref:
      GC_ref(key)
      hatrack_dict_put(d, key, p)
    elif K is ptr or K is SomeFloat or K is Rich or K is pointer:
      hatrack_dict_put(d, cast[pointer](key), p)
    else:
      static:
        error("Key type not supported for dictionaries: " & $(K))

proc lookup*[K, V](d: Dict[K, V], key: K): Option[V] =
  var
    found: cint = 0
    p:   pointer

  when K is SomeString:
    p = hatrack_dict_get(d, c4str(key), addr found)
  else:
    p = hatrack_dict_get(d, cast[pointer](key), addr found)

  if found == 0:
    return none(V)

  when V is cstring:
    return some($(to_cstring(cast[Rich](p))))
  elif V is string:
    return some($(to_cstring(cast[Rich](p))))
  elif V is seq:
    var l = cast[ptr XList](p)
    result = some(toSeq(l))
  else:
    result = some(cast[V](p))

proc toDict*[K, V](pairs: openarray[(K, V)]): Dict[K, V] =
  result.initDict()

  for (k, v) in pairs:
    result[k] = v

proc newDict*[K, V](): Dict[K, V] =
  initDict[K, V](result)

proc del*[K, V](d: Dict[K, V], key: K): bool {.discardable.} =
  when K is SomeString:
    return d.hatrack_dict_remove(c4str(key))
  else:
    return bool(d.hatrack_dict_remove(cast[pointer](key)))

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
      item.key = $(to_cstring(cast[Rich](uncast.key)))
    elif T is cstring:
      item.key = to_cstring(cast[Rich](uncast.key))
    elif T is SomeOrdinal:
      item.key = T(cast[int64](uncast.key))
    elif T is SomeFloat:
      item.key = T(cast[float](uncast.key))
    else: # T is SomeRef
      item.key = cast[T](uncast.key)

    when V is string:
      item.value = $(to_cstring(cast[Rich](uncast.value)))
    elif V is cstring:
      item.value = to_cstring(cast[Rich](uncast.value))
    elif V is SomeOrdinal:
      item.value = V(cast[int64](uncast.value))
    elif V is SomeFloat:
      item.value = V(cast[float](uncast.value))
    elif V is seq:
      var l = cast[XList[nimListType(item.value)]](p)
      item.value = toSeq(l)
    elif V is SomeRef:
      item.value = cast[V](uncast.value)
    else:
      item.value = cast[V](uncast.value)

    result.add(item)

proc keys*[T, V](d: Dict[T, V], sort = false): seq[T] =
  for item in d.items(sort):
    result.add(item[0])

proc values*[T, V](d: Dict[T, V], sort = false): seq[V] =
  for item in d.items(sort):
    result.add(item[1])

proc contains*[T, V](d: Dict[T, V], item: T): bool =
  return d.lookup(item).isSome()

proc `$`*[T, V](d: Dict[T, V]): string =
  var s: Rich = con4m_repr(cast[pointer](d))

  return $(to_cstring(s))

proc register_thread*() {.cdecl, importc: "mmm_register_thread" .}

proc set_style*(r: Rich, s: TextStyle) {.hatc, importc: "string_set_style".}
proc layer_style*(r: Rich, toAdd, toRm: TextStyle = 0) {.hatc, importc: "string_layer_style".}

proc set_default_text_style*(s: TextStyle) {.hatc,
                                             importc: "set_default_style".}
proc new_text_style*(): TextStyle =
  return 0

proc raw_add_bold*(v: TextStyle): TextStyle {.hatc, importc: "add_bold".}
proc add_bold*(v: var TextStyle) =
  v = raw_add_bold(v)

proc raw_remove_bold*(v: TextStyle): TextStyle {.hatc, importc: "remove_bold".}
proc remove_bold*(v: var TextStyle) =
  v = raw_remove_bold(v)

proc raw_add_inverse*(v: TextStyle): TextStyle {.hatc, importc: "add_inverse".}
proc add_inverse*(v: var TextStyle) =
  v = raw_add_inverse(v)

proc raw_remove_inverse*(v: TextStyle):
                       TextStyle {.hatc, importc: "remove_inverse".}
proc remove_inverse*(v: var TextStyle) =
  v = raw_remove_inverse(v)

proc raw_add_strikethrough*(v: TextStyle):
                          TextStyle {.hatc, importc: "add_strikethrough".}
proc add_strikethrough*(v: var TextStyle) =
  v = raw_add_strikethrough(v)

proc raw_remove_strikethrough*(v: TextStyle):
                             TextStyle {.hatc, importc: "remove_strikethrough".}
proc remove_strikethrough*(v: var TextStyle) =
  v = raw_remove_strikethrough(v)

proc raw_add_italic*(v: TextStyle): TextStyle {.hatc, importc: "add_italic".}
proc add_italic*(v: var TextStyle) =
  v = raw_add_italic(v)

proc raw_remove_italic*(v: TextStyle):
                      TextStyle {.hatc, importc: "remove_italic".}
proc remove_italic*(v: var TextStyle) =
  v = raw_remove_italic(v)

proc raw_add_underline*(v: TextStyle):
                      TextStyle {.hatc, importc: "add_underline".}
proc add_underline*(v: var TextStyle) =
  v = raw_add_underline(v)

proc raw_remove_underline*(v: TextStyle):
                         TextStyle {.hatc, importc: "remove_underline".}
proc remove_underline*(v: var TextStyle) =
  v = raw_remove_underline(v)

proc raw_add_double_underline*(v: TextStyle):
                             TextStyle {.hatc, importc: "add_double_underline".}
proc add_double_underline*(v: var TextStyle) =
  v = raw_add_double_underline(v)

proc raw_remove_double_underline*(v: TextStyle):
                         TextStyle {.hatc, importc: "remove_double_underline".}
proc remove_double_underline*(v: var TextStyle) =
  v = raw_remove_double_underline(v)

proc raw_add_upper_case*(v: TextStyle):
                       TextStyle {.hatc, importc: "add_upper_case".}
proc add_upper_case*(v: var TextStyle) =
  v = raw_add_upper_case(v)

proc raw_add_lower_case*(v: TextStyle):
                       TextStyle {.hatc, importc: "add_lower_case".}
proc add_lower_case*(v: var TextStyle) =
  v = raw_add_lower_case(v)

proc raw_add_title_case*(v: TextStyle):
                       TextStyle {.hatc, importc: "add_title_case".}
proc add_title_case*(v: var TextStyle) =
  v = raw_add_title_case(v)

proc raw_remove_case*(v: TextStyle): TextStyle {.hatc, importc: "remove_case".}

proc remove_case*(v: var TextStyle) =
  v = raw_remove_case(v)

proc raw_add_fg_color*(v: TextStyle, color: Color):
                       TextStyle {.hatc, importc: "add_fg_color".}

proc raw_add_bg_color*(v: TextStyle, color: Color):
                       TextStyle {.hatc, importc: "add_bg_color".}

proc raw_apply_fg_color*(v: TextStyle, s: cstring):
                       TextStyle {.hatc, importc: "apply_fg_color".}

proc raw_apply_bg_color*(v: TextStyle, s: cstring):
                       TextStyle {.hatc, importc: "apply_bg_color".}

proc raw_remove_fg_color*(v: TextStyle):
                        TextStyle {.hatc, importc: "remove_fg_color".}

proc raw_remove_bg_color*(v: TextStyle):
                        TextStyle {.hatc, importc: "remove_bg_color".}

proc raw_remove_all_color*(v: TextStyle):
                         TextStyle {.hatc, importc: "remove_all_color".}

proc bold*(r: Rich): Rich =
  var ts = TextStyle(0)
  ts.add_bold()
  r.layer_style(ts)
  return r

proc bold*(s: string): Rich =
  return bold(c4str(s))

proc em*(r: Rich): Rich =
  var ts = TextStyle(0)
  ts.add_italic()
  r.layer_style(ts)
  return r

proc em*(s: string): Rich =
  return em(c4str(s))

proc apply_style*(r: Rich, style: TextStyle) {.hatc,
                                               importc: "string_set_style".}

proc set_render_style(name: cstring,
                      style: RenderStyle) {.hatc, importc: "set_style".}
proc set_style*(style: RenderStyle, name: string) =
  set_render_style(cstring(name), style)


proc new_render_style*(): RenderStyle {.hatc.}
proc copy_render_style*(style: RenderStyle): RenderStyle {.hatc.}
proc get_string_style*(style: RenderStyle): TextStyle {.hatc.}
proc set_fg_color*(style: RenderStyle, c: Color) {.hatc.}
proc set_bg_color*(style: RenderStyle, c: Color) {.hatc.}
proc bold_on*(style: RenderStyle) {.hatc.}
proc bold_off*(style: RenderStyle) {.hatc.}
proc italic_on*(style: RenderStyle) {.hatc.}
proc italic_off*(style: RenderStyle) {.hatc.}
proc strikethru_on*(style: RenderStyle) {.hatc.}
proc strikethru_off*(style: RenderStyle) {.hatc.}
proc underline_off*(style: RenderStyle) {.hatc.}
proc underline_on*(style: RenderStyle) {.hatc.}
proc double_underline_on*(style: RenderStyle) {.hatc.}
proc inverse_on*(style: RenderStyle) {.hatc.}
proc inverse_off*(style: RenderStyle) {.hatc.}
proc casing_off*(style: RenderStyle) {.hatc.}
proc lowercase_on*(style: RenderStyle) {.hatc.}
proc uppercase_on*(style: RenderStyle) {.hatc.}
proc titlecase_on*(style: RenderStyle) {.hatc.}
proc set_border_theme*(style: RenderStyle, name: cstring) {.hatc.}
proc set_flex_size*(style: RenderStyle, size: int) {.hatc.}
proc set_absolute_size*(style: RenderStyle, size: int) {.hatc.}
proc set_size_range*(style: RenderStyle, lo, hi: cint) {.hatc.}
proc set_fit_to_text*(style: RenderStyle) {.hatc.}
proc set_auto_size*(style: RenderStyle) {.hatc.}
proc set_size_as_percent*(style: RenderStyle, pct: float, round: int8) {.hatc.}
proc set_top_pad*(style: RenderStyle, pad: int8) {.hatc.}
proc set_bottom_pad*(style: RenderStyle, pad: int8) {.hatc.}
proc set_left_pad*(style: RenderStyle, pad: int8) {.hatc.}
proc set_right_pad*(style: RenderStyle, pad: int8) {.hatc.}
proc set_wrap_hang*(style: RenderStyle, hang: int8) {.hatc.}
proc disable_line_wrap*(style: RenderStyle) {.hatc.}
proc set_pad_color*(style: RenderStyle, color: Color) {.hatc.}
proc clear_fg_color*(style: RenderStyle) {.hatc.}
proc clear_bg_color*(style: RenderStyle) {.hatc.}
proc set_alignment*(style: RenderStyle, alignment: Alignment) {.hatc.}
proc set_borders*(style: RenderStyle, borders: BorderSet) {.hatc.}
proc is_bg_color_on*(style: RenderStyle): bool {.hatc.}
proc is_fg_color_on*(style: RenderStyle): bool {.hatc.}
proc get_fg_color*(style: RenderStyle): Color {.hatc.}
proc get_bg_color*(style: RenderStyle): Color {.hatc.}
proc get_pad_style*(style: RenderStyle): TextStyle {.hatc.}
proc style_exists*(name: cstring): bool {.hatc.}
proc apply_column_style(g: Grid, col: cint,
                        tag: cstring) {.hatc, importc: "set_column_style".}
proc apply_row_style(g: Grid, col: cint,
                        tag: cstring) {.hatc, importc: "set_row_style".}

proc set_row_style*(g: Grid, col: int, tag: string) =
  g.apply_row_style(cint(col), cstring(tag))

proc set_col_style*(g: Grid, col: int, tag: string) =
  g.apply_row_style(cint(col), cstring(tag))

proc set_col_props*(g: Grid, col: int, style: RenderStyle) {.hatc,
                                                importc: "set_column_props".}
proc set_row_props*(g: Grid, row: int, style: RenderStyle) {.hatc.}

proc new_buffer*(l: int): Buffer {.cdecl, importc: "con4m_buffer".}
proc new_buffer*(s: string): Buffer =
  var l = s.len()
  result = new_buffer(l)

  if l != 0:
    copyMem(result.data, addr s[0], l)

proc buffer_join*(l: XList[Buffer], joiner: Buffer = nil): Buffer {.hatc.}

proc stream_raw_read*(s: CStream, l: int, buf: cstring): C4Obj {.hatc.}
proc stream_raw_write*(s: CStream, l: int, buf: cstring): cuint {.hatc.}
proc stream_write_object*(s: CStream, obj: C4Obj):
                        int {.hatc, importc: "_stream_write_object".}
proc stream_at_eof*(s: CStream): bool {.hatc.}
proc stream_get_location*(s: CStream): int {.hatc.}
proc stream_set_location*(s: CStream, n: int) {.hatc.}
proc stream_close*(s: CStream) {.hatc.}
proc stream_flush*(s: CStream) {.hatc.}
proc stream_read*(s: CStream, l: int): C4Obj {.hatc.}
proc string_instream*(s: Rich): CStream {.hatc.}
proc buffer_instream*(b: Buffer): CStream {.hatc.}
proc buffer_outstream*(b: Buffer): CStream {.hatc.}
proc buffer_iostream*(b: Buffer): CStream {.hatc.}
proc file_instream*(fname: Rich, outtype: int): CStream {.hatc.}
proc file_outstream*(fname: Rich, can_create, append: cint): CStream {.hatc.}
proc file_iostream*(fname: Rich, can_create: cint): CStream {.hatc.}

proc con4m_marshal*[T](o: T, s: CStream){.hatc.}
proc con4m_unmarshal*[T](s: CStream): T {.hatc.}
proc con4m_sub_marshal*[T](o: T, s: CStream, memos: Dict[int, pointer],
                        mid: ptr int) {.hatc.}
proc con4m_sub_unmarshal*[T](s: CStream, memos: Dict[int, pointer]): T {.hatc.}

proc marshal_cstring*(str: cstring, stream: CStream) {.hatc.}
proc unmarshal_cstring*(s: CStream): cstring {.hatc.}
proc marshal_i64*(i: int, s: CStream) {.hatc.}
proc marshal_u64*(i: uint, s: CStream) {.hatc.}
proc unmarshal_i64*(s: CStream): int {.hatc.}
proc unmarshal_u64*(s: CStream): uint {.hatc.}
proc marshal_i32*(i: cint, s: CStream) {.hatc.}
proc marshal_u32*(i: cuint, s: CStream) {.hatc.}
proc unmarshal_i32*(s: CStream): cint {.hatc.}
proc unmarshal_u32*(s: CStream): cuint {.hatc.}
proc marshal_i16*(i: int16, s: CStream) {.hatc.}
proc marshal_u16*(i: uint16, s: CStream) {.hatc.}
proc unmarshal_i16*(s: CStream): int16 {.hatc.}
proc unmarshal_u16*(s: CStream): uint16 {.hatc.}
proc marshal_i8*(i: int8, s: CStream) {.hatc.}
proc marshal_u8*(i: uint8, s: CStream) {.hatc.}
proc unmarshal_i8*(s: CStream): int8 {.hatc.}
proc unmarshal_u8*(s: CStream): uint8 {.hatc.}
proc marshal_bool*(b: bool, s: CStream) {.hatc.}
proc unmarshal_bool*(s: CStream): bool {.hatc.}
proc con4m_tuple*(t: TypeSpec): CTuple {.importc, cdecl.}

proc tuple_set*(x: CTuple, n: int, p: pointer) {.hatc.}
proc tuple_get*(x: CTuple, n: int): pointer {.hatc.}

proc `[]=`*(x: CTuple, ix: int, v: pointer) =
    tuple_set(x, ix, v)

template `[]`*(x: CTuple, ix: int): pointer =
    tuple_get(x, ix)

proc con4m_mixed*(t: TypeSpec): Mixed {.importc, cdecl.}

proc con4m_print(p: Rich | Grid | TypeSpec, n: pointer = nil) {.hatc, importc: "_print".}
proc print_err*(p: pointer) {.importc, cdecl.}
proc box_i64*(n: int): ptr int {.hatc.}
proc box_u64*(n: int): ptr uint {.hatc.}
proc box_i32*(n: cint): ptr cint {.hatc.}
proc box_u32*(n: cuint): ptr cuint {.hatc.}
proc box_i8*(n: int8): ptr int8 {.hatc.}
proc box_u8*(n: uint8): ptr uint8 {.hatc.}


proc print*(n: Rich | Grid | TypeSpec) =
  con4m_print(n)

# Not sure if I'll need this yet.
proc pass_kargs(n: cint, l: varargs[pointer]): pointer {.hatc.}


proc box*[T](n: T): ptr T =
  when T is int:
    return box_i64(n)
  elif T is uint:
    return box_u64(n)
  elif T is cint or T is Rune:
    return box_i32(cast[cint](n))
  elif T is cuint:
    return box_u32(n)
  elif T is int8:
    return box_i8(n)
  elif T is uint8  or T is char:
    return box_u8(cast[uint8](n))
once:
  # Auto-register the main thread.
  registerThread()

proc con4m_eq*(t: TypeSpec, o1, o2: pointer): bool {.hatc.}
proc con4m_lt*(t: TypeSpec, o1, o2: pointer): bool {.hatc.}
proc con4m_gt*(t: TypeSpec, o1, o2: pointer): bool {.hatc.}

proc getTid*(t: TypeSpec): TypeSpec {.hatc, importc: "global_resolve_type".}

template followForwards*(t: TypeSpec): TypeSpec =
  t.getTid()

proc to_string*(o: pointer | Grid | TypeSpec): string =
  con4m_repr(o).to_nim_str()

proc copy_type*(t: TypeSpec): TypeSpec {.hatc, importc: "global_copy".}
template atom*(s: string): Rich =
  c4str(s)

proc fg_color*(s: Rich, color: string): Rich =
  var style = new_text_style()
  style = style.raw_apply_fg_color(cstring(color))
  apply_style(s, style)

template fg_color*(s: string, color: string): Rich =
  fg_color(c4Str(s), color)

proc fg_color*(style: var TextStyle, color: string) =
  style = style.raw_apply_fg_color(cstring(color))

proc is_int_type*(t: TypeSpec): bool {.hatc, importc: "tspec_is_int_type".}
proc get_promotion_type*(t1, t2: TypeSpec, warning: ptr cint): TypeSpec {.hatc.}

proc con4m_simple_lit*(raw: pointer, st: cint, litmod: cstring,
                       err: ptr LitError): pointer {.hatc.}

proc isNumericBuiltin*(t: TypeSpec): bool =
  let n = cast[LibTid](t.base_type_id())
  if n >= C4_I8 and n <= C4_F64:
    return true
  else:
    return false

proc isIntBuiltin*(t: TypeSpec): bool =
  let n = cast[LibTid](t.base_type_id())
  if n >= C4_I8 and n < C4_F32:
    return true
  else:
    return false


proc isFloatBuiltin*(t: TypeSpec): bool =
  let n = cast[LibTid](t.base_type_id())
  if n >= C4_F32 and n <= C4_F64:
    return true
  else:
    return false

proc isValueType*(t: TypeSpec): bool =
  let n = cast[LibTid](t.base_type_id())
  if n >= C4_TYPE_ERROR and n <= C4_F64:
    return true
  else:
    return false


proc isBasicType*(t: TypeSpec): bool =
  return t.get_type_kind() in [BT_PRIMATIVE, BT_INTERNAL]

proc isTypeVar*(t: TypeSpec): bool =
  return t.get_type_kind() == BT_TVAR

proc isDictType*(t: TypeSpec): bool =
  return t.get_type_kind() == BT_DICT

proc getDataType*(t: TypeSpec): int =
  return t.base_type_id()

proc isFloatType*(t: TypeSpec): bool =
  return cast[LibTid](t.base_type_id()) in [C4_F32, C4_F64]

proc marshal_obj*(obj: C4Obj): Buffer {.hatc, importc: "con4m_marshal_to_buf".}
proc unmarshal_obj*(mem: cstring, l: int):
                  C4Obj {.hatc, importc: "con4m_mem_unmarshal".}

proc isVarargs*(t: TypeSpec): bool =
  return (t.details.flags and 1) != 0

proc getNumFormals*(t: TypeSpec): int =
  assert t.get_type_kind() == BT_FUNC
  return t.num_params() - 1

proc marshal_type_environment*(s: CStream, d: Dict[int, pointer],
                               p: ptr int) {.importc, cdecl.}
proc unmarshal_type_environment*(s: CStream, d: Dict[int, pointer]) {.importc, cdecl.}

proc con4m_can_cast*(tfrom, tto: TypeSpec):
                   bool {.hatc, importc: "con4m_can_coerce".}
proc con4m_cast*(o: pointer, tfrom, tto: TypeSpec):
              pointer {.hatc, importc: "con4m_coerce".}

proc call_cast*(v: pointer, tfrom, tto: TypeSpec, err: var string): pointer =
  if not con4m_can_cast(tfrom, tto):
    err = "CannotCast"
    return nil

  return con4m_cast(v, tfrom, tto)

proc instantiate_container*(t: TypeSpec, v: seq[pointer]): pointer =
  case cast[LibTid](t.base_type_id())
  of C4_LIST:
    var l: List[pointer] = cast[List[pointer]](
      con4m_flexarray[pointer](t, v.len()))
    for i, item in v:
      l.list_set(i, item)

    result = cast[pointer](l)

  of C4_TUPLE:
    var tup: CTuple = con4m_tuple(t)

    for i, item in v:
      tup.tuple_set(i, item)

    result = cast[pointer](tup)

  of C4_DICT:
    var dict = con4m_new[Dict[pointer, pointer]](t)
    var i = 0

    while i < v.len():
      dict[v[i]] = v[i+1]
      i += 2

    result = cast[pointer](dict)

  else:
    raise newException(ValueError,
                       "Type not a currently instantiable container type.")



proc con4m_len*(o: pointer): int {.hatc.}
proc con4m_add*(o1, o2: pointer): pointer {.hatc.}
proc con4m_sub*(o1, o2: pointer): pointer {.hatc.}
proc con4m_mul*(o1, o2: pointer): pointer {.hatc.}
proc con4m_div*(o1, o2: pointer): pointer {.hatc.}
proc con4m_mod*(o1, o2: pointer): pointer {.hatc.}
proc con4m_index_set*(o1, o2, o3: pointer) {.hatc.}
proc con4m_index_get*(o1, o2: pointer): pointer {.hatc.}
proc con4m_slice_get*(o1: pointer, s, f: int): pointer {.hatc.}
proc con4m_slice_set*(o1: pointer, s, f: int, n: pointer) {.hatc.}
proc con4m_copy*(o1: pointer): pointer {.hatc, importc: "con4m_copy_object".}

proc toRichXList*(l: seq[string] | seq[pointer]): XList[Rich] =
  result = new_xlist[Rich]()

  for item in l:
    result.add(r(item))

proc toSeqStr*(l: XList[Rich] | seq[Rich]): seq[string] =
  for item in l:
    result.add(item.toNimStr())

proc alloc_marshal_memos*(): Dict[int, pointer] {.hatc.}
proc alloc_unmarshal_memos*(): Dict[int, pointer] {.hatc.}
