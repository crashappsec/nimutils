import std/[net, httpclient, uri, math, os, streams, strutils, openssl, posix]
import "."/[managedtmp, logging]

type HttpStatusError* = object of ValueError
  code*: int

proc newHttpException*(
    code:            int,
    message:         string,
    parentException: ref Exception = nil,
): ref HttpStatusError =
  result = (ref HttpStatusError)(code: code, msg: message, parent: parentException)

var netDefaultUserAgent = defUserAgent

proc getDefaultUserAgent*(): string =
  netDefaultUserAgent

proc setDefaultUserAgent*(agent: string) =
  netDefaultUserAgent = agent

proc getRootCAStoreContent(): string =
  const
    caWiki  = "https://wiki.mozilla.org/CA/Included_Certificates"
    # link is taken directly from wiki page above
    # p.s. kind of odd its to salesforce vs one of mozilla-owned domains :shrug:
    caURL   = "https://ccadb.my.salesforce-sites.com/mozilla/IncludedRootsPEMTxt?TrustBitsInclude=Websites"
    cache   = "mozilla-root-store-" & CompileDate # cache certs by day
    curlCmd = "curl -fsSL --retry 5 '" & caURL & "'"
    (contents, curlExitCode) = gorgeEx(curlCmd, cache=cache)
  if curlExitCode != 0:
    raise newException(
      ValueError,
      "Could not download CA root store: " & contents
    )
  const
    opensslCmd             = "openssl storeutl -noout -certs /dev/stdin"
    (check, checkExitCode) = gorgeEx(opensslCmd, input=contents)
    checkLines             = check.splitLines()
  if checkExitCode != 0:
    raise newException(
      ValueError,
      "Could not validate CA root store certificates. " &
      "Maybe server didnt return valid PEM file? " &
      check
    )
  echo("Embedding Mozilla Root CA store with certificates " & checkLines[^1].toLower())
  echo("For more information see " & caWiki)
  contents

# as this is global managed tmp path (cleaned up at end of the process)
# we need to keep track of the pid which created the tmp file
# and if another pid wants to use bundled certs, for it to create
# its own tmp managed file as otherwise cert file can get cleaned up
# while trying to use it
var tmpCAStore = ""
var tmpCaStorePid = getpid()
proc getCAStorePath*(): string =
  let pid = getpid()
  if tmpCaStorePid == pid and tmpCAStore != "":
    return tmpCAStore
  const contents = getRootCAStoreContent()
  try:
    let tmp = writeNewTempFile(contents, "cabundle", ".pem")
    tmpCAStore = tmp
    tmpCaStorePid = pid
    trace("net: pid(" & $pid & ") saved bundled cers to " & tmp)
    return tmp
  except:
    trace("net: pid(" & $pid & ") could not write bundled certs to tmp file: " & getCurrentExceptionMsg())
    raise

{.emit: """
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <unistd.h>

#include <stdio.h>

// Cloudflare DNS
const char * dummy_dst  = "1.1.1.1";
const int    dummy_port = 53;

char *
get_external_ipv4_address()
{
    struct sockaddr_in addr;
    struct sockaddr_in sa      = {0, };
    int                fd      = socket(PF_INET, SOCK_DGRAM, 0);
    char              *result  = calloc(sizeof(char), INET_ADDRSTRLEN);
    socklen_t          addrlen = sizeof(addr);


    sa.sin_family      = AF_INET;
    sa.sin_addr.s_addr = inet_addr(dummy_dst);
    sa.sin_port        = htons(dummy_port);

    connect(fd, (struct sockaddr *)&sa, sizeof(sa));
    getsockname(fd, (struct sockaddr *)&addr, &addrlen);
    close(fd);
    inet_ntop(AF_INET, &addr.sin_addr, result, INET_ADDRSTRLEN);

    return result;
}
""".}

proc get_external_ipv4_address() : cstring {.cdecl, importc.}

proc getMyIpV4Addr*(): string =
  ## Portably returns the primary IPv4 address as determined by the
  ## machine's routing table. However, this does require internet
  ## access.
  var s  = get_external_ipv4_address()
  result = $(s)

