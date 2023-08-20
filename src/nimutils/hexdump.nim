# Wrapping a C implementation I've done in the past.  Oddly, the main
# C function (now called chex) was always declared uint64_t, but the
# only way I could make Nim happy was if I changed them to `unsigned
# int`, which is okay on all the machines I care about anyway.
#
# :Author: John Viega (john@viega.org)

{.emit: """
#include <stdint.h>
#include <stdlib.h>
#include <sys/ioctl.h>

const uint8_t hex_map[16] = { '0', '1', '2', '3', '4', '5', '6', '7',
                              '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };

#define MIN_DUMP_WIDTH 36

int
calculate_size_prefix(uint64_t len, uint64_t start) {
    // We're going to keep the size prefix even; every 8 bits of max size
    // results in 2 characters printing.

    int log2 = 63 - __builtin_clzll(start + len);
    int ret  = (log2 / 8) * 2;

    if (log2 % 8) {
	ret += 2;
    }
    if (ret == 0) {
	ret = 2;
    }
    return ret;
}

char *
add_offset(char *inptr, uint64_t start_offset, uint64_t offset_len,
	   uint64_t line, uint64_t cpl) {
    /*
    ** To not have to worry much about padding, we're going to add
    ** offset_len zeros and the two spaces. Then, we'll set hex
    ** offset digits from the *right* until the whole offset is written.
    */
    uint8_t  chr;
    uint64_t value = start_offset + (uint64_t)(line * cpl);
    int ix         = offset_len;

    for (int i = 0; i < offset_len; i++) {
	inptr[i] = '0';
    }
    inptr[offset_len]     = ' ';
    inptr[offset_len + 1] = ' ';

    while (value) {
	chr         = (uint8_t)value & 0x0f;
	value       = value >> 4;
	inptr[--ix] = hex_map[chr];
    }

    // Return the output write position, which is after the second space.
    return inptr + offset_len + 2;
}


// This macro will be used below to output a single byte in hex.
#define HEXCHAR() *outptr++ = hex_map[*inptr >> 4];   \
                  *outptr++ = hex_map[*inptr & 0x0f]; \
   	          *outptr++ = ' ';                    \
 	          *inptr++;

#define ASCIICHAR() if (*lineptr < 32 || *lineptr > 126) { \
                        *outptr++ = '.';                   \
           	    }                                      \
                    else {                                 \
 		        *outptr++ = *lineptr;              \
 	            }                                      \
 	            *lineptr++;

char *
chex(void *ptr, unsigned int len, unsigned int start_offset,
     unsigned int width) {
    struct winsize ws;
    uint64_t       offset_len  = calculate_size_prefix(len, start_offset);
    uint64_t       chars_per_line;
    uint64_t       num_lines;
    uint64_t       alloc_len;
    uint64_t       remainder;
    char          *inptr   = (char *)ptr;
    char          *lineptr = inptr;
    char          *outptr;
    char 	  *ret;

    if (width == 0) {
      ioctl(0, TIOCGWINSZ, &ws);
      if (ws.ws_col > MIN_DUMP_WIDTH) {
	width = ws.ws_col;
      } else {
        width = MIN_DUMP_WIDTH;
      }
    }
    else {
      if (width < MIN_DUMP_WIDTH) {
        width = MIN_DUMP_WIDTH;
      }
    }

    /*
    ** Calculate how many characters we have room to print per line.
    **
    ** Every byte will have its two nibbles printed together, and will
    ** be separated by a space. But, Every FOURTH byte, we add an
    ** extra space. And each byte will have an ascii representation off on
    ** the end. So each byte requires 4.25 spaces.
    **
    ** But we'll only print out groups of 4 bytes, so each group of 4
    ** requires 17 columns.
    **
    ** Additionally, we have the overhead of an extra two spaces
    ** between the offset and the first byte, and we should leave at
    ** least a 1 char margin on the right, so from the width we remove
    ** the `offset_len` we calculated, along w/ 3 more overhead
    ** cols. This will never possibly be more than 19 columns (offset
    ** length of a 64-bit address would be 16 bytes).
    **
    ** This explains the below equation, but also why the minimum
    ** width is 36; the size we need for one group of 4 chars.
    */

    chars_per_line = ((width - offset_len - 3) / 17) * 4;

    /*
    ** To figure out how many lines we need, we add chars_per_line - 1
    ** to the len, then divide by chars_per_line; this makes sure to
    ** count any short line, but does not overcount if we already are
    ** at an exact multiple.
     */
    num_lines = (len + chars_per_line - 1) / chars_per_line;

    /*
     * We need to keep track of how many leftover characters
     * we have to print on the final line.
     */
    remainder = len % chars_per_line;

    /*
    ** When allocing the result, we need to add another character per
    ** line for the ending newline. Plus, we need to add one more byte
    ** for the null terminator.
    */

    alloc_len = (chars_per_line + 1) * num_lines + 1;
    ret       = (char *)calloc(alloc_len, 1);
    outptr    = ret;

    /*
     * Now that we've done our allocation, let's have num_lines
     * represent the number of FULL lines by subtracting one if
     * the remainder is non-zero.
     */
    if (remainder != 0) {
	num_lines -= 1;
    }

    for (int i = 0; i < num_lines; i++) {
	// Hold onto the beginning of the line so we can go
	// back through at the end for the ASCII bits.
	outptr = add_offset(outptr, start_offset, offset_len, i,
			    chars_per_line);

	// The inner loop is for quads.
	for (int j = 0; j < chars_per_line / 4; j++) {
	    HEXCHAR();
	    HEXCHAR();
	    HEXCHAR();
	    HEXCHAR();
	    *outptr++ = ' ';
	}
	// Now for any ASCII-printable stuff, we emit it, or a '.' if not.
	// lineptr is pointing at the first char we need to show.
	for (int j = 0; j < chars_per_line; j++) {
	    ASCIICHAR();
	}

	*outptr++ = '\n';
    }

    if (remainder != 0) {
	// First, print the offset.
	outptr = add_offset(outptr, start_offset, offset_len, num_lines,
			    chars_per_line);

	// Next, we need to know the position where the ASCII
	// representation starts. We've skipped the offset plus pad,
	// but we need to calculate 13 bytes for each group of 4,
	// if this were a full line.
	char *stopptr = outptr + (chars_per_line/4)*13;

	// Now, print any full groups of 4.
	for (int i = 0; i < remainder / 4; i++) {
	    HEXCHAR();
	    HEXCHAR();
	    HEXCHAR();
	    HEXCHAR();
	    *outptr++ = ' ';
	}
	// Now, print any leftover chars.
	for (int i = 0; i < remainder % 4; i++) {
	    HEXCHAR();
	}

	// Pad with spaces until we get to where the ASCII bits start.
	while (outptr < stopptr) {
	    *outptr++ = ' ';
	}
	for (int i = 0; i < remainder; i++) {
	    ASCIICHAR();
	}
	// Now, pad the rest of the line w/ spaces;
	for (int i = remainder; i < chars_per_line; i++) {
	    *outptr++ = ' ';
	}
	*outptr = '\n';
    }

    return ret;
}

"""}

proc rawHexDump(x: pointer, sz: cuint, offset: cuint, width: cuint):
               cstring {.importc: "chex".}

proc hexDump*(x: pointer, sz: uint, offset: uint = 0, width = 0): string =
  # Hex dump memory from the
  return $(rawHexDump(x, cuint(sz), cuint(offset), cuint(width)))


when isMainModule:
  var
    buf: array[128, byte] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
    39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56,
    57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92,
    93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108,
    109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
    123, 124, 125, 126, 127 ]

  echo hexDump(addr buf[0], 128, width = 40)
