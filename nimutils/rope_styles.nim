##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import unicode, tables, rope_base, rope_construct, options, random, hexdump

proc newStyle*(fgColor = "", bgColor = "", overflow = OIgnore, hang = -1,
               lpad = -1, rpad = -1, casing = CasingIgnore,
               tmargin = -1, bmargin = -1, bold = BoldIgnore,
               inverse = InverseIgnore, strikethru = StrikeThruIgnore,
               italic = ItalicIgnore, underline = UnderlineIgnore,
               bulletChar = Rune(0x0000), minColWidth = -1, maxColWidth = -1,
               borders: openarray[BorderOpts] = [], boxStyle: BoxStyle = nil,
               align = AlignIgnore): FmtStyle =
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
    if hang >= 0:
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
    if minColWidth != -1:
      result.minTableColWidth = some(minColWidth)
    if maxColWidth != -1:
      result.maxTableColWidth = some(maxColWidth)

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
  defaultStyle* = newStyle(overflow = OWrap, lpad = 0, rpad = 0, tmargin = 0)
  tableDefault  = newStyle(borders = [BorderAll], overflow = OWrap, tmargin = 0,
                           fgColor = "white", bgcolor = "dodgerblue")
  # 1. Even / odd columns
  # 2. Table margins
  styleMap*: Table[string, FmtStyle] = {
    "body"     : newStyle(rpad = 1, lpad = 1),
    "div"      : newStyle(rpad = 1, lpad = 1, bgColor = "none"),
    "p"        : newStyle(bmargin = 1),
    "basic"    : newStyle(bmargin = 0),
    "h1"       : newStyle(fgColor = "red", bold = BoldOn, align = AlignL,
                          italic = ItalicOn, casing = CasingUpper,
                          tmargin = 1, bmargin = 0),
    "h2"       : newStyle(fgColor = "lime", bgColor = "darkslategray",
                 bold = BoldOn, align = AlignL, italic = ItalicOn, tmargin = 2),
    "h3"       : newStyle(bgColor = "red", fgColor = "white",
                 italic = ItalicOn, tmargin = 1, casing = CasingUpper),
    "h4"       : newStyle(bgColor = "red", fgColor = "white", italic = ItalicOn,
                          underline = UnderlineSingle, casing = CasingTitle),
    "h5"       : newStyle(fgColor = "darkslategray", bgColor = "lime",
                                    italic = ItalicOn, casing = CasingTitle),
    "h6"       : newStyle(fgColor = "yellow", bgColor = "blue",
                          underline = UnderlineSingle, casing = CasingTitle),
    "ol"       : newStyle(bulletChar = Rune('.'), lpad = 2, align = AlignL),
    "ul"       : newStyle(bulletChar = Rune(0x2022), lpad = 2,
                                         align = AlignL), #•
    "li"       : newStyle(lpad = 1, overflow = OWrap, align = AlignL),
    "table"    : tableDefault,
    "thead"    : tableDefault,
    "tbody"    : tableDefault,
    "tfoot"    : tableDefault,
    "tborder"  : tableDefault,
    "td"       : newStyle(tmargin = 0, overflow = OWrap, align = AlignL,
                                                  lpad = 1, rpad = 1),
    "th"       : newStyle(bgColor = "black", bold = BoldOn, overflow = OWrap,
                 casing = CasingUpper, tmargin = 0, fgColor = "lime",
                 align = AlignC),
    "tr"       : newStyle(fgColor = "white", bold = BoldOn, lpad = 0, rpad = 0,
                          overflow = OWrap, tmargin = 0,
                          bgColor = "dodgerblue"),
    "tr.even"  : newStyle(fgColor = "white", bgColor = "dodgerblue",
                           tmargin = 0, overflow = OWrap),
    "tr.odd"   : newStyle(fgColor = "white", bgColor = "steelblue",
                           tmargin = 0, overflow = OWrap),
    "em"       : newStyle(fgColor = "jazzberry", italic = ItalicOn),
    "italic"   : newStyle(italic = ItalicOn),
    "i"        : newStyle(italic = ItalicOn),
    "u"        : newStyle(underline = UnderlineSingle),
    "underline": newStyle(underline = UnderlineSingle),
    "strong"   : newStyle(inverse = InverseOn, italic = ItalicOn),
    "code"     : newStyle(inverse = InverseOn, italic = ItalicOn),
    "caption"  : newStyle(bgColor = "black", fgColor = "atomiclime",
                          align = AlignC, italic = ItalicOn, bmargin = 2)

    }.toTable()

  perClassStyles* = Table[string, FmtStyle]()
  perIdStyles*    = Table[string, FmtStyle]()

  breakingStyles*: Table[string, bool] = {
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
    "h6"         : true
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
  if changes.minTableColWidth.isSome():
    result.minTableColWidth = changes.minTableColWidth
  if changes.maxTableColWidth.isSome():
    result.maxTableColWidth = changes.maxTableColWidth
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
         of StyleTypeTag:   styleMap[reference]
         of StyleTypeClass: perClassStyles[reference]
         of StyleTypeId:    perIdStyles[reference]

proc setClass*(r: Rope, name: string) =
  ## Sets the 'class' associated with a given Rope.
  r.class = name

proc setID*(r: Rope, name: string) =
  ## Sets the 'id' associated with a given rope manually.

proc ropeStyle*(r: Rope, style: FmtStyle): Rope =
  ## Edits the style for a specific rope, merging any passed overrides
  ## into the style associated with the Rope's ID.
  ##
  ## If the rope has no ID, it is assigned one at random by
  ## hex-encoding a 64-bit random value.
  if r.id == "":
    r.id = randString(8).hex()

  if r.id in perIdStyles:
    perIdStyles[r.id] = style.mergeStyles(perIdStyles[r.id])
  else:
    perIdStyles[r.id] = style.mergeStyles(defaultStyle)

  return r

proc noTableBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides a rope's current style to remove any
  ## table borders.
  return r.ropeStyle(newStyle(borders = [BorderNone]))

proc allTableBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides a rope's current style to add all
  ## table borders.
  return r.ropeStyle(newStyle(borders = [BorderAll]))

proc typicalBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides a rope's current style to set 'typical'
  ## table borders, which is all except for internal
  ## horizontal separators.
  return r.ropeStyle(newStyle(borders = [BorderTypical]))

proc defaultBg*(r: Rope): Rope {.discardable.} =
  ## Remove any background color for the current node (going with
  ## whatever the environment uses by default). Note that it may not
  ## have the effect you think if sub-nodes set a color (i.e., don't
  ## do this at the top level of a table).
  return r.ropeStyle(FmtStyle(bgColor: some("")))

proc defaultBg*(s: string): Rope {.discardable.} =
  ## Return a Rope that will ensure the current string's background
  ## color is not set (unless you later change it with another call).
  ##
  ## This call does NOT process embedded markdown.
  return s.textRope().defaultBg()

proc defaultFg*(r: Rope): Rope {.discardable.} =
  ## Remove the foreground text color for the current node (applying
  ## whatever the environment uses by default). Note that it may not
  ## have the effect you think if sub-nodes set a color (i.e., don't
  ## do this at the top level of a table).
  return r.ropeStyle(FmtStyle(textColor: some("")))

proc defaultFg*(s: string): Rope {.discardable.} =
  ## Return a Rope that will ensure the current string's foreground
  ## color is not set (unless you later change it with another call).
  ##
  ## This call does NOT process embedded markdown.
  return s.textRope().defaultFg()

proc bgColor*(r: Rope, color: string): Rope {.discardable.} =
  ## Overrides a rope's current style to set the background color.
  ## Note that sub-nodes will still have their style applied after
  ## this, and can have an impact. For instance, setting this at the
  ## "table" level is unlikely to affect the entire table.
  return r.ropeStyle(newStyle(bgColor = color))

proc bgColor*(s: string, color: string): Rope {.discardable.} =
  ## Returns a new Rope from a string, where the node will have the
  ## explicit background color applied. This will not have sub-nodes,
  ## so should override other settings (e.g., in a table).
  return s.textRope().bgColor(color)

proc fgColor*(r: Rope, color: string): Rope {.discardable.} =
  ## Overrides a rope's current style to set the foreground color.
  ## Note that sub-nodes will still have their style applied after
  ## this, and can have an impact. For instance, setting this at the
  ## "table" level is unlikely to affect the entire table.
  return r.ropeStyle(newStyle(fgColor = color))

proc fgColor*(s: string, color: string): Rope {.discardable.} =
  ## Returns a new Rope from a string, where the node will have the
  ## explicit foreground color applied. This will not have sub-nodes,
  ## so should override other settings (e.g., in a table).
  return s.textRope().fgColor(color)

proc topMargin*(r: Rope, n: int): Rope {.discardable.} =
  ## Add a top margin to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort.  Currently, the margin is also
  ## ignored for the first rope when rendering (though probably will
  ## change).
  return r.ropeStyle(newStyle(tmargin = n))

proc bottomMargin*(r: Rope, n: int): Rope {.discardable.} =
  ## Add a bottom margin to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort. Currently, the margin is also
  ## ignored for the first rope when rendering (though probably will
  ## change).
  return r.ropeStyle(newStyle(bmargin = n))

proc leftPad*(r: Rope, n: int): Rope {.discardable.} =
  ## Add left padding to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort.
  return r.ropeStyle(newStyle(lpad = n))

proc rightPad*(r: Rope, n: int): Rope {.discardable.} =
  ## Add right padding to a Rope object. This will be ignored if the
  ## rope isn't a 'block' of some sort.
  return r.ropeStyle(newStyle(rpad = n))

proc plainBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have plain borders, *if* borders are set, and if
  ## the border setting isn't overriden by an internal node.
  return r.ropeStyle(newStyle(boxStyle = BoxStylePlain))

proc boldBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have bold borders, *if* borders are set, and if
  ## the border setting isn't overriden by an internal node.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleBold))

proc doubleBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have double-lined borders, *if* borders are set,
  ## and if the border setting isn't overriden by an internal node.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleDouble))

proc dashBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have dashed borders, *if* borders are set,
  ## and if the border setting isn't overriden by an internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleDash))

proc altDashBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have an dashed borders created from an alternate
  ## part of the Unicode character set. This is only applied *if*
  ## borders are set, and if the border setting isn't overriden by an
  ## internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleDash2))

proc boldDashBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have BOLD dashed borders, *if* borders are set,
  ## and if the border setting isn't overriden by an internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleBoldDash))

proc altBoldDashBorders*(r: Rope): Rope {.discardable.} =
  ## Overrides any settings for table borders; any nested table
  ## contents will have BOLD dashed borders created from an alternate
  ## part of the Unicode character set. This is only applied *if*
  ## borders are set, and if the border setting isn't overriden by an
  ## internal node.
  ##
  ## NB, All dashed borders don't render on all terminals, and we do
  ## not currently attempt to detect this condition.
  return r.ropeStyle(newStyle(boxStyle = BoxStyleBoldDash2))

proc setBullet*(r: Rope, c: Rune): Rope {.discardable.} =
  ## Sets the character used as a bullet for lists. For ordered lists,
  ## this does NOT change the numbering style, it changes the
  ## character put after the number. Currently, there's no ability to
  ## tweak the numbering style. You can instead use an unordered list,
  ## remove the bullet with `removeBullet` and manually number.
  return r.ropeStyle(newStyle(bulletChar = c))

proc removeBullet*(r: Rope): Rope {.discardable.} =
  ## Causes unordered list items to render without a bullet.
  ## Ordered list items still render numbered; they just lose
  ## the period after the number.
  return r.ropeStyle(FmtStyle(bulletChar: some(Rune(0x0000))))