proc timeoutGuard(client: HttpClient, url: Uri | string) =
  # https://github.com/nim-lang/Nim/issues/6792
  # https://github.com/nim-lang/Nim/issues/14807
  # std/httpclient request() does not honor timeout param for
  # connect timeouts and if the TCP connection cannot be established
  # in some cases it will wait until /proc/sys/net/ipv4/tcp_syn_retries
  # is exhausted which is ~130sec
  # by trying regular connect() with timeout first we can ensure
  # TCP connection can be established before attempting to make
  # HTTP request
  if client.timeout > 0:
    let uri = when url is string:
      parseUri(url)
    else:
      url
    let hostname = uri.hostname
    # port is optional in the Uri so we use default ports
    var port: Port
    if uri.port == "":
      port = if uri.scheme == "https": Port(443)
             else:                     Port(80)
    else:
      port = Port(uri.port.parseInt)
    try:
      let socket = newSocket()
      # this throws the same TimeoutError http request throws
      socket.connect(hostname, port, timeout = client.timeout)
      socket.close()
    except OSError:
      # in some cases when the hostname is non-routable IP, OS raises
      # its own error via errno which for example can be EINVAL:
      # https://linux.die.net/man/3/connect
      # > The address_len argument is not a valid length for the address
      # > family; or invalid address family in the sockaddr structure.
      # however as the the errno description can be confusing "Invalid argument"
      # this makes it clear its an OS error, not a nim bug where an invalid
      # argument is passed to a function.
      raise newException(OSError, "Could not connect due to OS raising: " & getCurrentExceptionMsg())

template withRetry(retries: int, firstRetryDelayMs: int, c: untyped) =
  # retry code block with exponential backoff
  var attempts = 0
  while attempts <= retries:
    try:
      c
      break
    except SslError:
      raise
    except:
      if attempts == retries:
        # reraise last exception to bubble error up
        raise
      let delayMs = firstRetryDelayMs * (2 ^ attempts)
      if delayMs > 0:
        sleep(delayMs)
      attempts += 1

proc check*(response: Response,
            url: Uri | string,
            acceptStatusCodes: openArray[Slice[int]] = @[],
            rejectStatusCodes: openArray[Slice[int]] = @[],
           ): Response =
  let code = int(response.code())
  if len(acceptStatusCodes) > 0:
    var matched = false
    for range in acceptStatusCodes:
      if range.contains(code):
        matched = true
        break
    if not matched:
      raise newHttpException(
        code    = code,
        message = $url & " failed with " & response.status & " " & response.body(),
      )
  for range in rejectStatusCodes:
    if range.contains(code):
      raise newHttpException(
        code    = code,
        message = $url & " failed with " & response.status & " " & response.body(),
      )
  return response

proc safeRequest(client: HttpClient,
                 url: Uri | string,
                 httpMethod: HttpMethod | string = HttpGet,
                 body = "",
                 headers: HttpHeaders = nil,
                 multipart: MultipartData = nil,
                 retries: int = 0,
                 connectRetries: int = 0,
                 firstRetryDelayMs: int = 0,
                 acceptStatusCodes: openArray[Slice[int]] = @[],
                 rejectStatusCodes: openArray[Slice[int]] = @[],
                 ): Response =
  withRetry(connectRetries, firstRetryDelayMs):
    timeoutGuard(client, url)
  withRetry(retries, firstRetryDelayMs):
    # all vars are accessed from outer scope
    let response = client.request(url = url,
                                  httpMethod = httpMethod,
                                  body = body,
                                  headers = headers,
                                  multipart = multipart)
    return response.check(url               = url,
                          acceptStatusCodes = acceptStatusCodes,
                          rejectStatusCodes = rejectStatusCodes)

# https://github.com/nim-lang/Nim/blob/a45f43da3407dbbf8ecd15ce8ecb361af677add7/lib/pure/httpclient.nim#L380-L386
# similar to stdlib but defaults to bundled CAs
proc getSSLContext(caFile:           string = "",
                   verifyMode               = CVerifyPeer,
                   preferBundledCerts: bool = false,
                   ): SslContext =
  if caFile != "":
    # note when caFile is provided there is no try..except
    # otherwise we would silently fallback to bundled CA root store
    # if caFile is invalid/does not exist
    return newContext(verifyMode = verifyMode, caFile = caFile)
  else:
    if preferBundledCerts:
      return newContext(verifyMode = verifyMode, caFile = getCAStorePath())
    try:
      return newContext(verifyMode = verifyMode)
    except:
      return newContext(verifyMode = verifyMode, caFile = getCAStorePath())

