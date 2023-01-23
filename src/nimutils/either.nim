## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.
##
import macros

type
  Either*[T, U] = object
    tVal: T
    uVal: U
    hasT: bool

  NeitherDefect* = object of Defect
  IsOtherDefect* = object of Defect

proc either*[T, U](x: T|U): Either[T, U] =
  # Set the value of an Either object.
  when typeof(x) is T:
    result.tVal = x
    result.uVal = default(U)
    result.hasT = true
  else:
    result.uVal = x
    result.hasT = false
    result.tVal = default(T)

proc isA*[T, U](x: Either[T, U], t: typedesc): bool =
  when T is t: return x.hasT
  elif U is t: return not x.hasT
  else:
    static:
      error("In call to isA(x: " & $(typeof(x)) & ", T), T must be of type " &
        $(typeof(x.tVal)) & " or " & $(typeof(x.uVal)))
  
proc left*[T, U](x: Either[T, U]): T =
  if x.isA(T):
    return x.tVal
  else:
    raise newException(IsOtherDefect, "Unpack error.")

proc right*[T, U](x: Either[T, U]): U =
  if x.isA(U):
    return x.uVal
  else:
    raise newException(IsOtherDefect, "Unpack error.")

template get*[T, U](x: Either[T, U], t: typedesc): auto =
  when t is T:
    left(x)
  elif t is U:
    right(x)
  else:
    static:
      macros.error("Invalid type to " & $(typeof(x)) & ".get(): " & $(t))
    nil

proc `==`*[T, U](a, b: Either[T, U]): bool {.inline.} =
  if a.isA(T):
    if not b.isA(T):
      return false
    return a.tVal == b.tVal
  elif b.isA(T):
      return false
    
  if a.isA(U):
    if not b.isA(U):
      return false
    return a.uVal == b.uVal
  elif b.isA(U):
    return false

  raise newException(NeitherDefect, "Either objects are not initialized")
    
proc `$`*[T, U](self: Either[T, U]): string =
  if self.isA(T):
    result = "either("
    result.addQuoted(self.tVal)
    result.add(")")
  elif self.isA(U):
    result = "either("
    result.addQuoted(self.uVal)
    result.add(")")
  else:
    raise newException(NeitherDefect, "Either objects are not initialized")    

macro EitherDecl*(name: untyped, x: typedesc, y: typedesc) =
  ## Declare a concrete Either type and set up auto-converters.
  return quote do:
    type `name` = Either[`x`, `y`]

    converter xConverter*(a: `x`): `name` =
      result.tVal = a
      result.hasT = true

    converter yConverter*(b: `y`): `name` =
      result.uVal = b
      result.hasT = false
