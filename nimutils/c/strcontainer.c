#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

// Flags in a bitfield.
#define BOLD_ON         0x0001
#define INV_ON          0x0002
#define ST_ON           0x0004
#define ITALIC_ON       0x0008
#define UL_ON           0x0010
#define FG_COLOR_ON     0x0020
#define BG_COLOR_ON     0x0040
#define UL_DOUBLE       0x0080
#define UPPER_CASE      0x0100
#define TITLE_CASE      0x0200
#define LOWER_CASE      0x0300

typedef struct {
    uint64_t  offset;
    uint64_t  info;  // 16 bits of flags, 24 bits bg color, 24 bits fg color
} style_entry_t;

typedef struct {
    uint64_t      num_entries;
    style_entry_t styles[];
} style_info_t;

typedef struct {
    int64_t       len;
    style_info_t *styling;
    char          data[];
} real_str_t;

const int header_size = sizeof(int64_t) + sizeof(style_info_t *);

typedef char str_t;

str_t *
c4string_new(int64_t len)
{
    real_str_t *real_obj = calloc(len + header_size + 1, 1);

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

str_t *
c4str_from_file(char *name, int *err)
{
    int fd = open(name, O_RDONLY|O_EXLOCK);
    if (fd == -1) {
	*err = errno;
	return NULL;
    }

    off_t len = lseek(fd, 0, SEEK_END);

    if (len == -1) {
    err:
	*err = errno;
	close(fd);
	return NULL;
    }
    if (lseek(fd, 0, SEEK_SET) == -1) {
	goto err;
    }

    str_t *result = c4string_new(len);
    char *p       = result;

    while (1) {
	ssize_t num_read = read(fd, p, len);

	if (num_read == -1) {
	    if (errno == EINTR || errno == EAGAIN) {
		continue;
	    }
	    goto err;
	}

	if (num_read == len) {
	    return result;
	}

	p   += num_read;
	len -= num_read;
    }
}

int64_t
c4string_len(str_t *s)
{
    real_str_t *p = (real_str_t *)(s - header_size);
    return p->len;
}

void
c4string_free(str_t *s)
{
    free((real_str_t *)(s - header_size));
}

// This is really to make sure we can malloc()
// everything in advance before any rendering.
// It can overestimate on colors.
int
max_code_len(style_entry_t *style) {
    /*
     * We always add for the semicolon separator;
     * for the last item, that add goes toward the
     * m at the end.
     */
    int res       = 2;  // leading \e[
    uint64_t info = style->info;

    if (!info) {
	return 4; // A reset: \e[0m
    }

    if (info & UL_DOUBLE) {
	res += 3;
    }
    else {
	if (info & UL_ON) {
	    res += 2;
	}
    }
    if (info & BOLD_ON) {
	res += 2;
    }
    if (info & INV_ON) {
	res += 2;
    }
    if (info & ST_ON) {
	res += 2;
    }
    if (info & ITALIC_ON) {
	res += 2;
    }
    if (info & FG_COLOR_ON) {
	// longest is, e.g., 38;2;255;255;255
	res += 16;
    }
    if (info & BG_COLOR_ON) {
	res += 16;
    }

    return res;
}

int
get_ansi_render_buf_size(str_t *s, _Bool is_u32) {
    real_str_t *p = (real_str_t *)(s - header_size);
    int res = p->len + 1; // +1 for a trailing null.

    if (p->styling != NULL) {
	for (int i = 0; i < p->styling->num_entries; i++) {
	    res += max_code_len(&(p->styling->styles[i]));
	}
    }

    if(is_u32) {
	return res << 2; // 4 bytes per char.
    }
    else {
	return res;
    }
}

void
ansi_render_u8(str_t *s, char *buf) {
    real_str_t *real = (real_str_t *)(s - header_size);

    if (real->styling == NULL) {
	memcpy(buf, s, real->len + 1);
	return;
    }
}

void
ansi_render_u32(str_t *s, uint32_t *p) {
    real_str_t *real = (real_str_t *)(s - header_size);

    if (real->styling == NULL) {
	memcpy(p, s, real->len << 2);
	p[real->len] = 0;
	return;
    }
}

void
ansi_render(str_t *s, _Bool is_u32, char *p) {
    if (is_u32) {
	ansi_render_u32(s, (uint32_t *)p);
    }
    else {
	ansi_render_u8(s, p);
    }
}
