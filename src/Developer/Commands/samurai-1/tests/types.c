/* Guard the port's string allocation, formatting and 64-bit arithmetic. */
#include "compat.h"
#include <assert.h>
#include <string.h>
#include "htab.h"
#include "util.h"

const char *argv0 = "port-types";

int
main(void)
{
	static const size_t lengths[] = {0, 1, 3, 4, 8, 16, 17, 48, 49, 128};
	/* Values from the pinned upstream implementation, including its 128-bit path. */
	static const char *hashes[] = {
		"5a6ef77074ebc84b", "48dfce108249b3f8", "4a25c2969d7e2f6a",
		"b4ee98f29eebfc4f", "ec1570c82e51623e", "df7f47a6f1034c55",
		"6e168b32dd992016", "de39ec8d0e6155a0", "5935302eea87371f",
		"adbec08e962d43a1"
	};
	char input[128], number[21], large[4097], *formatted, *end;
	struct string *str;
	size_t i;
	int64_t value;

	assert(sizeof(uint32_t) == 4);
	assert(sizeof(uint64_t) == 8);
	for (i = 0; i < sizeof(input); ++i)
		input[i] = (char)i;
	for (i = 0; i < countof(lengths); ++i)
		assert(strcmp(u64hex(number, rapidhashv1(input, lengths[i])), hashes[i]) == 0);
	value = strtoll("-9223372036854775808", &end, 10);
	assert(*end == '\0');
	assert(strcmp(i64dec(number, value), "-9223372036854775808") == 0);
	assert(strcmp(u64hex(number, strtoull("ffffffffffffffff", &end, 16)), "ffffffffffffffff") == 0);
	assert(*end == '\0');
	memset(large, 'x', sizeof(large) - 1);
	large[sizeof(large) - 1] = '\0';
	assert(xasprintf(&formatted, "%s:%s", "prefix", large) == 4103);
	assert(strlen(formatted) == 4103);
	assert(strcmp(formatted + 7, large) == 0);
	free(formatted);
	str = mkstr(0);
	str->s[0] = '\0';
	assert(str->n == 0 && strcmp(str->s, "") == 0);
	free(str);
	str = mkstr(sizeof(large) - 1);
	memcpy(str->s, large, sizeof(large));
	assert(str->n == 4096 && strcmp(str->s, large) == 0);
	free(str);
	puts("PASS: C89 strings, formatting and upstream 64-bit hash vectors");
	return 0;
}
