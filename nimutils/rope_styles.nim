##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import unicode, tables, rope_base, rope_construct, options, random, hexdump

proc newStyle*(fgColor = "", bgColor = "", overflow = OIgnore, hang = -1,
               lpad = -1, rpad = -1, casing = CasingIgnore,
               tmargin = -1, bmargin = -1, bold = BoldIgnore,
               inverse = InverseIgnore, strikethru = StrikeThruIgnore,
               italic = ItalicIgnore, underline = UnderlineIgnore,
               bulletChar = Rune(0x0000), borders: openarray[BorderOpts] = [],
               boxStyle: BoxStyle = nil, align = AlignIgnore): FmtStyle =
    ## A swiss-army-knife interface for getting the exact style you're
    ## looking for.
    ##
    ## Styles get pushed and popped while walking through the
    ## underlying DOM; when multiple styles are pushed at once,
    ## they're *merged*, with anything in the newer style overriding
    ## anything it defines.
    ##
    ## For the parameters, the default values all mean "inherit from
    ## the existing style". Anything you specify beyond the defaults
    ## will lead to an override.
    ##
    ## Internally, individual style objects use Option[]s to know what
    ## to override or not.
    ##
    ## Also, you need to consider the order in which style objects get
    ## applied. There's usually a default style in place when we start
    ## the pre-rendering process.
    ##
    ## Then, as we get to individual nodes, we look up the current
    ## active style mapped to the for the node type (which map to
    ## common html tags, and are interchangably called tags). If
    ## there's a style, we merge it in (popping / unmerging it at the
    ## end of processing the node).
    ##
    ## Then, if the node is in a 'class' (akin to an HTML class), and
    ## there's a stored style for that class, we apply its overrides
    ## next.
    ##
    ## Finally, if the node has an 'id' set, we apply any style
    ## associated with the id. Then, we render.
    ##
    ## If you use the style API on rope objects, it works by mutating
    ## the overrides, using the style associated w/ the node's ID
    ## (creating a random ID if one isn't set).
    ##
    ## This means they take higher precidence than anything else, BUT,
    ## the effects you set could still be masked by sub-nodes in the
    ## tree. For instance, if you set something on a `table` node, the
    ## saved styles for `tbody`, `tr` and `th`/`td` nodes can end up
    ## masking what you were trying to set.
    ##
    ## The overall style for tags, classes and IDs can be set with
    ## `setStyle()` and retrieved with `getStyle()`.

    result = FmtStyle()

    if fgColor != "":
      result.textColor = some(fgColor)
    if bgColor != "":
      result.bgColor   = some(bgColor)
    if overflow != OIgnore:
      result.overFlow = some(overflow)
    if hang != -1:
      result.hang = some(hang)
    if lpad >= 0:
      result.lpad = some(lpad)
    if rpad >= 0:
      result.rpad = some(rpad)
    if tmargin >= 0:
      result.tmargin = some(tmargin)
    if bmargin >= 0:
      result.bmargin = some(bmargin)
    if casing != CasingIgnore:
      result.casing = some(casing)
    case bold
    of BoldOn:
      result.bold = some(true)
    of BoldOff:
      result.bold = some(false)
    else:
      discard
    case inverse
    of InverseOn:
      result.inverse = some(true)
    of InverseOff:
      result.inverse = some(false)
    else:
      discard
    case strikethru
    of StrikeThruOn:
      result.strikethrough = some(true)
    of StrikeThruOff:
      result.strikethrough = some(false)
    else:
      discard
    case italic
    of ItalicOn:
      result.italic = some(true)
    of ItalicOff:
      result.italic = some(false)
    else:
      discard
    if underline != UnderlineIgnore:
      result.underlineStyle = some(underline)
    if bulletChar != Rune(0x0000):
      result.bulletChar = some(bulletChar)

    if len(borders) != 0:
      for item in borders:
        case item
        of BorderNone:
          result.useTopBorder           = some(false)
          result.useBottomBorder        = some(false)
          result.useLeftBorder          = some(false)
          result.useRightBorder         = some(false)
          result.useVerticalSeparator   = some(false)
          result.useHorizontalSeparator = some(false)
        of BorderTop:
          result.useTopBorder           = some(true)
        of BorderBottom:
          result.useBottomBorder        = some(true)
        of BorderLeft:
          result.useLeftBorder          = some(true)
        of BorderRight:
          result.useRightBorder         = some(true)
        of HorizontalInterior:
          result.useHorizontalSeparator = some(true)
        of VerticalInterior:
          result.useVerticalSeparator   = some(true)
        of BorderTypical:
          result.useTopBorder           = some(true)
          result.useBottomBorder        = some(true)
          result.useLeftBorder          = some(true)
          result.useRightBorder         = some(true)
          result.useVerticalSeparator   = some(true)
          result.useHorizontalSeparator = some(false)
        of BorderAll:
          result.useTopBorder           = some(true)
          result.useBottomBorder        = some(true)
          result.useLeftBorder          = some(true)
          result.useRightBorder         = some(true)
          result.useVerticalSeparator   = some(true)
          result.useHorizontalSeparator = some(true)
    if boxStyle != nil:
      result.boxStyle = some(boxStyle)
    if align != AlignIgnore:
      result.alignStyle = some(align)

