#include "n00b.h"

// John's stuff.
typedef void (*CB_TYPE)(const char *, unsigned int, void*);

typedef struct {
    CB_TYPE process_output;
    void *unused1;
    void *unused2;
    void *unused3;
} MD_HTML_CALLBACKS;

N_LIB_PRIVATE N_CDECL(void, nimu_process_markdown)(NU8* s_p0, unsigned int n_p1, void* p_p2);

MD_HTML_CALLBACKS x = {
  .process_output   = nimu_process_markdown,
  .unused1 = NULL,
  .unused2 = NULL,
  .unused3 = NULL
};

int
c_markdown_to_html(char *mdoc, size_t len, void *outobj, size_t flags) {
  return md_html(mdoc, len, x, outobj, flags & 0x1ffff, flags >> 28);
}
