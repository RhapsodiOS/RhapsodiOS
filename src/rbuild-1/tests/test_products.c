#include "products.h"
#include "test.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>

#define ROOT "/tmp/rb-products"
#define OBJ "usr/local/lib/objs/"
static void reset(void) {
    CHECK_INT(system("rm -rf " ROOT " && mkdir -p " ROOT), 0);
}
static void word(unsigned char *p, unsigned long v) {
    int i;
    for (i=0; i<4; i++) p[3-i] = (unsigned char)(v >> (8*i));
}
static void thin(unsigned char *p, unsigned cpu) {
    memset(p, 0, 28);
    word(p, 0xfeedfaceUL); word(p+4, cpu); word(p+12, 1);
}
static void put(const char *rel, unsigned mask) {
    char path[1024], command[1200], *slash;
    unsigned char b[104];
    unsigned n = 28;
    FILE *f;
    sprintf(path, ROOT "/%s", rel);
    slash = strrchr(path, '/'); *slash = 0;
    sprintf(command, "mkdir -p %s", path);
    CHECK_INT(system(command), 0); *slash = '/';
    memset(b, 0, sizeof(b));
    if (mask == 3) {
        n = 104; word(b, 0xcafebabeUL); word(b+4, 2);
        word(b+8, 7); word(b+16, 48); word(b+20, 28);
        word(b+28, 18); word(b+36, 76); word(b+40, 28);
        thin(b+48, 7); thin(b+76, 18);
    } else if (mask) thin(b, mask == 1 ? 7 : 18);
    else { memcpy(b, "#!/bin/sh\necho hi\n", 18); n=18; }
    f = fopen(path, "wb"); CHECK(f != 0);
    if (f) { CHECK_INT(fwrite(b,1,n,f), n); CHECK_INT(fclose(f),0); }
}
TEST(test_installed_code) {
    reset(); put("bin/tool",3);
    CHECK_INT(products_validate(ROOT,3,0,0),0);
    CHECK_INT(products_validate(ROOT,1,0,1),0);
    CHECK_INT(products_validate(ROOT,1,0,0),1);
    put("bin/tool",1);
    CHECK_INT(products_validate(ROOT,3,0,0),1);
    CHECK_INT(products_validate(ROOT,2,0,0),1);
    CHECK_INT(products_validate(ROOT,1,0,0),0);
    put("bin/tool",0); chmod(ROOT "/bin/tool",0755);
    put("System/Headers/a.h",0);
    CHECK_INT(products_validate(ROOT,3,0,0),0);
    CHECK_INT(symlink("/no/such/place",ROOT "/escape"),0);
    CHECK_INT(symlink(ROOT,ROOT "/cycle"),0);
    CHECK_INT(symlink("/bin",ROOT "/outside"),0);
    CHECK_INT(products_validate(ROOT,3,0,0),0);
    CHECK_INT(products_validate(ROOT "/outside",3,0,0),1);
    CHECK_INT(products_validate("/no/such/product-root",3,0,0),1);
    CHECK_INT(products_validate(ROOT,0,0,0),1);
}
TEST(test_directory_buckets) {
    reset();
    put(OBJ "lib/i386/dynamic_obj/intel.o",1);
    put(OBJ "lib/ppc/dynamic_obj/power.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    CHECK_INT(products_validate(ROOT,1,1,1),0);
    CHECK_INT(products_validate(ROOT,1,1,0),0);
    CHECK_INT(products_validate(ROOT,3,0,0),1);
    put(OBJ "lib/profile/i386/dynamic_obj/a.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put(OBJ "lib/profile/ppc/dynamic_obj/b.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    put(OBJ "lib/profile/ppc/dynamic_obj/b.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    reset();
    put(OBJ "lib/dynamic_obj/i386/a.o",1);
    put(OBJ "lib/dynamic_obj/ppc/b.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    put(OBJ "lib/dynamic_obj/ppc/i386/ambiguous.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    reset();
    put(OBJ "i386/dynamic_obj/a.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put(OBJ "i386/dynamic_obj/a.o",3);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    put("elsewhere/i386/dynamic_obj/a.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put("elsewhere/i386/dynamic_obj/a.o",3);
    CHECK_INT(products_validate(ROOT,3,0,0),0);
    reset();
    put(OBJ "Libc/dynamic_obj/i386/gen.subproj/i386.subproj/setjmp.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put(OBJ "Libc/dynamic_obj/ppc/gen.subproj/ppc.subproj/setjmp.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    reset();
    put(OBJ "lib/dynamic_obj/gen.subproj/i386.subproj/a.o",1);
    put(OBJ "lib/dynamic_obj/gen.subproj/ppc.subproj/b.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    put(OBJ "lib/dynamic_obj/i386.subproj/ppc/mixed.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    reset();
    put(OBJ "lib/i386/dynamic_obj/intel.o",1);
    put(OBJ "lib/ppc/dynamic_obj/fat.o",3);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    CHECK_INT(products_validate(ROOT,2,1,0),0);
    put(OBJ "lib/ppc/dynamic_obj/fat.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
}
TEST(test_suffix_pairs) {
    reset();
    put(OBJ "lib/dynamic_obj/a.i386.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put(OBJ "lib/dynamic_obj/a.ppc.o",2);
    put(OBJ "lib/dynamic_obj/a.o",3);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    CHECK_INT(products_validate(ROOT,1,1,1),0);
    put(OBJ "lib/dynamic_obj/b.i386.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put(OBJ "lib/dynamic_obj/b.ppc.o",1);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    put(OBJ "lib/dynamic_obj/b.ppc.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    reset();
    put(OBJ "lib/i386/dynamic_obj/a.i386.o",1);
    put(OBJ "lib/ppc/dynamic_obj/different.ppc.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),0);
    put(OBJ "lib/ppc/dynamic_obj/wrong.i386.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
    reset();
    put(OBJ "lib/variant1/dynamic_obj/a.i386.o",1);
    put(OBJ "lib/variant2/dynamic_obj/a.ppc.o",2);
    CHECK_INT(products_validate(ROOT,3,1,0),1);
}
TEST(test_per_arch_install_dirs) {
    /* A driver package installs thin binaries under private/Drivers/<arch>/,
     * so a universal build is satisfied by the pair, not by fat files. */
    reset();
    put("private/Drivers/i386/BPF.config/BPF_reloc",1);
    put("private/Drivers/i386/BPF.config/PostLoad",1);
    put("private/Drivers/ppc/BPF.config/BPF_reloc",2);
    put("private/Drivers/ppc/BPF.config/PostLoad",2);
    CHECK_INT(products_validate(ROOT,3,0,0),0);
    CHECK_INT(products_validate(ROOT,1,0,0),0);
    CHECK_INT(products_validate(ROOT,2,0,0),0);
    /* A fat binary in an arch directory still carries that arch. */
    put("private/Drivers/i386/BPF.config/PostLoad",3);
    CHECK_INT(products_validate(ROOT,3,0,0),0);
    /* The wrong CPU under an arch directory is still caught. */
    put("private/Drivers/i386/BPF.config/PostLoad",2);
    CHECK_INT(products_validate(ROOT,3,0,0),1);
    CHECK_INT(products_validate(ROOT,2,0,0),1);
    /* Only the component directly below private/Drivers names the CPU. */
    reset();
    put("private/Drivers/BPF.config/tool",1);
    CHECK_INT(products_validate(ROOT,3,0,0),1);
    /* Code outside any arch directory must still cover what was asked. */
    reset();
    put("usr/bin/rcz",1);
    CHECK_INT(products_validate(ROOT,3,0,0),1);
    CHECK_INT(products_validate(ROOT,1,0,0),0);
}
static void run_all(void) {
    RUN(test_installed_code);
    RUN(test_directory_buckets);
    RUN(test_suffix_pairs);
    RUN(test_per_arch_install_dirs);
    system("rm -rf " ROOT);
}
TEST_MAIN()