var
  plainStyle    = FmtStyle(
    textColor: some(""), bgColor: some(""), overflow: some(OWrap),
    lpad: some(0), rpad: some(0), tmargin: some(0), bmargin: some(0),
    casing: some(CasingIgnore), bold: some(false), hang: some(2),
    inverse: some(false), strikethrough: some(false),
    italic: some(false), underlineStyle: some(UnderlineIgnore),
    useTopBorder: some(true), useLeftBorder: some(true),
    useRightBorder: some(true), useVerticalSeparator: some(false),
    useHorizontalSeparator: some(false), boxStyle: some(BoxStyleDouble),
    alignStyle: some(AlignIgnore))

  defaultStyle* = plainStyle
  tableDefault  = newStyle(overflow = OWrap, tmargin = 0, bmargin = 0,
                                                       lpad = 0, rpad = 0)

  styleMap*: Table[string, FmtStyle] = {
    "container" : newStyle(rpad = 1, lpad = 1, tmargin = 1, bmargin = 1),
    "div"       : newStyle(rpad = 1, lpad = 1, bgColor = "none"),
    "p"         : newStyle(bmargin = 1),
    "basic"     : newStyle(bmargin = 0),
    "h1"        : newStyle(fgColor = "red", bold = BoldOn, align = AlignL,
                           italic = ItalicOn, casing = CasingUpper,
                           tmargin = 1, bmargin = 0),
    "h2"        : newStyle(fgColor = "lime", bgColor = "darkslategray",
                  bold = BoldOn, align = AlignL, italic = ItalicOn, tmargin = 2),
    "h3"        : newStyle(bgColor = "red", fgColor = "white",
                  italic = ItalicOn, tmargin = 0, casing = CasingUpper),
    "h4"        : newStyle(bgColor = "red", fgColor = "white", italic = ItalicOn,
                           underline = UnderlineSingle, casing = CasingTitle),
    "h5"        : newStyle(fgColor = "darkslategray", bgColor = "lime",
                                     italic = ItalicOn, casing = CasingTitle),
    "h6"        : newStyle(fgColor = "yellow", bgColor = "blue",
                           underline = UnderlineSingle, casing = CasingTitle),
    "ol"        : newStyle(bulletChar = Rune('.'), lpad = 2, align = AlignL),
    "ul"        : newStyle(bulletChar = Rune(0x2022), lpad = 2,
                                          align = AlignL), #•
    "li"        : newStyle(lpad = 1, overflow = OWrap, align = AlignL),
    "left"      : newStyle(align = AlignL),
    "right"     : newStyle(align = AlignR),
    "center"    : newStyle(align = AlignC),
    "justify"   : newStyle(align = AlignJ),
    "flush"     : newStyle(align = AlignF),
    "table"     : newStyle(borders = [BorderAll], tmargin = 1, bmargin = 1,
                           lpad = 1, rpad = 1, bgColor = "dodgerblue"),
    "thead"     : tableDefault,
    "tbody"     : tableDefault,
    "tfoot"     : tableDefault,
    "plain"     : plainStyle,
    "text"      : defaultStyle,
    "tborder"   : newStyle(tmargin = 0, bmargin = 0, lpad = 1, rpad = 1),
    "td"        : newStyle(tmargin = 0, overflow = OWrap, align = AlignL,
                                                   lpad = 1, rpad = 1),
    "th"        : newStyle(bgColor = "black", bold = BoldOn, overflow = OWrap,
                  casing = CasingUpper, tmargin = 0, fgColor = "lime",
                  lpad = 1, rpad = 1, align = AlignC),
    "tr"        : newStyle(fgColor = "white", bold = BoldOn, lpad = 1, rpad = 1,
                                      overflow = OWrap, tmargin = 0, bmargin = 0,
                           bgColor = "dodgerblue"),
    "tr.even"   : newStyle(fgColor = "white", bgColor = "slategray",
                            tmargin = 1, overflow = OWrap),
    "tr.odd"    : newStyle(fgColor = "white", bgColor = "steelblue",
                            tmargin = 1, overflow = OWrap),
    "em"        : newStyle(fgColor = "jazzberry", italic = ItalicOn),
    "italic"    : newStyle(italic = ItalicOn),
    "i"         : newStyle(italic = ItalicOn),
    "u"         : newStyle(underline = UnderlineSingle),
    "underline" : newStyle(underline = UnderlineSingle),
    "strong"    : newStyle(inverse = InverseOn, italic = ItalicOn),
    "code"      : newStyle(inverse = InverseOn, italic = ItalicOn),
    "caption"   : newStyle(bgColor = "black", fgColor = "atomiclime",
                           align = AlignC, italic = ItalicOn)

    }.toTable()

  perClassStyles*: Table[string, FmtStyle] = {
    "callout"   : newStyle(fgColor = "fandango", bgColor = "jazzberry",
                           italic = ItalicOn, casing = CasingTitle)
    }.toTable()

  perIdStyles*    = Table[string, FmtStyle]()

  breakingStyles*: Table[string, bool] = {
    "container"  : true,
    "basic"      : true,
    "caption"    : true,
    "p"          : true,
    "div"        : true,
    "ol"         : true,
    "ul"         : true,
    "li"         : true,
    "blockquote" : true,
    "pre"        : true,
    "q"          : true,
    "small"      : true,
    "td"         : true,
    "th"         : true,
    "title"      : true,
    "h1"         : true,
    "h2"         : true,
    "h3"         : true,
    "h4"         : true,
    "h5"         : true,
    "h6"         : true,
    "left"       : true,
    "right"      : true,
    "center"     : true,
    "justify"    : true,
    "flush"      : true
    }.toTable()

