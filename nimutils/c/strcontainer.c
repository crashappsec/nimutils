#include <stdint.h>
#include <string.h>
#include <stdlib.h>

typedef struct {
    int64_t  len;
    char     data[];
} real_str_t;

typedef char str_t;

str_t *
c4string_new(int64_t *len)
{
    real_str_t *real_obj = calloc(len + sizeof(int64_t) + 1, 1);

    real_obj->len = len;
    return real_obj->data;
}

str_t *
c4string_from_cstr(char *s) {
    int64_t  l      = (int64_t)strlen(s);
    str_t   *result = c4string_new(l);

    memcpy(result, s, (size_t)(l + 1));

    return result;
}

int64_t
c4string_len(str_t *s)
{
    real_str_t *p = (real_str_t *)(s - sizeof(int64_t));
    return p->len;
}

void
c4string_free(str_t *s)
{
    free((real_str_t *)(s - sizeof(int64_t)));
}
