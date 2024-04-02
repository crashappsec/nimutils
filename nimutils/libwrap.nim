{.pragma: hatc, cdecl, nodecl, importc.}

import std/terminal, unicode

type
  RawList* {.final, pure, header: "con4m.h", importc: "flexarray_t".} = object
  RawXList* {.final, pure, header: "con4m.h", importc: "xlist_t".} = object
  RawDict* {.final, pure.} = object
  # For now, we will not parameterize trees, just make them all take strings.
  Tree* = pointer
  Grid* = pointer
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

  StackBox*[T] = ref object of RootRef
    ownedByNim*: bool
    contents*:   T
  SomeString*  = string | cstring # String box.
  SomeRef*     = ref or pointer  # Not boxed.
  SomeNumber*  = SomeOrdinal or SomeFloat
  RawItem*     = object
    key*:   pointer
    value*: pointer
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

  TypeSpecObj* {.final, pure.} = object
  TypeSpec* = ptr TypeSpecObj

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
    C4_FUNCDEF       = 40,
    C4_REF           = 41,
    C4_GENERIC       = 42,

const
  BORDER_TOP          = 0x01
  BORDER_BOTTOM       = 0x02
  BORDER_LEFT         = 0x04
  BORDER_RIGHT        = 0x08
  INTERIOR_HORIZONTAL = 0x10
  INTERIOR_VERTICAL   = 0x20

proc ansi_render*(s: Rich, f: File) {.hatc.}
proc ansi_render_to_width*(s: Rich, w, h: cint, f: File) {.hatc.}

# Type system.

proc resolve_type_aliases*(t: TypeSpec, env: TypeEnv): TypeSpec {.hatc.}
proc type_spec_is_concrete*(t: TypeSpec): bool {.hatc.}
proc type_spec_copy*(t: TypeSpec, env: TypeEnv): TypeSpec {.hatc.}
proc get_builtin_type*(n: LibTid): TypeSpec {.hatc.}
proc unify*(t1: TypeSpec, t2: TypeSpec, env: TypeEnv) {.hatc.}
proc lookup_type_spec*(id: uint, env: TypeEnv): TypeSpec {.hatc.}
proc tspec_list*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_xlist*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_queue*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_ring*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_stack*(t: TypeSpec): TypeSpec {.hatc.}
proc tspec_dict*(t1, t2: TypeSpec): TypeSpec {.hatc.}
proc tspec_set*(t1: TypeSpec): TypeSpec {.hatc.}
proc tspec_tuple*(n: int, l: varargs[TypeSpec]): TypeSpec {.hatc.}
proc tspec_fn*(ret: TypeSpec, n: int, l: varargs[TypeSpec]): TypeSpec {.hatc.}
proc tspec_varargs_fn*(ret: TypeSpec, n: int,
                       l: varargs[TypeSpec]): TypeSpec {.hatc.}

proc get_builtin_type*[T](x: T = default(T)): TypeSpec

proc nim_type_hack_base*[T](item: List[T] | XList[T]): auto =
  return default(T)

proc nim_type_hack*[T](item: List[T] | XList[T]): auto =
  return typeof(nim_type_hack_base[T](item))

proc nim_item_type*[T](item: List[T] | XList[T]): TypeSpec =
  return get_builtin_type[nim_type_hack[T](item)]()

proc get_key_type*[K, V](item: Dict[K, V]): TypeSpec =
  return get_builtin_type[nim_type_hack[K](item)]()


proc get_val_type*[K, V](item: Dict[K, V]): TypeSpec =
  return get_builtin_type[nim_type_hack[V](item)]()

proc get_builtin_type*[T](x: T = default(T)): TypeSpec =
  var p: pointer = nil

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
  elif T is XList:
    return tspec_xlist(get_xlist_type[T](cast[T](p)))
  elif T is List:
    return tspec_list(get_nim_item_type[T](cast[T](p)))
  elif T is Dict:
    return tspec_dict(get_key_type[T](cast[T](p)), get_val_type[T](cast[T](p)))
  elif T is ref or T is ptr:
    return get_builtin_type(C4_REF)

proc con4m_xlist*(t: TypeSpec): ptr RawXList {.hatc.}

proc new_xlist*[T](t: TypeSpec = nil): XList[T] =
  return cast[XList[T]](con4m_xlist(get_builtin_type[T]()))

proc xlist_get*[T](l: XList[T], ix: int, err: ptr cint): T {.hatc.}

proc xlist_len*[T](t: XList[T]): int {.hatc.}

proc xlist_append*[T](t: Xlist[T], v: T) {.hatc.}

proc xlist_set[T](t: XList[T], ix: int, v: pointer): cint {.hatc.}

proc `[]`*[T](l: XList[T], ix: int): T {.hatc.} =
  var err: cint = 0

  result = xlist_get[T](l, ix, addr err)
  if err != 0:
    raise newException(ValueError, "Invalid index.")

proc `[]=`*[T](l: XList[T], ix: int, v: pointer) =
    var err = xlist_set(l, ix, v)

    if err != 0:
      raise newException(ValueError, "Invalid index.")

import strutils
proc toXList*[T](l: seq[T]): ptr RawXList =
  result = new_xlist[T]()
  for item in l:
      xlist_append(result, item)

proc toSeq*[T](l: XList[T]): seq[T] =
  result = @[]

  let l = l.xlist_len()

  for i in 0 ..< l:
    result.add(l.xlist_get(i, nil))

proc `+`*(l1: ptr RawXList, l2: ptr RawXList):
               ptr RawXList {.importc: "xlist_plus", header: "con4m.h", hatc.}

proc `+=`*(l1: ptr RawXList, l2: ptr RawXList) {.importc: "xlist_plus_eq", header: "con4m.h", hatc.}