proc createHttpContext(uri: Uri,
                       maxRedirects: int = 3,
                       timeout: int = 1000, # in ms - 1 second
                       pinnedCert: string = "",
                       preferBundledCerts: bool = false,
                       verifyMode = CVerifyPeer,
                       disallowHttp: bool = false,
                       userAgent: string = netDefaultUserAgent,
                       ): (SslContext, HttpClient) =
  try:
    let
      # always pass ssl context to client
      # as otherwise if http server returns redirect to https
      # nim segfaults vs throwing exception
      context = getSSLContext(caFile             = pinnedCert,
                              verifyMode         = verifyMode,
                              preferBundledCerts = preferBundledCerts)
      client  = newHttpClient(sslContext   = context,
                              userAgent    = userAgent,
                              timeout      = timeout,
                              maxRedirects = maxRedirects)

    if client == nil:
      raise newException(ValueError, "Invalid HTTP configuration")

    return (context, client)

  except:
    trace("net: pid(" & $getpid() & ") could not get http client with ssl context: " & getCurrentExceptionMsg())
    trace("net: pinnedCert=" & pinnedCert)
    trace("net: verifyMode=" & $verifyMode)
    trace("net: preferBundledCerts=" & $preferBundledCerts)
    raise

proc safeRequest*(url: Uri | string,
                  httpMethod: HttpMethod | string = HttpGet,
                  body = "",
                  headers: HttpHeaders = nil,
                  multipart: MultipartData = nil,
                  retries: int = 0,
                  connectRetries: int = 0,
                  firstRetryDelayMs: int = 0,
                  timeout: int = 1000,
                  pinnedCert: string = "",
                  preferBundledCerts: bool = false,
                  autoPreferBundledCerts: bool = true,
                  verifyMode = CVerifyPeer,
                  maxRedirects: int = 3,
                  disallowHttp: bool = false,
                  acceptStatusCodes: openArray[Slice[int]] = @[],
                  rejectStatusCodes: openArray[Slice[int]] = @[],
                  userAgent: string = netDefaultUserAgent,
                  ): Response =
  let uri = when url is string:
    parseUri(url)
  else:
    url

  var preferBundledCerts = preferBundledCerts
  if uri.scheme == "http":
    if disallowHttp:
      raise newException(ValueError, "http:// URLs not allowed (only https).")
    elif pinnedCert != "":
      raise newException(ValueError, "Pinned cert not allowed with http " &
                                     "URL (only https).")
    if autoPreferBundledCerts:
      # if we know we are making request to http://
      # do not load system CA certs and instead attempt to use bundled certs
      # in case of https direct but of course if that fails, fallback to
      # system CA certs
      preferBundledCerts = true

  let (context, client) = createHttpContext(
    uri                = uri,
    maxRedirects       = maxRedirects,
    timeout            = timeout,
    pinnedCert         = pinnedCert,
    verifyMode         = verifyMode,
    disallowHttp       = disallowHttp,
    userAgent          = userAgent,
    preferBundledCerts = preferBundledCerts,
  )
  try:
    return client.safeRequest(url               = uri,
                              httpMethod        = httpMethod,
                              body              = body,
                              headers           = headers,
                              multipart         = multipart,
                              retries           = retries,
                              connectRetries    = connectRetries,
                              firstRetryDelayMs = firstRetryDelayMs,
                              acceptStatusCodes = acceptStatusCodes,
                              rejectStatusCodes = rejectStatusCodes)

  except SslError:
    if preferBundledCerts and pinnedCert != "":
      # if the cert is not pinned and bundled certs are preferred
      # ignore error to retry with system certs
      discard
    else:
      raise
  finally:
    context.destroyContext()
    client.close()

  trace("net: retrying request without bundled certs: " & getCurrentExceptionMsg())
  # retry without bundled certs preference which will
  # attempt to use system root certs
  return safeRequest(
    url                    = uri,
    httpMethod             = httpMethod,
    body                   = body,
    headers                = headers,
    multipart              = multipart,
    retries                = retries,
    connectRetries         = connectRetries,
    firstRetryDelayMs      = firstRetryDelayMs,
    timeout                = timeout,
    pinnedCert             = pinnedCert,
    preferBundledCerts     = false,
    autoPreferBundledCerts = false,
    verifyMode             = verifyMode,
    maxRedirects           = maxRedirects,
    disallowHttp           = disallowHttp,
    acceptStatusCodes      = acceptStatusCodes,
    rejectStatusCodes      = rejectStatusCodes,
    userAgent              = userAgent,
  )
