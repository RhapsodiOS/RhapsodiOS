#include <stdio.h>
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerIdentity.h"
static unsigned int checks, failures;
#define CHECK(x) do { ++checks; if (!(x)) { ++failures; \
    fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); } } while (0)
static ScreamerBytes bytes(const char *s, unsigned int n)
{
    ScreamerBytes b;
    b.bytes = (const unsigned char *)s;
    b.length = n;
    return b;
}
static void classify_compatible_list(void)
{
    CHECK(ScreamerClassify(bytes(0,0), bytes("vendor\0screamer\0",16)) == kScreamerIdentityScreamer);
    CHECK(ScreamerClassify(bytes("screamer",8), bytes(0,0)) == kScreamerIdentityScreamer);
    CHECK(ScreamerClassify(bytes("screamer",9), bytes(0,0)) == kScreamerIdentityScreamer);
    CHECK(ScreamerClassify(bytes(0,0), bytes(0,0)) == kScreamerIdentityUnknown);
    CHECK(ScreamerClassify(bytes("burgundy",8), bytes(0,0)) == kScreamerIdentityOther);
}
static void reject_unterminated_list(void)
{
    CHECK(ScreamerClassify(bytes(0,0), bytes("vendor\0screamer",15)) == kScreamerIdentityConflict);
    CHECK(ScreamerClassify(bytes("screamer",8), bytes(0,1)) == kScreamerIdentityConflict);
    CHECK(ScreamerClassify(bytes("screamer\0garbage",16), bytes(0,0)) == kScreamerIdentityConflict);
}
static void reject_conflicting_codec(void)
{
    CHECK(ScreamerClassify(bytes("screamer",8), bytes("burgundy\0",9)) == kScreamerIdentityConflict);
    CHECK(ScreamerClassify(bytes(0,0), bytes("screamer\0snapper\0",17)) == kScreamerIdentityConflict);
    CHECK(ScreamerClassify(bytes("awacs",5), bytes("screamer\0",9)) == kScreamerIdentityConflict);
}
static void reject_prefix_match(void)
{
    CHECK(ScreamerClassify(bytes("screamer-extra",14), bytes(0,0)) == kScreamerIdentityUnknown);
    CHECK(ScreamerClassify(bytes(0,0), bytes("not-screamer\0",13)) == kScreamerIdentityUnknown);
}
int main(void)
{
    classify_compatible_list();
    reject_unterminated_list();
    reject_conflicting_codec();
    reject_prefix_match();
    printf("identity: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