proc new_tree*(s: Rich): Tree {.hatc, importc: "con4m_tree".}
proc add_node*(t: Tree, s: Rich): Tree {.hatc, importc: "tree_add_node".}
proc children*(t: Tree): XList[Tree] {.hatc, importc: "tree_children".}
proc get_child*(t: Tree, i: int): Tree {.hatc, importc: "tree_get_child".}
proc contents*(t: Tree): Rich {.hatc, importc: "tree_get_contents".}
proc len*(t: Tree): int {.hatc, importc: "tree_get_number_children".}
proc parent*(t: Tree): Tree {.hatc, importc: "tree_get_parent".}

proc install_default_styles*(){.hatc.}
proc dict_new*(kt: cint): ptr RawDict {.hatc, importc: "hatrack_dict_new", header: "con4m.h".}
proc con4m_rich*(s, t: pointer): Rich {.hatc.}
proc con4m_grid*(r, c: cint, tt, th, td: cstring, hr, hc, stripe: cint):
               Grid {.nodecl, hatc.}
proc grid_to_str*(g: Grid, w: int): Rich {.hatc, importc: "nim_grid_to_str".}
proc grid_horizontal_flow*[T](l: XList[T], col: int, w: int, tstyle: cstring,
                           cstyle: cstring): Grid {.hatc.}

proc internal_grid_tree(l: Tree, zero: pointer):
                       Grid {.hatc, importc: "_grid_tree".}

proc grid_tree*(l: Tree): Grid =
  return internal_grid_tree(l, nil)

proc con4m_cstring*(s: cstring, l: int): Rich {.hatc.}
proc string_copy*(s: Rich): Rich {.hatc.}
proc string_concat*(s1: Rich, s2: Rich): Rich {.hatc.}
proc utf32_to_utf8*(s1: Rich): Rich {.hatc.}
proc utf8_to_utf32*(s1: Rich): Rich {.hatc.}
proc string_slice*(s: Rich, x, y: int): Rich {.hatc.}
proc utf8_repeat*(r: Rune, n: int): Rich {.hatc.}
proc utf32_repeat*(r: Rune, n: int): Rich {.hatc.}
proc string_strip*(s: Rich): Rich {.hatc, importc: "_string_strip".}
proc string_truncate*(s: Rich, n: int): Rich {.hatc,
                                               importc: "_string_truncate".}
proc string_join*(s: ptr RawXlist, sub: Rich):
                Rich {.hatc, importc: "_string_join".}
proc string_find*(s: Rich, sub: Rich) {.hatc, importc: "_string_find".}
proc string_split*(s, sub: Rich): ptr RawList {.hatc.}
proc con4m_repr*(o: pointer | Grid): Rich {.importc: "con4m_value_obj_repr", cdecl.}
proc add_row*(g: Grid, p: pointer) {.importc: "grid_add_row", nodecl, cdecl.}

proc c4str*(s: string): Rich =
  if s == "":
    return nil
  result = con4m_cstring(cstring(s), s.len())

proc c4str*(s: cstring): Rich =
  if s == "":
    return nil
  return con4m_cstring(s, s.len())

proc c4bool*(b: bool): cint =
  if b:
    return 1
  else:
    return 0

proc rich_new*(s: SomeString, t: SomeString = "td"): Rich =
  return con4m_rich(c4str(s), c4str(t))

proc rich_print*(s: Rich, file = stdout) =
  ansi_render(s, file)

proc grid_new*(start_rows = 0, start_cols = 0, table_tag = "table",
               th_tag = "", td_tag = "", header_rows = 0, header_cols = 0,
               stripe = false): Grid =
    return con4m_grid(cint(start_rows), cint(start_cols), cstring(table_tag),
                      cstring(th_tag), cstring(td_tag), cint(header_rows),
                      cint(header_cols), c4bool(stripe))

proc cell*(s: string, tag: string = "td"): Grid =
  result = grid_new(table_tag = tag, td_tag = tag)
  add_row(result, rich_new(s, tag))

proc flow*(components: seq[Grid]): Grid =
  result = grid_new(start_rows = components.len(), table_tag = "flow")
  for item in components:
    add_row(result, item)

proc toStackBox*[T](o: T): StackBox[T] =
  result = StackBox[T](contents: o, ownedByNim: true)
  GC_ref(result)

proc unboxStackObj*[T](box: StackBox[T]): T =
  return box.contents

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
                     cint {.hatc.}
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

proc register_thread*() {.cdecl, importc: "mmm_register_thread" .}

proc apply_style*(r: Rich, s: TextStyle) {.hatc, importc: "string_apply_style".}
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

proc raw_add_fg_color*(v: TextStyle, r, g, b: uint8):
                       TextStyle {.hatc, importc: "add_fg_color".}

proc raw_add_bg_color*(v: TextStyle, r, g, b: uint8):
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

proc fg_color*(v: var TextStyle, s: string) =
  v = raw_apply_fg_color(v, cstring(s))

proc fg_color*(v: var TextStyle, r, g, b: uint8) =
  v = raw_add_fg_color(v, r, g, b)

proc fg_color*(v: var TextStyle, n: Color) =
  fg_color(v,
           uint8((n shl 16) and 0xff),
           uint8((n shl 8) and 0xff),
           uint8(n and 0xff))

proc bg_color*(v: var TextStyle, s: string) =
  v = raw_apply_bg_color(v, cstring(s))

proc bg_color*(v: var TextStyle, r, g, b: uint8) =
  v = raw_add_bg_color(v, r, g, b)

proc bg_color*(v: var TextStyle, n: Color) =
  bg_color(v,
           uint8((n shl 16) and 0xff),
           uint8((n shl 8) and 0xff),
           uint8(n and 0xff))

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

once:
  # Auto-register the main thread.
  registerThread()
