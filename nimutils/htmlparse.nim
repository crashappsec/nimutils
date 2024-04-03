## Wraps libgumbo for fast, standards compliant HTML parsing.
## Really only wraps the most basic functionality, though!
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022 - 2023, Crash Override, Inc.

import tables, strutils, unicode, grid, libwrap, markdown

type
  HtmlNodeType* = enum
    HtmlDocument   = 0,
    HtmlElement    = 1,
    HtmlText       = 2,
    HtmlCData      = 3,
    HtmlComment    = 4,
    HtmlWhiteSpace = 5,
    HtmlTemplate   = 6

  HtmlNode* = ref object
    parent*:   HtmlNode
    kind*:     HtmlNodeType
    contents*: string
    children*: seq[HtmlNode]
    attrs*:    OrderedTable[string, string]

  Walker = object
    root: HtmlNode
    cur:  HtmlNode

proc stringize(n: HtmlNode, indent = 0): string =
  let c = n.contents.replace("\n", "\\n")
  result = Rune(' ').repeat(indent) & " - " & c & " (" & $(n.kind) & ")" & "\n"

  for kid in n.children:
    result &= kid.stringize(indent + 2)

proc `$`*(n: HtmlNode): string =
  return n.stringize()

proc make_gumbo(html: cstring, userdata: pointer): void {.cdecl, importc.}

proc enter_callback(ctx: var Walker, kind: HtmlNodeType, contents: cstring)
    {.exportc, cdecl.} =
  let newNode = HtmlNode(parent: ctx.cur, kind: kind, contents: $(contents),
                         children: @[])

  if ctx.root == nil:
    ctx.root = newNode
  else:
    ctx.cur.children.add(newNode)

  case kind
  of HtmlDocument, HtmlTemplate, HtmlElement:
    ctx.cur = newNode
  else:
    discard

proc leave_callback(ctx: var Walker) {.exportc, cdecl.} =
  ctx.cur = ctx.cur.parent

proc add_attribute(ctx: var Walker, n, v: cstring) {.exportc, cdecl.} =
  let
    name = $(n)
    val  = $(v)

  ctx.cur.attrs[name] = val

proc parseDocument*(html: string): HtmlNode =
  ## Converts a string consisting of well-formed HTML into a tree
  ## representing the DOM.
  ##
  ## If the string is not well-formed, results are undefined.  That
  ## means, since this call just uses the `gumbo` library to construct
  ## the tree, we're not too well versed in the consequences of using
  ## it with bunk input. We've gotten passable results, but with very
  ## little experience here.
  var walker = Walker(root: nil, cur: nil)

  make_gumbo(cstring(html), cast[pointer](addr walker))
  result = walker.root

{.emit: """
#include "gumbo.h"
#include <stdlib.h>
#include <string.h>

// We're doing a lot of string duplication in here that we don't
// need to do, and can optimize later. Was done for expedience.

static char *
element_name(GumboNode *node)
{
    // This function always copys out the tag name to avoid having to
    // worry about managing string slices.
    // We must free it.

    GumboElement *elem = &(node->v.element);

    if (elem->tag != GUMBO_TAG_UNKNOWN) {
        return strdup(gumbo_normalized_tagname(elem->tag));
    }
    char *ret = (char *)calloc(1, elem->original_tag.length);
    memcpy(ret, elem->original_tag.data, elem->original_tag.length);
    return ret;
}

static inline char *
get_text(GumboNode *node)
{
  GumboText *tobj = &node->v.text;

  return strdup(tobj->text);
}

static void
add_attributes(GumboVector *attributes, void *userdata)
{
  for (int i = 0; i < attributes->length; i++) {
    GumboAttribute *x    = attributes->data[i];
    char           *name = strdup(x->name);
    char           *val  = NULL;

    if(strlen(x->value) != 0) {
      val  = strdup(x->value);
    }
    add_attribute(userdata, name, val);
    free(name);
    if(strlen(x->value) != 0) {
      free(val);
    }
  }
}

static void
tree_traverse(GumboNode *node, void *userdata)
{
    GumboVector *children = NULL;
    char        *contents;

    switch (node->type) {
      case GUMBO_NODE_ELEMENT:
      case GUMBO_NODE_TEMPLATE:
        contents = element_name(node);
        break;
      default:
        contents = get_text(node);
    }

    enter_callback(userdata, node->type, contents);
    free(contents);

    switch (node->type) {
    case GUMBO_NODE_ELEMENT:
    case GUMBO_NODE_TEMPLATE:
      add_attributes(&node->v.element.attributes, userdata);
      children = &node->v.element.children;
      recurse:
        for (int i = 0; i < children->length; i++) {
            tree_traverse(children->data[i], userdata);
        }
        leave_callback(userdata);
        break;
    case GUMBO_NODE_DOCUMENT:
      children = &node->v.document.children;
      goto recurse;
    default:
        return;
    }
    return;
}

void
make_gumbo(char *html, void *userdata)
{
  GumboOutput *res = gumbo_parse(html);
  tree_traverse(res->root, userdata);
  gumbo_destroy_output(res);
}
"""}
proc htmlToFlowOneNode(n: HtmlNode, l: var seq[Grid], s: var Rich)


