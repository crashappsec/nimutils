#ifndef HEX_H__
#define HEX_H__
extern int calculate_size_prefix(uint64_t len, uint64_t start);
extern void add_offset(char **optr, uint64_t start_offset, uint64_t offset_len,
		       uint64_t line, uint64_t cpl);
extern char * hexl(void *ptr, unsigned int len, unsigned int start_offset,
		   unsigned int width, char *prefix);
extern char *chex(void *ptr, unsigned int len, unsigned int start_offset,
		  unsigned int width);
extern void print_hex(void *ptr, unsigned int len, char *prefix);

#endif
