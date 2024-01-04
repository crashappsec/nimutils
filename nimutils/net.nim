import std/[asyncfutures, net, httpclient, uri, math, os]

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
    var uri: Uri
    when url is string:
      uri = parseUri(url)
    else:
      uri = url
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
