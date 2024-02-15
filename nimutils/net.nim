import std/[asyncfutures, net, httpclient, uri, math, os, streams, strutils]
import openssl
import ./managedtmp

proc getRootCAStoreContent(): string =
  const
    caWiki  = "https://wiki.mozilla.org/CA/Included_Certificates"
    # link is taken directly from wiki page above
    # p.s. kind of odd its to salesforce vs one of mozilla-owned domains :shrug:
    caURL   = "https://ccadb.my.salesforce-sites.com/mozilla/IncludedRootsPEMTxt?TrustBitsInclude=Websites"
    cache   = "mozilla-root-store-" & CompileDate # cache certs by day
    curlCmd = "curl -fsSL --retry 5 " & caURL
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

var tmpCAStore = ""
proc getCAStorePath(): string =
  const contents = getRootCAStoreContent()
  if tmpCAStore != "":
    return tmpCAStore
  let (stream, tmp) = getNewTempFile("cabundle", ".pem")
  stream.write(contents)
  stream.close()
  tmpCAStore = tmp
  return tmp

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

proc timeoutGuard(client: HttpClient | AsyncHttpClient, url: Uri | string) =
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
    let socket = newSocket()
    # this throws the same TimeoutError http request throws
    socket.connect(hostname, port, timeout = client.timeout)
    socket.close()

template withRetry(retries: int, firstRetryDelayMs: int, c: untyped) =
  # retry code block with exponential backoff
  var attempts = 0
  while attempts <= retries:
    try:
      c
    except:
      if attempts == retries:
        # reraise last exception to bubble error up
        raise
      let delayMs = firstRetryDelayMs * (2 ^ attempts)
      if delayMs > 0:
        sleep(delayMs)
      attempts += 1
  raise newException(ValueError, "retried code block didnt return. this should never happen")

proc safeRequest*(client: AsyncHttpClient,
                  url: Uri | string,
                  httpMethod: HttpMethod | string = HttpGet,
                  body = "",
                  headers: HttpHeaders = nil,
                  multipart: MultipartData = nil,
                  retries: int = 0,
                  firstRetryDelayMs: int = 0,
                  ): Future[AsyncResponse] =
  timeoutGuard(client, url)
  withRetry(retries, firstRetryDelayMs):
    return client.request(url = url, httpMethod = httpMethod, body = body,
                          headers = headers, multipart = multipart)

proc safeRequest*(client: HttpClient,
                  url: Uri | string,
                  httpMethod: HttpMethod | string = HttpGet,
                  body = "",
                  headers: HttpHeaders = nil,
                  multipart: MultipartData = nil,
                  retries: int = 0,
                  firstRetryDelayMs: int = 0,
                  ): Response =
  timeoutGuard(client, url)
  withRetry(retries, firstRetryDelayMs):
    return client.request(url = url, httpMethod = httpMethod, body = body,
                          headers = headers, multipart = multipart)

# https://github.com/nim-lang/Nim/blob/a45f43da3407dbbf8ecd15ce8ecb361af677add7/lib/pure/httpclient.nim#L380-L386
# similar to stdlib but defaults to bundled CAs
proc getSSLContext(caFile: string = ""): SslContext =
  if caFile != "":
    # note when caFile is provided there is no try..except
    # otherwise we would silently fail to bundled CA root store
    # if caFile is invalid/does not exist
    return newContext(verifyMode = CVerifyPeer, caFile = caFile)
  else:
    try:
      return newContext(verifyMode = CVerifyPeer)
    except:
      return newContext(verifyMode = CVerifyPeer, caFile = getCAStorePath())

proc createHttpClient*(uri: Uri = parseUri(""),
                       maxRedirects: int = 3,
                       timeout: int = 1000, # in ms - 1 second
                       pinnedCert: string = "",
                       disallowHttp: bool = false,
                       userAgent: string = defUserAgent,
                       ): HttpClient =
  var context: SslContext

  if uri.scheme in @["", "https"]:
    context = getSSLContext(caFile = pinnedCert)
  else:
    if disallowHttp:
      raise newException(ValueError, "http:// URLs not allowed (only https).")
    elif pinnedCert != "":
      raise newException(ValueError, "Pinned cert not allowed with http " &
                                     "URL (only https).")

  let client = newHttpClient(sslContext   = context,
                             userAgent    = userAgent,
                             timeout      = timeout,
                             maxRedirects = maxRedirects)

  if client == nil:
    raise newException(ValueError, "Invalid HTTP configuration")

  return client

proc safeRequest*(url: Uri | string,
                  httpMethod: HttpMethod | string = HttpGet,
                  body = "",
                  headers: HttpHeaders = nil,
                  multipart: MultipartData = nil,
                  retries: int = 0,
                  firstRetryDelayMs: int = 0,
                  timeout: int = 1000,
                  pinnedCert: string = "",
                  maxRedirects: int = 3,
                  disallowHttp: bool = false,
                  ): Response =
  let uri = when url is string:
    parseUri(url)
  else:
    url
  let client = createHttpClient(uri           = uri,
                                maxRedirects  = maxRedirects,
                                timeout       = timeout,
                                pinnedCert    = pinnedCert,
                                disallowHttp  = disallowHttp)
  try:
    return client.safeRequest(url               = uri,
                              httpMethod        = httpMethod,
                              body              = body,
                              headers           = headers,
                              multipart         = multipart,
                              retries           = retries,
                              firstRetryDelayMs = firstRetryDelayMs)
  finally:
    client.close()
