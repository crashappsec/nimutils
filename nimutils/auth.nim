import tables, std/[base64, httpclient, times]
import jwt, pubsub

proc jwtValidate(auth: AuthConfig) =
  let token = parseJwtToken(auth.params["token"])
  if token.isExpired():
    raise newException(ValueError, "JWT token has expired since " & $(token.payload.exp))

proc jwtInjectHeaders(auth: AuthConfig, headers: HttpHeaders): HttpHeaders =
  let token = auth.params["token"]
  headers["Authorization"] = "Bearer " & token
  return headers

proc basicInjectHeaders(auth: AuthConfig, headers: HttpHeaders): HttpHeaders =
  let
    creds   = auth.params["username"] & ":" & auth.params["password"]
    encoded = base64.encode(creds)
  headers["Authorization"] = "Basic " & encoded
  return headers

proc addJwtAuth*() =
  let
    record = AuthImplementation()
    keys = {
      "token": true,
    }.toTable()
  record.validate      = jwtValidate
  record.injectHeaders = jwtInjectHeaders
  record.keys          = keys
  registerAuth("jwt", record)

proc addBasicAuth*() =
  let
    record = AuthImplementation()
    keys = {
      "username": true,
      "password": true,
    }.toTable()
  record.injectHeaders = basicInjectHeaders
  record.keys          = keys
  registerAuth("basic", record)

proc addDefaultAuths*() =
  addJwtAuth()
  addBasicAuth()