proc extractOneRow(n: HtmlNode): seq[Grid] =
  var r: Rich = c4str("")

  for item in n.children:
    if item.kind notin [HtmlElement, HtmlTemplate]:
      continue

    item.htmlToFlowOneNode(result, r)

proc htmlToFlowOneNode(n: HtmlNode, l: var seq[Grid], s: var Rich) =
  var stashed_contents: seq[Grid]

  case n.kind
  of HtmlDocument:
    for item in n.children:
      item.htmlToFlowOneNode(l, s)

    return
  of HtmlText, HtmlCData:
    if s.rich_len() == 0:
      s = c4str(n.contents)
    else:
      s = string_concat(s, c4str(n.contents))
    return

  of HtmlElement, HtmlTemplate:
    if n.contents.startswith('<') and n.contents[^1] == '>':
      n.contents = n.contents[1 ..< ^1]

    # handle the contents below, it's the bulk of this function
    # And don't need extra nesting.
  else:
    return

  case n.contents
  of "br":
    if s.rich_len() != 0:
      l.add(cell(s, "p"))
      s = c4str("")

  of "a":
    let url = if "href" in n.attrs: n.attrs["href"] else: "https://unknown"
    for item in n.children:
      n.htmlToFlowOneNode(l, s)

    let rich_url: Rich = c4Str("(" & url & ")")

    s = string_concat(s, rich_url)
  of "ol":
    if s.rich_len() != 0:
      l.add(cell(s, "p"))
      s = c4str("")

    stashed_contents = l
    l                = @[]
    for item in n.children:
      item.htmlToFlowOneNode(l, s)


    if l.len() != 0:
      l = stashed_contents & @[ol(l)]
    else:
      l = stashed_contents

  of "ul":
    if s.rich_len() != 0:
      l.add(cell(s, "p"))
      s = c4str("")

    stashed_contents = l
    l                = @[]
    for item in n.children:
      item.htmlToFlowOneNode(l, s)


    if l.len() != 0:
      l = stashed_contents & @[ol(l)]
    else:
      l = stashed_contents

  of "h1", "h2", "h3", "h4", "h5", "h6", "td", "th":
    if s.rich_len() != 0:
      l.add(cell(s, "p"))
      s = c4str("")

    var list_len = l.len()

    for item in n.children:
      item.htmlToFlowOneNode(l, s)
      if l.len() > list_len:
        list_len = l.len()
        l[^1] = cell(l[^1], n.contents)

  of "em", "i", "b", "bold", "strong", "u", "caption", "text", "plain",
       "underline", "strikethrough", "strikethru", "italic":
    # Ideally children produce only strings.
    var
      stash  = s
      rstyle = lookup_cell_style(cstring(n.contents))
      sstyle = if rstyle != nil:
                 get_string_style(rstyle)
               else:
                 0

    s = c4str("")

    for item in n.children:
      item.htmlToFlowOneNode(l, s)
      if rstyle != nil and s.rich_len() != 0:
        s.apply_style(sstyle)

      if s.rich_len() != 0:
        if stash.rich_len() != 0:
          stash = string_concat(stash, s)
        else:
          stash = s

    s = stash

  of "html", "body", "head", "blockquote", "div", "code", "p", "q":
    if s.rich_len() != 0:
      l.add(cell(s, "p"))
      s = c4str("")

    stashed_contents = l
    l                = @[]

    for item in n.children:
      item.htmlToFlowOneNode(l, s)

    if l.len() != 0:
      l = stashed_contents & @[flow(l)]
    else:
      l = stashed_contents

  of "table":
    if s.rich_len() != 0:
      l.add(cell(s, "p"))
      s = c4str("")

    var
      cells:   seq[seq[Grid]]
      title:   string
      caption: string
      rows   = 0
      hrows  = 0

    for item in n.children:
      if item.kind == HtmlWhiteSpace or item.contents == "colgroup":
        # We'll hit colgroup some other time.
        continue
      case item.contents
      of "caption":
        item.htmlToFlowOneNode(l, s)
        caption = $(to_cstring(s))
        s = c4str("")
      of "title":
        item.htmlToFlowOneNode(l, s)
        title = $(to_cstring(s))
        s = c4str("")
      of "thead":
        for sub in n.children:
          if item.contents == "tr":
            rows  += 1
            hrows += 1
            cells &= sub.extract_one_row()
      of "tfoot", "tbody":
        for sub in n.children:
          if item.contents == "tr":
            rows  += 1
            cells &= sub.extract_one_row()
      else:
        discard

    l.add(table(cells, title, caption, header_rows = hrows))
  else:
    discard # TODO

proc htmlToFlow*(n: HtmlNode): Grid =
  var
    flow_items:   seq[Grid] = @[]
    unboxed_text: Rich = c4str("")

  htmlToFlowOneNode(n, flow_items, unboxed_text)

  return flow(flow_items)

proc htmlToFlow*(s: string, markdown = true): Grid =
  let html = if markdown:
               markdownToHtml(s)
             else:
               s

  let tree = parseDocument(html).children[1]

  result = tree.htmlToFlow()
