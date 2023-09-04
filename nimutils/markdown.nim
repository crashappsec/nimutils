{.pragma: cmark, cdecl, importc.}

import std/terminal

# Decided not to wrap much of the library; instead I'm going to wrap
# an HTML parsing library that I gen from, instead of this.

type MdOpts* = enum
  MdCmarkDefault  = 0,
  MdSourcePos     = 0x2,
  MdHardBreaks    = 0x4,
  MdNoBreaks      = 0x10,
  MdValidateUtf   = 0x200,
  MdSmart         = 0x400,
  MdPreLang       = 0x800,
  MdLiberalInline = 0x1000,
  MdFootnotes     = 0x2000,
  MdStDblTilde    = 0x4000,
  MdPreferStyle   = 0x8000,
  MdFullInfo      = 0x10000,
  MdRenderUnsafe  = 0x20000
when false:
  type
    MDNodeType* {.size: sizeof(cuint).} = enum
      MdTypeNone          = 0x0000,
      MdTypeBlock         = 0x8000,
      MdTypeInline        = 0xc000,
      MdTypeDocument      = MdTypeBlock or 0x0001,
      MdTypeBlockQuote    = MdTypeBlock or 0x0002,
      MdTypeList          = MdTypeBlock or 0x0003,
      MdTypeItem          = MdTypeBlock or 0x0004,
      MdTypeCodeBlock     = MdTypeBlock or 0x0005,
      MdTypeHtmlBlock     = MdTypeBlock or 0x0006,
      MdTypeCustomBlock   = MdTypeBlock or 0x0007,
      MdTypeParagraph     = MdTypeBlock or 0x0008,
      MdTypeHeading       = MdTypeBlock or 0x0009,
      MdTypeThematicBreak = MdTypeBlock or 0x000a,
      MdTypeFootnoteDef   = MdTypeBlock or 0x000b,
      MdTypeText          = MdTypeInline | 0x0001,
      MdTypeSoftBreak     = MdTypeInline | 0x0002,
      MdTypeLineBreak     = MdTypeInline | 0x0003,
      MdTypeCode          = MdTypeInline | 0x0004,
      MdTypeHtmlInline    = MdTypeInline | 0x0005,
      MdTypeCustomInline  = MdTypeInline | 0x0006,
      MdTypeEmph          = MdTypeInline | 0x0007,
      MdTypeStrong        = MdTypeInline | 0x0008,
      MdTypeLink          = MdTypeInline | 0x0009,
      MdTypeImage         = MdTypeInline | 0x000a,
      MdTypeFootnoteRef   = MdTypeInline | 0x000b

    MDListType* {.size: sizeof(cuint).} = enum
      MdNoList = 0, MdBulletList = 1, MdOrderedList = 2

    MDDelimType* {.size: sizeof(cuint).} = enum
      MdDelimNone = 0, MdDelimPeriod = 1, MdDelimParen = 2

    MDEventType* {.size: sizeof(cuint).} = enum
      MdEventNone = 0, MdEventDone = 1, MdEventEnter = 2, MdEventExit = 3

    MdLlist* = object
      next*: ptr MdLlist
      data*: ptr

    MdNodeObj*   = distinct object
    MdNode*      = ptr MdNodeObj
    MdIterObj*   = distinct object
    MdIter*      = ptr MdIterObj

    MdDoucment* = object
      root: MdNode

proc cmark_markdown_to_html(s: cstring, l: csize_t, opt: cint): cstring
    {.cmark.}

proc cmark_gfm_core_extensions_ensure_registered(): void {.cmark.}
proc cmark_to_html(s: cstring, l: cint, opt: cint, w: cint): cstring {.cmark.}
proc cmark_to_man(s: cstring, l: cint, opt: cint, w: cint): cstring {.cmark.}
proc cmark_to_latex(s: cstring, l: cint, opt: cint, w: cint): cstring {.cmark.}
proc cmark_to_plaintext(s: cstring, l: cint, opt: cint, w: cint): cstring
    {.cmark.}

include "headers/cmark-gfm.nim"
include "headers/cmark-gfm-extensions.nim"

{.emit: """
static inline void
add_extension(cmark_parser *parser, char *name) {
  cmark_syntax_extension *ext = cmark_find_syntax_extension(name);
  cmark_parser_attach_syntax_extension(parser, ext);
}

static inline cmark_node *
core_markdown_parse(char *s, int len, int opts)
{
  cmark_parser *parser = cmark_parser_new(opts);
  cmark_node   *root;

  add_extension(parser, "table");
  add_extension(parser, "strikethrough");
  add_extension(parser, "autolink");
  add_extension(parser, "tagfilter");
  add_extension(parser, "tasklist");

  cmark_parser_feed(parser, s, len);
  root = cmark_parser_finish(parser);

  cmark_parser_free(parser);
  return root;
}

char *
cmark_to_html(char *s, int len, int opts, int ignore)
{
  char         *result;
  cmark_node   *root;

  root   = core_markdown_parse(s, len, opts);
  result = cmark_render_html(root, opts, NULL);
  cmark_node_free(root);

  return result;
}

char *
cmark_to_man(char *s, int len, int opts, int width)
{
  char         *result;
  cmark_node   *root;

  root   = core_markdown_parse(s, len, opts);
  result = cmark_render_man(root, opts, width);
  cmark_node_free(root);

  return result;
}

char *
cmark_to_plaintext(char *s, int len, int opts, int width)
{
  char         *result;
  cmark_node   *root;

  root   = core_markdown_parse(s, len, opts);
  result = cmark_render_plaintext(root, opts, width);
  cmark_node_free(root);

  return result;
}

char *
cmark_to_latex(char *s, int len, int opts, int width)
{
  char         *result;
  cmark_node   *root;

  root   = core_markdown_parse(s, len, opts);
  result = cmark_render_latex(root, opts, width);
  cmark_node_free(root);

  return result;
}
""".}

proc register_gfm_extensions() =
  once:
    cmark_gfm_core_extensions_ensure_registered()

var minTerminalWidth = 20

template gfmTemplate(cfunc: untyped) =
  register_gfm_extensions()

  var
    optV: int = 0
    realWidth = width

  if width < minTerminalWidth:
    realWidth = terminalWidth()
    if realWidth < minTerminalWidth:
      realWidth = minTerminalWidth

  for item in opts:
    optV = optv or int(item)

  var cstr = cfunc(cstring(s), cint(s.len()), cint(optV), cint(realWidth))
  result   = $(cstr)
  dealloc(cstr)

proc markdownToHtml*(s: string, opts: openarray[MdOpts] = [MdSmart]): string =
  var width = 0 # This gets ignored for markdownToHtml
  gfmTemplate(cmark_to_html)


proc markdownToMan*(s: string, opts: openarray[MdOpts] = [MdSmart],
                    width = -1): string =
  gfmTemplate(cmark_to_man)

proc markdownToPlaintext*(s: string, opts: openarray[MdOpts] = [MdSmart],
                          width = -1): string =
  gfmTemplate(cmark_to_plaintext)

proc markdownToLatex*(s: string, opts: openarray[MdOpts] = [MdSmart],
                      width = -1): string =
  gfmTemplate(cmark_to_latex)