{.emit: """
#include <stdatomic.h>
#include <stdint.h>

_Atomic(uint32_t) next_id = ATOMIC_VAR_INIT(0x1ffffff);

uint32_t
next_style_id() {
  return atomic_fetch_add(&next_id, 1);
}

""" .}

# I'd love for each style is going to get one unique ID that we can
# look up in both directions. Currently this won't work in a
# multi-threaded world, but I'm going to soon migrate it to my
# lock-free, wait-free hash tables.

proc next_style_id(): cuint {.importc, nodecl.}

var
  idToStyleMap: Table[uint32, FmtStyle]
  styleToIdMap: Table[FmtStyle, uint32]

proc getStyleId*(s: FmtStyle): uint32 =
  ## This is really meant to be an internal API, but cross-module.  It
  ## returns a 32-bit integer unique to the style (across the life of
  ## program execution). This integer is added to the pre-render
  ## stream to pass on information to the renderer, and is explicitly
  ## NOT in the range of valid unicode characters.
  ##
  ## Note that the renderer does not need to keep stack state; the
  ## styles it looks up have had all stack operations pre-applied.
  if s in styleToIdMap:
    return styleToIdMap[s]

  result = uint32(next_style_id())

  idToStyleMap[result] = s
  styleToIdMap[s]      = result

proc idToStyle*(n: uint32): FmtStyle =
  ## The inverse of `getStyleId()`, which enables renderers to look up
  ## style information associated with the text that follows (until
  ## seeing a reset marker or another style ID.)
  result = idToStyleMap[n]

  if result == defaultStyle:
    return
  for k, v in styleMap:
    if v == result:
      return

