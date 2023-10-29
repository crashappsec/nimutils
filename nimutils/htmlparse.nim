## Wraps libgumbo for fast, standards compliant HTML parsing.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022 - 2023, Crash Override, Inc.

import tables, strutils, unicode

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
  var walker = Walker(root: nil, cur: nil)

  make_gumbo(cstring(html), cast[pointer](addr walker))
  result = walker.root


include "headers/gumbo.nim"

{.emit: """
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
