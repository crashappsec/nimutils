## Module for various reusable auth implementations
##
## Auth implementations are stand-alone and can be used together
## with sinks however can be used outside of them directly.
##
## Currently these auth methods are implemented:
## * basic auth
## * JWT

import std/[options, sugar, tables, base64, httpclient, times]
import "."/jwt

type
  AuthParams *      = OrderedTableRef[string, string]
  ValidateCallback* = ((AuthConfig) -> void)
  HeadersCallback*  = ((AuthConfig, HttpHeaders) -> HttpHeaders)

  AuthImplementation* = ref object
    name*:          string
    keys*:          Table[string, bool]
    validate*:      ValidateCallback
    injectHeaders*: HeadersCallback

  AuthConfig* = ref object
    name*:           string
    implementation*: AuthImplementation
    params*:         AuthParams

var allAuths:   Table[string, AuthImplementation]

proc registerAuth*(name: string, auth: AuthImplementation) =
  auth.name      = name
  allAuths[name] = auth

proc getAuthImplementation*(name: string): Option[AuthImplementation] =
  if name in allAuths:
    return some(allAuths[name])
  return none(AuthImplementation)

proc ensureParamsHaveKeys*(params: AuthParams,
                           keys: Table[string, bool]) =
  for k, v in params:
    if k notin keys:
      raise newException(ValueError, "Extraneous key: " & k)

  for k, v in keys:
    if v and k notin params:
      raise newException(ValueError, "Required key missing: " & k)

proc configAuth*(a: AuthImplementation,
                 name: string,
                 `params?`: Option[AuthParams] = none(AuthParams)
                 ): Option[AuthConfig] =
  let
    params = `params?`.get(newOrderedTable[string, string]())
    auth   = AuthConfig(name: name, implementation: a, params: params)
  ensureParamsHaveKeys(params, a.keys)
  if a.validate != nil:
    a.validate(auth)
  return some(auth)

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