proc mergeStyles*(base: FmtStyle, changes: FmtStyle): FmtStyle =
  ## This layers any new overrides on top of existing values, creating
  ## a third style.
  result         = base.copyStyle()
  result.lpad    = changes.lpad
  result.rpad    = changes.rpad
  result.tmargin = changes.tmargin
  result.bmargin = changes.bmargin

  if changes.textColor.isSome():
    result.textColor = changes.textColor
  if changes.bgColor.isSome():
    result.bgColor = changes.bgColor
  if changes.overflow.isSome():
    result.overflow = changes.overflow
  if changes.hang.isSome():
    result.hang = changes.hang
  if changes.casing.isSome():
    result.casing = changes.casing
  if changes.bold.isSome():
    result.bold = changes.bold
  if changes.inverse.isSome():
    result.inverse = changes.inverse
  if changes.strikethrough.isSome():
    result.strikethrough = changes.strikethrough
  if changes.italic.isSome():
    result.italic = changes.italic
  if changes.underlineStyle.isSome():
    result.underlineStyle = changes.underlineStyle
  if changes.bulletChar.isSome():
    result.bulletChar = changes.bulletChar
  if changes.useTopBorder.isSome():
    result.useTopBorder = changes.useTopBorder
  if changes.useBottomBorder.isSome():
    result.useBottomBorder = changes.useBottomBorder
  if changes.useLeftBorder.isSome():
    result.useLeftBorder = changes.useLeftBorder
  if changes.useRightBorder.isSome():
    result.useRightBorder = changes.useRightBorder
  if changes.useVerticalSeparator.isSome():
    result.useVerticalSeparator = changes.useVerticalSeparator
  if changes.useHorizontalSeparator.isSome():
    result.useHorizontalSeparator = changes.useHorizontalSeparator
  if changes.boxStyle.isSome():
    result.boxStyle = changes.boxStyle
  if changes.alignStyle.isSome():
    result.alignStyle = changes.alignStyle

proc isContainer*(r: Rope): bool =
  ## Returns true if the rope itself represents a "container", meaning
  ## a layout box.
  if r == nil:
    return false

  case r.kind
  of RopeAtom, RopeLink, RopeFgColor, RopeBgColor:
    return false
  of RopeList, RopeTable, RopeTableRow, RopeTableRows:
    return true
  of RopeBreak:
    if r.guts == nil:
      return false
    else:
      return true
  of RopeTaggedContainer:
    if r.tag in breakingStyles or r.noTextExtract:
      return true
    else:
      return false

template setDefaultStyle*(style: FmtStyle) =
  ## This call allows you to set the default starting style, which is
  ## applied whenever you call a routine that formats (such as
  ## `print()` or `stylize()`
  defaultStyle = style

type StyleType* = enum StyleTypeTag, StyleTypeClass, StyleTypeId

proc setStyle*(reference: string, style: FmtStyle, kind = StyleTypeTag) =
  ## Set a specific output style for a tag, class or ID, based on the
  ## value of the `kind` parameter. See the notes on `newStyle()` for
  ## how this gets applied.
  case kind
  of StyleTypeTag:   styleMap[reference]       = style
  of StyleTypeClass: perClassStyles[reference] = style
  of StyleTypeId:    perIdStyles[reference]    = style

proc getStyle*(reference: string, kind = StyleTypeTag): FmtStyle =
  ## Return the installed style associated w/ a Tag, Class or Id.
  return case kind
         of StyleTypeTag:
           if reference == "default":
              return defaultStyle
           else:
             styleMap[reference]
         of StyleTypeClass: perClassStyles[reference]
         of StyleTypeId:    perIdStyles[reference]

proc setClass*(r: Rope, name: string, recurse = false) =
  ## Sets the 'class' associated with a given Rope.
  var toProcess: seq[Rope]

  if recurse:
    toProcess = r.ropeWalk()
  else:
    toProcess.add(r)

  for item in toProcess:
      item.class = name

proc setID*(r: Rope, name: string) =
  ## Sets the 'id' associated with a given rope manually.

proc findFirstContainer*(r: Rope): Rope =
  ## If a rope has annotation nodes at the top, skip them to find
  ## the first container node, or return null if not.
  for item in r.ropeWalk():
    if item.isContainer():
      return item

proc ropeStyle*(r:     Rope,
                style: FmtStyle,
                recurse   = false,
                container = false): Rope
    {.discardable.} =
  ## Edits the style for a specific rope, merging any passed overrides
  ## into the style associated with the Rope's ID.
  ##
  ## If the rope has no ID, it is assigned one at random by
  ## hex-encoding a 64-bit random value.

  var toProcess: seq[Rope]

  result = r

  if r == nil:
    return

  if container and not r.isContainer():
    return r.findFirstContainer().ropeStyle(style, true, recurse)

  if recurse:
    toProcess = r.ropeWalk()
  else:
    toProcess.add(r)

  for item in toProcess:
    if container:
      if not item.isContainer():
        continue
      item.noTextExtract = true

    if item.id == "":
      item.id = randString(8).hex()

    if item.id in perIdStyles:
      perIdStyles[item.id] = perIdStyles[item.id].mergeStyles(style)
    else:
      perIdStyles[item.id] = style

