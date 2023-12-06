## John Viega
## john@crashoverride.com

{.emit: """
#include <stdint.h>
#include <inttypes.h>

const char hextable[] = "0123456789abcdef";

#define UR *p-- = hextable[n & 0x0f]; n >>= 4

void hex64(uint64_t n, char *p) {
  p += 16;

  UR; UR; UR; UR; UR; UR; UR; UR; UR; UR; UR; UR; UR; UR; UR;
  *p-- = hextable[n];
}

void hex128(__uint64_t *x, char *p) {
#if __BYTE_ORDER == __LITTLE_ENDIAN
  hex64(x[0], p + 16);
  hex64(x[1], p);
#else
  hex64(x[0], p);
  hex64(x[1], p + 16);
#endif 
}

#if BYTE_ORDER == __BIG_ENDIAN
#define U128LOW 0
#define U128HIGH 1
#else
#define U128LOW 1
#define U128HIGH 0
#endif

int clzp128(__uint64_t *p) {
  __uint64_t n = p[U128HIGH];
  if (!n) {
    n = p[U128LOW];
    return 64 + __builtin_clzll(n);
  } else {
    return __builtin_clzll(n);
  }
}

""".}

type
  int128*{.importc: "__int128_t", header: "<stdint.h>".} = object
  uint128*{.importc: "__uint128_t", header: "<stdint.h>".} = object

proc clzp128*(argc: pointer): cint {.importc, cdecl.}
proc hex128*(x: pointer, buf: ptr char) {.cdecl, nodecl, importc.}

func `+`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` + `y`;" .}
func `-`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` - `y`;" .}
func `*`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` * `y`;" .}
func `div`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` / `y`';" .}
func `shl`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` << `y`;" .}
func `shr`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` >> `y`;" .}
func `or`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` | `y`;" .}
func `and`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` & `y`;" .}
func `xor`*[T: int128|uint128](x, y: T): T =
  {.emit: "`result` = `x` ^ `y`;" .}
func `+=`*[T: int128|uint128](x: var T, y: T) =
  x = x + y
func `-=`*[T: int128|uint128](x: var T, y: T) =
  x = x - y
func `*=`*[T: int128|uint128](x: var T, y: T) =
  x = x * y
func high*[T: uint128](x: typedesc[T]): T =
  {.emit: "`result` = ~(__uint128_t)0;" .}
func low*[T: uint128](x: typedesc[T]): T = 0
func high*[T: int128](x: typedesc[T]): T = 
  {.emit: "`result` = (__int128_t)~(((__uint128_t)1) << 127);" .}
func low*[T: int128](x: typedesc[T]): T =
  {.emit: "`result` = (__int128_t)((__uint128_t)1) << 127;" .}
converter iToI128*[T: int|int32|int16|uint128](n: T): int128 =
  {.emit: "`result` = `n`;" .}
converter iToU128*[T: uint|uint32|uint16|int128](n: T): uint128 =
  {.emit: "`result` = `n`;" .}
  
proc `toRope`*[T: int128|uint128](x: T): string =
  var n = x
  result = newString(33)
  hex128(addr n, addr result[0])
