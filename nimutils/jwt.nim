import strutils, std/[base64, json, times]

type
  JwtHeader* = ref object
    json*: JsonNode

  JwtPayload* = ref object
    exp*:  Time
    json*: JsonNode

  JwtToken* = ref object
    header*:    JwtHeader
    payload*:   JwtPayload
    signature*: string
    value*:     string

proc `$`*(token: JwtToken): string =
  return token.value

template isExpired*(token: JwtToken): bool =
  (fromUnix(0) < token.payload.exp) and (token.payload.exp < getTime())

template isStillAlive*(token: JwtToken): bool =
  not (token.isExpired())

template base64Pad(data: string): string =
  data & "=".repeat(len(data) mod 4)

proc parseJwtToken*(token: string): JwtToken =
  let parts = token.split(".")
  if len(parts) != 3:
    raise newException(ValueError, "Invalid JWT")
  let
    headerJson  = parseJson(base64.decode(base64Pad(parts[0])))
    payloadJson = parseJson(base64.decode(base64Pad(parts[1])))
    signature   = base64.decode(base64Pad(parts[2]))
  var exp       = fromUnix(0)
  if "exp" in payloadJson:
    exp         = fromUnix(payloadJson["exp"].getInt())
  let
    header      = JwtHeader(json: headerJson)
    payload     = JwtPayload(json: payloadJson, exp: exp)
  return JwtToken(header: header, payload: payload,
                  signature: signature, value: token)
