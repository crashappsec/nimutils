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
  var s  = get_external_ipv4_address()
  result = $(s)
