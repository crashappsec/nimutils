## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022
##
## This module is for generic boxing of values, which is useful for
## compiler symbol tables, etc. However, this is also a more flexible
## alternative to the nim Any type defined in std/typeinfo.  The major
## problem with Nim's Any type is that does not help the developer
## avoid danging pointers.  That is, if one uses an Any type in Nim,
## it uses a non-traced pointer, meaning that, if the container is the
## last reference to the object, then the object will end up dangling,
## meaning it will generally not be there when unboxing.
##
## We solve that problem by holding an object reference for anything
## we want to keep around.  Most importantly, sequences go in a
## 'crate', which holds a copy of the sequence, ensuring any
## referencable object in the sequence is properly copied and tracked.
##
## The current limitation relative to the Any type is that we
## currently are not explicitly handling the range of types that the
## Nim Any types does.  Specifically:
##
## - For primitive numeric types, the underlying storage is 64-bit
##   values, that you can then cast into the type you expect. If you
##   DO NOT know enough context to know, for instance, if the value is
##   meant to be signed or not, and you need that context, you can
##   stick it in an object wrapper.
##
## - You also need to use object wrappers for most complex Nim types
##   like Tuples, Sets and so-on, since we don't intrinsically deal
##   with them.
##
## Note that currently, there's no support for convering custom types
## to strings.
##
## Thanks very much to ElegantBeef for helping me with my fight against
## type system recursion wonkiness... the little hack for decomposing list
## item types so I can recurse was due to him.
##
## However, my major issue turned out to be that UFCS is ambiguous in
## the face of generics, and that ambiguity does not work out in favor
## of UFCS.  Specifically, foo.bar[Type](boz) I believe becomes
## foo.bar[Type](boz) instead of bar[Type](foo, boz) (as would
## typically happen).
##
## I did just learn that you can do [: instead to get UFCS semantics.
## But when you get it wrong, the error messages are not even a little
## helpful.

import std/typetraits
import std/hashes
import strutils
import tables
import json

type
    MixedKind* = enum
        MkInt, MkStr, MkFloat, MkSeq, MkBool, MkTable, MkObj
    BoxAtom = string or int64 or float64 or RootRef or SomeTableRef
    Packable* = concept x, var v
        customPack(x) is Box
        customUnpack(type Box, v)
    Box* = ref object
        case kind*: MixedKind
        of MkFloat: f*: float64
        of MkInt:   i*: int64
        of MkBool:  b*: bool
        of MkStr:   s*: string
        of MkSeq:   c*: ListCrate
        of MkObj:   o*: RootRef # If we add in object types later.
        of MkTable: t: TableCrate
    SomeTableRef = TableRef or OrderedTableRef

    # These are necessary to ensure objects don't get garbage
    # collected.  If we don't stick them into ref objects, the runtime
    # won't track us, and the objects can easily go out of scope on us.
    ListCrate = ref object of RootObj
        s: seq[Box]
    TableCrate = ref object of RootObj
        t: OrderedTableRef[Box, Box]

proc arrItemType*[T](a: openarray[T]): auto =
    return default(T)
proc arrItemType*(a: BoxAtom): BoxAtom = a

proc unpack*[T](box: Box): T =
    ## This recursively unpacks anything sitting in a Box, including
    ## custom code via the `Packable` interface.
    ##
    ## Whereas with packing the compiler will generally find it easy
    ## to figure out the type of the object you're packing, with
    ## unpack(), you'll often be specifying the type manually (though,
    ## it can be inferred from the destination variable, if the
    ## language already knows that type).
    ##
    ## If you do NOT want to unpack every layer at once, just declare
    ## the type of the destination variable appropriately. For
    ## instance, If you have boxed a `seq[seq[int]]`, calling
    ## `unpack[seq[seq[int]]]()` removes both layers of packing, but
    ## calling `unpack[seq[Box]]` just one.
    when T is string:
        return box.s
    elif T is SomeInteger:
        return cast[T](box.i)
    elif T is bool:
        return box.b
    elif T is SomeFloat:
        return cast[T](box.f)
    elif T is seq[Box]:
        result = newSeq[Box]()
        for item in box.c.s:
            result.add(item)
    elif T is seq:
        result = newSeq[typeof(result.arrItemType)]()
        for item in box.c.s:
            when typeof(result.arrItemType) is BoxAtom:
                result.add(unpack[typeof(result.arrItemType)](item))
            elif typeof(result.arrItemType) is seq:
                result.add(unpack[typeof(result.arrItemType)](item))
            else:
                raise newException(ValueError, "Invalid type to box")
    elif T is SomeTableRef:
        var
            genericParamDummy: genericParams(result.type)
            dstKey: typeof(genericParamDummy[0])
            dstVal: typeof(genericParamDummy[1])

        when T is OrderedTableRef:
            result = newOrderedTable[typeof(genericParamDummy[0]),
                                     typeof(genericParamDummy[1])]()
            for k, v in box.t.t:
                dstKey = unpack[typeof(genericParamDummy[0])](k)
                dstVal = unpack[typeof(genericParamDummy[1])](v)
                result[dstKey] = dstVal
        else:
            result = newTable[typeof(genericParamDummy[0]),
                              typeof(genericParamDummy[1])]()
            for k, v in box.t.t:
                dstKey = unpack[typeof(genericParamDummy[0])](k)
                dstVal = unpack[typeof(genericParamDummy[1])](v)
                result[dstKey] = dstVal
        # The first t is the TableCrate, the second get to the actual table
    elif T is Packable:
        var res: T
        customUnpack(box, res)
        result = res
    elif T is Box:
        return box
    else:
        raise newException(ValueError, "Destination type is not boxable.")