proc colPcts*(r: Rope, pcts: openarray[int]): Rope {.discardable.} =
  if r == nil:
    return

  var info: seq[ColInfo]
  for item in pcts:
    info.add(ColInfo(span: 1, widthPct: item))

  for item in r.search(tag = ["table"]):
    item.colInfo = info

  return r

proc applyClass*(r: Rope, class: string, recurse = true): Rope {.discardable.} =
  if r == nil:
    return

  if recurse:
    for item in r.ropeWalk():
      item.class = class
  else:
    r.class = class

proc noTableBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides a rope's current style to remove any
  ## table borders.
  return r.ropeStyle(newStyle(borders = [BorderNone]), recurse, true)

proc allTableBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides a rope's current style to add all
  ## table borders.
  return r.ropeStyle(newStyle(borders = [BorderAll]), recurse, true)

proc typicalBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides a rope's current style to set 'typical'
  ## table borders, which is all except for internal
  ## horizontal separators.
  return r.ropeStyle(newStyle(borders = [BorderTypical]), recurse, true)

proc defaultBg*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Remove any background color for the current node (going with
  ## whatever the environment uses by default). Note that it may not
  ## have the effect you think if sub-nodes set a color (i.e., don't
  ## do this at the top level of a table).
  return r.ropeStyle(FmtStyle(bgColor: some("")), recurse)

proc defaultBg*(s: string): Rope {.discardable.} =
  ## Return a Rope that will ensure the current string's background
  ## color is not set (unless you later change it with another call).
  ##
  ## This call does NOT process embedded markdown.
  return pre(s).defaultBg()

proc defaultFg*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Remove the foreground text color for the current node (applying
  ## whatever the environment uses by default). Note that it may not
  ## have the effect you think if sub-nodes set a color (i.e., don't
  ## do this at the top level of a table).
  return r.ropeStyle(FmtStyle(textColor: some("")), recurse)

proc defaultFg*(s: string): Rope {.discardable.} =
  ## Return a Rope that will ensure the current string's foreground
  ## color is not set (unless you later change it with another call).
  ##
  ## This call does NOT process embedded markdown.
  return pre(s).defaultFg()

proc bgColor*(r: Rope, color: string, recurse = true): Rope {.discardable.} =
  ## Overrides a rope's current style to set the background color.
  ## Note that sub-nodes will still have their style applied after
  ## this, and can have an impact. For instance, setting this at the
  ## "table" level is unlikely to affect the entire table.
  return r.ropeStyle(newStyle(bgColor = color), recurse)

proc bgColor*(s: string, color: string): Rope {.discardable.} =
  ## Returns a new Rope from a string, where the node will have the
  ## explicit background color applied. This will not have sub-nodes,
  ## so should override other settings (e.g., in a table).
  return pre(s).bgColor(color)

proc fgColor*(r: Rope, color: string, recurse = true): Rope {.discardable.} =
  ## Overrides a rope's current style to set the foreground color.
  ## Note that sub-nodes will still have their style applied after
  ## this, and can have an impact. For instance, setting this at the
  ## "table" level is unlikely to affect the entire table.
  return r.ropeStyle(newStyle(fgColor = color), recurse)

proc fgColor*(s: string, color: string): Rope {.discardable.} =
  ## Returns a new Rope from a string, where the node will have the
  ## explicit foreground color applied. This will not have sub-nodes,
  ## so should override other settings (e.g., in a table).
  return pre(s).fgColor(color)

proc topMargin*(r: Rope, n: int, recurse = false): Rope {.discardable.} =
  ## Add a top margin to a Rope object. This may be ignored if the
  ## rope isn't a 'block' of some sort.
  return r.ropeStyle(newStyle(tmargin = n), recurse, true)

proc topMargin*(s: string, n: int): Rope {.discardable.} =
  ## Adds a top margin to a string.
  return pre(s).topMargin(n)

proc bottomMargin*(r: Rope, n: int, recurse = false): Rope {.discardable.} =
  ## Add a bottom margin to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort.
  return r.ropeStyle(newStyle(bmargin = n), recurse, true)

proc bottomMargin*(s: string, n: int): Rope {.discardable.} =
  ## Adds a bottom margin to a string.
  return pre(s).bottomMargin(n)

proc leftPad*(r: Rope, n: int, recurse = false): Rope {.discardable.} =
  ## Add left padding to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort.
  return r.ropeStyle(newStyle(lpad = n), recurse, true)

proc leftPad*(s: string, n: int): Rope {.discardable.} =
  ## Add left padding to a string.
  result = pre(s).leftPad(n)

proc rightPad*(r: Rope, n: int, recurse = false): Rope {.discardable.} =
  ## Add right padding to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort.
  return r.ropeStyle(newStyle(rpad = n), recurse, true)

proc rightPad*(s: string, n: int): Rope {.discardable.} =
  ## Add right padding to a string.
  result = s.text().rightPad(n)

proc lpad*(r: string | Rope, n: int, recurse = false): Rope {.discardable.} =
  ## Alias for `leftPad`
  result = r.leftPad(n, recurse)

proc rpad*(r: string | Rope, n: int): Rope {.discardable.} =
  ## Alias for `rightPad`
  result = r.rightPad(n)

proc plainBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have plain borders, *if* borders are set, and if
  ## the border setting isn't overriden by an internal node.
  return r.ropeStyle(newStyle(boxStyle = BoxStylePlain), recurse, true)

proc boldBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have bold borders, *if* borders are set, and if
  ## the border setting isn't overriden by an internal node.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleBold), recurse, true)

proc doubleBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have double-lined borders, *if* borders are set,
  ## and if the border setting isn't overriden by an internal node.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleDouble), recurse, true)

proc dashBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have dashed borders, *if* borders are set,
  ## and if the border setting isn't overriden by an internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleDash), recurse, true)

proc altDashBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have an dashed borders created from an alternate
  ## part of the Unicode character set. This is only applied *if*
  ## borders are set, and if the border setting isn't overriden by an
  ## internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleDash2), recurse, true)

proc boldDashBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have BOLD dashed borders, *if* borders are set,
  ## and if the border setting isn't overriden by an internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleBoldDash), recurse, true)

proc altBoldDashBorders*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have BOLD dashed borders created from an alternate
  ## part of the Unicode character set. This is only applied *if*
  ## borders are set, and if the border setting isn't overriden by an
  ## internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleBoldDash2), recurse, true)

proc boxStyle*(r: Rope, s: BoxStyle, recurse = true): Rope {.discardable.} =
  ## Style box borders using a specific passed box style.  Built-in
  ## default values are:
  ##
  ## BoxStylePlain, BoxStyleBold, BoxStyleDouble, BoxStyleDash,
  ## BoxStyleDash2, BoxStyleBoldDash, BoxStyleBoldDash2,
  ## BoxStyleAsterisk, BoxStyleAscii
  ##
  ## Styles depend on the font having approrpiate unicode glyphs;
  ## we've found the dashed boxes are less widely available.
  return r.ropeStyle(newStyle(boxStyle = s), recurse, true)

proc setBorders*(r: Rope, o: BorderOpts, recurse = true): Rope {.discardable.} =
  ## Set which borders will be displayed for any tables within a rope.
  return r.ropeStyle(newStyle(borders = [o]), recurse, true)

proc setBullet*(r: Rope, c: Rune, recurse = true): Rope {.discardable.} =
  ## Sets the character used as a bullet for lists. For ordered lists,
  ## this does NOT change the numbering style, it changes the
  ## character put after the number. Currently, there's no ability to
  ## tweak the numbering style. You can instead use an unordered list,
  ## remove the bullet with `removeBullet` and manually number.
  if r != nil:
    r.noTextExtract = true
  return r.ropeStyle(newStyle(bulletChar = c), recurse)

proc removeBullet*(r: Rope, recurse = true): Rope {.discardable.} =
  ## Causes unordered list items to render without a bullet.
  ## Ordered list items still render numbered; they just lose
  ## the period after the number.
  return r.ropeStyle(FmtStyle(bulletChar: some(Rune(0x0000))), recurse, true)

proc setCasing*(r: Rope, casing: TextCasing, recurse = true): Rope
    {.discardable.} =
  ## Sets casing on a rope.
  return r.ropeStyle(newStyle(casing = casing), recurse)

proc setCasing*(s: string, casing: TextCasing): Rope =
  return pre(s).setCasing(casing)

proc setOverflow*(r: Rope, overflow: OverflowPreference, recurse = true): Rope
  {.discardable.} =
  ## Sets the overflow strategy. If you set OIntentWrap then you can
  ## change the wrap hang value via `setHang()`.
  return r.ropeStyle(newStyle(overflow = overflow), recurse)

proc setOverflow*(s: string, overflow: OverflowPreference): Rope =
  return pre(s).setOverflow(overflow)

proc setHang*(r: Rope, hang: int, recurse = true): Rope {.discardable.} =
  ## Sets the indent hang for when OIndentWrap is on.
  return r.ropeStyle(newStyle(hang = hang), recurse)

proc bold*(r: Rope, disable = false, recurse = true): Rope {.discardable.} =
  var param: BoldPref

  if disable:
    param = BoldOff
  else:
    param = BoldOn

  return r.ropeStyle(newStyle(bold = param), recurse)

proc bold*(s: string): Rope =
  return pre(s).bold()

proc inverse*(r: Rope, disable = false, recurse = true): Rope {.discardable.} =
  var param: InversePref

  if disable:
    param = InverseOff
  else:
    param = InverseOn

  return r.ropeStyle(newStyle(inverse = param), recurse)

proc inverse*(s: string): Rope =
  return pre(s).inverse()

proc strikethrough*(r: Rope, disable = false, recurse = true):
                  Rope {.discardable.} =
  var param: StrikeThruPref

  if disable:
    param = StrikeThruOff
  else:
    param = StrikeThruOn

  return r.ropeStyle(newStyle(strikethru = param), recurse)

proc strikethrough*(s: string): Rope =
  return pre(s).strikethrough()

proc italic*(r: Rope, disable = false, recurse = true): Rope {.discardable.} =
  var param: ItalicPref

  if disable:
    param = ItalicOff
  else:
    param = ItalicOn

  return r.ropeStyle(newStyle(italic = param), recurse)

proc italic*(s: string): Rope =
  return pre(s).italic()

proc underline*(r: Rope, kind = UnderlineSingle, recurse = true):
              Rope {.discardable.} =

  return r.ropeStyle(newStyle(underline = kind), recurse)

proc underline*(s: string): Rope =
  return pre(s).underline()

proc align*(r: Rope, kind: AlignStyle, recurse = false): Rope {.discardable.} =
  ## Sets alignment preference for a rope as specified.  Does NOT
  ## recurse into children by default.
  return r.ropeStyle(newStyle(align = kind), recurse)

proc align*(s: string, kind: AlignStyle): Rope =
  return pre(s).align(kind)

proc center*(r: Rope, recurse = false): Rope {.discardable.} =
  ## Centers a node. Unless recurse is on, this will only set the
  ## preference on the top rope, not any children.
  return r.ropeStyle(newStyle(align = AlignC), recurse)

proc center*(s: string): Rope =
  return pre(s).center()

proc right*(r: Rope, recurse = false): Rope {.discardable.} =
  ## Right-justifies a node. Unless recurse is on, this will only set
  ## the preference on the top rope, not any children.
  return r.ropeStyle(newStyle(align = AlignR), recurse)

proc right*(s: string): Rope =
  return pre(s).right()

proc left*(r: Rope, recurse = false): Rope {.discardable.} =
  ## Left-justifies a node. Unless recurse is on, this will only set
  ## the preference on the top rope, not any children.
  return r.ropeStyle(newStyle(align = AlignL), recurse)

proc left*(s: string): Rope =
  return pre(s).left()

proc justify*(r: Rope, recurse = false): Rope {.discardable.} =
  ## Does line justification (adds spaces between words to justify
  ## both on the left and the right), except for any trailing
  ## line. Unless recurse is on, this will only set the preference on
  ## the top rope, not any children.
  return r.ropeStyle(newStyle(align = AlignJ), recurse)

proc justify*(s: string): Rope =
  return pre(s).justify()

proc flushJustify*(r: Rope, recurse = false): Rope {.discardable.} =
  ## Does full flush line justification, including for the final line
  ## (unless it is a single word). Unless recurse is on, this will
  ## only set the preference on the top rope, not any children.
  return r.ropeStyle(newStyle(align = AlignF), recurse)

proc flushJustify*(s: string): Rope =
  return pre(s).justify()
