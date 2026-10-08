/* Providers for exact production helper bodies inserted by the Python driver.
 * This tests lookup decisions, not DriverKit matching or hardware probing. */
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
typedef unsigned int vm_offset_t;
typedef int DTEntry;
#define kSuccess 0
#define kError (-1)
struct node { const char *key, *value; int has_reg; vm_offset_t reg[4]; };
static struct node nodes[3];
static int count, lookups, properties, selected, panics, failures, cases;
static char trace[16];
static const char *primary_key, *primary_value;
static jmp_buf panic_target;
static int DTFindEntry(const char *key, const char *value, DTEntry *entry)
{
    int i;
    trace[lookups++] = (!strcmp(key, primary_key) &&
        !strcmp(value, primary_value)) ? '1' : '2';
    trace[lookups] = 0;
    for (i = 0; i < count; i++)
        if (!strcmp(key, nodes[i].key) && !strcmp(value, nodes[i].value)) {
            *entry = i;
            return kSuccess;
        }
    return kError;
}
static int DTGetProperty(DTEntry entry, const char *key, void **value, int *size)
{
    properties++;
    selected = entry;
    if (strcmp(key, "reg") || !nodes[entry].has_reg) return kError;
    *value = nodes[entry].reg;
    *size = sizeof(nodes[entry].reg);
    return kSuccess;
}
static void panic(const char *message)
{
    (void)message;
    panics++;
    longjmp(panic_target, 1);
}

/* PRODUCTION_HELPERS */

static void check(vm_offset_t (*helper)(void), const char *helper_name,
    const char *case_name, int want_panic, vm_offset_t want_value,
    const char *want_trace, int want_properties, int want_selected)
{
    volatile vm_offset_t value = 0xffffffffU;
    int ok;
    lookups = properties = panics = 0;
    selected = -1;
    trace[0] = 0;
    if (!setjmp(panic_target)) value = helper();
    ok = panics == want_panic && (want_panic || value == want_value) &&
        !strcmp(trace, want_trace) && properties == want_properties &&
        selected == want_selected;
    /* Zero is still an offset. The caller adds it to the I/O base. */
    if (!want_panic && want_value == 0 && value + 0x80000000U != 0x80000000U)
        ok = 0;
    cases++;
    failures += !ok;
    printf("%s %s %s panic=%d value=%08x lookup=%s reg=%d selected=%d\n",
        ok ? "PASS" : "FAIL", helper_name, case_name, panics,
        (unsigned int)value, trace, properties, selected);
}
static void suite(vm_offset_t (*helper)(void), const char *name,
    const char *key1, const char *value1, const char *key2, const char *value2,
    int cell)
{
    int i;
    primary_key = key1; primary_value = value1;
    count = 0;
    check(helper, name, "absent", 0, 0, "12", 0, -1);
    count = 3;
    for (i = 0; i < count; i++) {
        nodes[i].key = key1; nodes[i].value = value1; nodes[i].has_reg = 1;
        nodes[i].reg[0] = 0x10000 + i * 0x1000;
        nodes[i].reg[1] = 0x1000;
        nodes[i].reg[2] = 0x8800 + i * 0x100;
        nodes[i].reg[3] = 0x100;
    }
    nodes[2].key = key2; nodes[2].value = value2;
    check(helper, name, "first-primary", 0, nodes[0].reg[cell], "1", 1, 0);
    nodes[0].has_reg = 0;
    check(helper, name, "primary-reg-failure-no-retry", 1, 0, "1", 1, 0);
    nodes[0].has_reg = 1;
    nodes[0].reg[cell] = 0;
    check(helper, name, "valid-zero", 0, 0, "1", 1, 0);
    nodes[0].key = nodes[1].key = "unrelated";
    check(helper, name, "fallback", 0, nodes[2].reg[cell], "12", 1, 2);
    nodes[2].has_reg = 0;
    check(helper, name, "fallback-reg-failure", 1, 0, "12", 1, 2);
    nodes[2].key = "device_type"; nodes[2].value = "soundbus";
    check(helper, name, "unrecognized-node", 0, 0, "12", 0, -1);
}
int main(void)
{
    if (sizeof(vm_offset_t) != 4) return 2;
    suite(get_scsi_int_offset, "scsi", "name", "mesh", "compatible", "chrp,mesh0", 0);
    suite(get_scsi_int_dma_offset, "dma", "name", "mesh", "compatible", "chrp,mesh0", 2);
    suite(get_audio_offset, "audio", "device_type", "davbus", "device_type", "sound", 0);
    printf("PEXPERT_OPTIONAL cases=%d failures=%d cell_bytes=%d\n",
        cases, failures, (int)sizeof(vm_offset_t));
    return failures != 0;
}