proc unpack*[T](box: Box, result: var T) =
    ## This really isn't necessary, but sometimes you might want to
    ## use a var param...
    var x: T = unpack[T](box)
    result = x

proc hash*(box: Box): Hash =
    ## Allow boxes of primitive types to be used as hash table keys.
    case box.kind
    of MkInt: return hash(unpack[int](box))
    of MkStr: return hash(unpack[string](box))
    of MkFloat: return hash(unpack[float](box))
    of MkBool: return hash(unpack[bool](box))
    else: raise newException(ValueError, "Invalid type for hash key")

proc pack*[T](x: T): Box =
    ## This recursively boxes sequences and dicts down to an "atomic"
    ## type, which is currently primitives, tables, other boxes, and
    ## anything implementing our `Packable` interface (called concepts
    ## in Nim... they bind on more than just function signatures.
    ##
    ## This is better than holding references to objects that may
    ## or may not be boxed, especially since we have tuple types where
    ## boxing is currently necessary.
    ##
    ## Generally with pack(), the compiler isn't going to have a problem
    ## figuring out the type to pack, so you shouldn't have to specify
    ## the parameter.
    when T is Box:
        result = x
    elif T is SomeInteger:
        result = Box(kind: MkInt, i: cast[int64](x))
    elif T is SomeFloat:
        result = Box(kind: MkFloat, f: cast[float64](x))
    elif T is bool:
        result = Box(kind: MkBool, b: x)
    elif T is string:
        result = Box(kind: MkStr, s: x)
    elif T is RootRef:
        result = Box(kind: MkObj, o: x)
    elif T is seq[Box]:
        var c = ListCrate(s: newSeq[Box]())
        result = Box(kind: MkSeq, c: c)
        for item in x:
            c.s.add(item)
    elif T is seq:
        var c = ListCrate(s: newSeq[Box]())
        for item in x:
            c.s.add(pack(item))
        result = Box(kind: MkSeq, c: c)
    elif T is SomeTableRef:
        var newdict: OrderedTableRef[Box, Box] = newOrderedTable[Box, Box]()
        for k, v in x:
            newdict[pack(k)] = pack(v)
        result = Box(kind: MkTable, t: TableCrate(t: newDict))
    elif T is Packable:
        return customPack[T](x)
    else:
        raise newException(ValueError, "Bad type to pack: " & $(T.type))

proc `$`*(x: Box): string =
    case x.kind
    of MkFloat:
        return $(x.f)
    of MkInt:
        return $(x.i)
    of MkTable:
        var addComma: bool = false

        result = "{"

        for k, val in x.t.t:
            if addComma: result = result & ", " else: addComma = true
            result = result & $(k) & " : " & $(val)

        result = result & "}"
    of MkBool:
        return $(x.b)
    of MkStr:
        return x.s
    of MkSeq:
        var s: seq[string] = @[]
        for item in x.c.s:
            s.add($(item))
        return "box[" & s.join(", ") & "]"
    of MkObj:
        return "<boxed object>"

proc boxToJson*(b: Box): string =
    var addComma: bool = false

    case b.kind
    of MkInt, MkFloat, MkBool:
        return $(b)
    of MkStr:
        return escapeJson($(b))
    of MkSeq:
        result = "["
        for item in b.c.s:
            if addComma: result = result & ", ": else: addComma = true
            result = result & item.boxToJSon()
        result = result & "]"
    of MkTable:
        result = "{ "
        for k, val in b.t.t:
            if addComma: result = result & ", " else: addComma = true
            result = result & boxToJson(k) & " : " & boxToJson(val)
        result = result & " }"
    else:
        return "null" # Boxed objects not supported

when isMainModule:
    var
        i1 = "a"
        l1 = @["a", "b", "c"]
        l2 = @["d", "e", "f"]
        l3 = @["g", "h", "i"]
        l123 = @[l1, l2, l3]
        b1, b123: Box
        o123: seq[seq[string]] = @[]
        oMy: seq[Box] = @[]
        a1 = pack(i1)

    echo typeof(a1)
    echo unpack[string](a1)
    b1 = pack(l1)
    echo b1
    echo unpack[seq[string]](b1)
    b123 = pack(l123)
    echo b123
    echo typeof(b123)
    echo typeof(o123)
    o123 = unpack[seq[seq[string]]](b123)
    echo o123
    oMy = unpack[seq[Box]](b123)
    echo oMy

    var myDict = newTable[string, seq[string]]()

    myDict["foo"] = @["a", "b"]
    myDict["bar"] = @["b"]
    myDict["boz"] = @["c"]
    myDict["you"] = @["d"]

    import streams

    let
        f = newFileStream("box.nim", fmRead)
        contents = f.readAll()[0 .. 20]

    myDict["file"] = @[contents]

    let
        dictBox = pack(myDict)
        listbox = pack(l1)

    var outlist: l1.type
    unpack(listbox, outlist)

    echo "Here's the listbox: ", listbox
    echo "Here it is unpacked: ", outlist

    var newDict: TableRef[string, seq[string]]

    unpack(dictBox, newDict)

    echo "Here's the dictbox(nothing should be quoted): ", dictBox
    echo "Here it is unpacked (should have quotes): ", newDict
    echo "Here it is, boxed, as Json: ", boxToJson(dictBox)

    # This shouldn't work w/o a custom handler.
    # import sugar
    # var v: ()->int
    # unpack[()->int](b123, v)
