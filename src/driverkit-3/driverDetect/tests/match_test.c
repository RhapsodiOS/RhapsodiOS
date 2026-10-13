#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "match.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
	printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } \
	} while (0)

#define NE2K_PATH "../../../drivers-i386/network/drvNE2k/NE2K.drvproj/Default.table"
#define AHCI_PATH "../../../drivers-i386/ide/drvAHCI/AHCI.drvproj/Default.table"
#define VGA_PATH "../../../drivers-i386/video/drvVGA/VGA.drvproj/Default.table"

static char *slurp(const char *path)
{
	FILE *f = fopen(path, "rb");
	char *buf;
	size_t n;

	if (f == NULL) {
		printf("FAIL cannot open %s\n", path);
		failures++;
		return NULL;
	}
	buf = malloc(65536);
	n = fread(buf, 1, 65535, f);
	buf[n] = '\0';
	fclose(f);
	return buf;
}

static void test_ids_forms(void)
{
	/* plain */
	CHECK(ids_match("0x802910ec", 0x802910ecUL, 0));
	CHECK(!ids_match("0x802910ec", 0x802810ecUL, 0));
	CHECK(ids_match("0x1111 0x802910ec", 0x802910ecUL, 0));
	CHECK(ids_match("0x1111\t0x802910ec", 0x802910ecUL, 0));
	/* mask */
	CHECK(ids_match("0x00001234&0xffff", 0x56781234UL, 0));
	CHECK(!ids_match("0x00001234&0xffff", 0x56781235UL, 0));
	/* secondary */
	CHECK(ids_match("0x802910ec:0x11223344", 0x802910ecUL, 0x11223344UL));
	CHECK(!ids_match("0x802910ec:0x11223344", 0x802910ecUL, 0x11223345UL));
	CHECK(ids_match("0x802910ec:0x1100&0xff00", 0x802910ecUL, 0x00001199UL));
	CHECK(!ids_match("0x802910ec:0x1100&0xff00", 0x802910ecUL, 0x00002299UL));
	CHECK(ids_match("0x1234&0xffff:0x5&0xf", 0x99991234UL, 0xabcd0005UL));
	/* no secondary part: any sid matches */
	CHECK(ids_match("0x802910ec", 0x802910ecUL, 0xdeadbeefUL));
	/*
	 * Leading colon: testIDs zeroes the primary test and mask at every
	 * space or tab, so a token starting with ':' has a wildcard primary
	 * (it does not reuse the previous one); only the secondary is tested.
	 */
	CHECK(ids_match("0x802910ec:0x1 :0x2", 0x802910ecUL, 0x2));
	CHECK(!ids_match("0x802910ec:0x1 :0x2", 0x802910ecUL, 0x3));
	CHECK(ids_match("0x802910ec:0x1 :0x2", 0x802810ecUL, 0x2));
	CHECK(ids_match(":0x2", 0x802910ecUL, 0x2));
	CHECK(!ids_match(":0x2", 0x802910ecUL, 0x3));
	/* vendor 0 and 0xffff never match, even with a zero mask */
	CHECK(!ids_match("0xffffffff", 0xffffffffUL, 0));
	CHECK(!ids_match("0x0&0x0", 0x1234ffffUL, 0));
	CHECK(!ids_match("0x0&0x0", 0x12340000UL, 0));
	/* empty and garbage strings match nothing and terminate */
	CHECK(!ids_match("", 0x802910ecUL, 0));
	CHECK(!ids_match("zzz", 0x802910ecUL, 0));
}

static void test_table_value(void)
{
	char v[16];
	static const char t[] =
	    "/* \"Family\" = \"Fake\"; */\n"
	    "\"Boot Driver\";\n"
	    "\"Family\"   =   \"Disk\"  ;\r\n"
	    "\"Long\" = \"0123456789abcdef0123\";\n";

	CHECK(table_value(t, "Family", v, sizeof v) == 4 && strcmp(v, "Disk") == 0);
	CHECK(table_value(t, "Fam", v, sizeof v) == -1);
	CHECK(table_value(t, "Boot Driver", v, sizeof v) == -1);
	CHECK(table_value(t, "Missing", v, sizeof v) == -1);
	CHECK(table_value(t, "Long", v, sizeof v) == -1);	/* does not fit */
	CHECK(table_value("\"E\" = \"\";", "E", v, sizeof v) == 0 && v[0] == '\0');
}

static void test_real_tables(void)
{
	char *ne2k = slurp(NE2K_PATH), *ahci = slurp(AHCI_PATH);
	char ids[512], fam[32];

	if (ne2k == NULL || ahci == NULL)
		return;
	CHECK(table_value(ne2k, "Bus Type", ids, sizeof ids) == 3 &&
	    strcmp(ids, "PCI") == 0);
	CHECK(table_value(ne2k, "Family", fam, sizeof fam) > 0 &&
	    strcmp(fam, "Network") == 0);
	CHECK(table_value(ne2k, "Auto Detect IDs", ids, sizeof ids) > 0);
	CHECK(ids_match(ids, 0x802910ecUL, 0));
	CHECK(!ids_match(ids, 0x29228086UL, 0));
	CHECK(table_value(ahci, "Auto Detect IDs", ids, sizeof ids) > 0);
	CHECK(ids_match(ids, 0x29228086UL, 0));
	CHECK(!ids_match(ids, 0x802910ecUL, 0));
	{
		const char *tables[2], *names[2];
		struct pcidev devs[2];
		struct match m[4];

		tables[0] = ne2k;
		tables[1] = ahci;
		names[0] = "NE2K";
		names[1] = "AHCI";
		memset(devs, 0, sizeof devs);
		devs[0].dev = 3;
		devs[0].pid = 0x802910ecUL;
		devs[1].dev = 4;
		devs[1].pid = 0x29228086UL;
		CHECK(match_all(tables, names, 2, devs, 2, m, 4) == 2);
		CHECK(strcmp(m[0].driver, "NE2K") == 0 &&
		    strcmp(m[0].family, "Network") == 0 && m[0].d.dev == 3 &&
		    m[0].instance == 0);
		CHECK(strcmp(m[1].driver, "AHCI") == 0 &&
		    strcmp(m[1].family, "Disk") == 0 && m[1].d.dev == 4);
		/* max bounds the output */
		CHECK(match_all(tables, names, 2, devs, 2, m, 1) == 1);
	}
	free(ne2k);
	free(ahci);
}

static void test_two_cards_one_driver(void)
{
	char *ne2k = slurp(NE2K_PATH);
	const char *tables[1], *names[1];
	struct pcidev devs[3];
	struct match m[4];

	if (ne2k == NULL)
		return;
	tables[0] = ne2k;
	names[0] = "NE2K";
	memset(devs, 0, sizeof devs);
	devs[0].dev = 3;
	devs[0].pid = 0x802910ecUL;
	devs[1].dev = 5;
	devs[1].pid = 0x29228086UL;	/* not ours */
	devs[2].dev = 6;
	devs[2].bus = 1;
	devs[2].pid = 0x802910ecUL;
	CHECK(match_all(tables, names, 1, devs, 3, m, 4) == 2);
	CHECK(m[0].instance == 0 && m[0].d.dev == 3);
	CHECK(m[1].instance == 1 && m[1].d.dev == 6 && m[1].d.bus == 1);
	free(ne2k);
}

static void test_driver_without_ids_never_matches(void)
{
	char *vga = slurp(VGA_PATH);
	const char *tables[2], *names[2];
	static const char notpci[] =
	    "\"Bus Type\" = \"EISA\";\n\"Auto Detect IDs\" = \"0x802910ec\";\n";
	struct pcidev d;
	struct match m[2];

	if (vga == NULL)
		return;
	tables[0] = vga;
	tables[1] = notpci;
	names[0] = "VGA";
	names[1] = "NOTPCI";
	memset(&d, 0, sizeof d);
	d.pid = 0x802910ecUL;
	CHECK(match_all(tables, names, 2, &d, 1, m, 2) == 0);
	free(vga);
}

static void test_write_location(void)
{
	struct pcidev d;
	char *r = NULL;
	static const char with[] =
	    "\"A\" = \"1\";\n\"Location\" = \"\";\n\"B\" = \"2\";\n";
	static const char without[] = "\"A\" = \"1\";\n";
	static const char old[] = "\"Location\" = \"Dev:9 Func:9 Bus:9\";\n";

	memset(&d, 0, sizeof d);
	d.dev = 3;
	CHECK(write_location(with, &d, &r) == 0 && strcmp(r,
	    "\"A\" = \"1\";\n\"Location\" = \"Dev:3 Func:0 Bus:0\";\n"
	    "\"B\" = \"2\";\n") == 0);
	free(r);
	CHECK(write_location(without, &d, &r) == 0 && strcmp(r,
	    "\"A\" = \"1\";\n\"Location\" = \"Dev:3 Func:0 Bus:0\";\n") == 0);
	free(r);
	d.dev = 12;
	d.func = 1;
	d.bus = 2;
	CHECK(write_location(old, &d, &r) == 0 && strcmp(r,
	    "\"Location\" = \"Dev:12 Func:1 Bus:2\";\n") == 0);
	free(r);
}

static void test_table_set(void)
{
	static const char t[] =
	    "/* \"Boot Drivers\" = \"x\"; */\n"
	    "\"Boot Drivers\" = \"EISABus PCIBus EIDE NE2K\";\n"
	    "\"Active Drivers\" = \"VGA BPF\";\n";
	char *r = NULL;

	/* Only the key changes, not the comment that names it. */
	CHECK(table_set(t, "Boot Drivers", "EISABus PCIBus EIDE", &r) == 0 &&
	    strcmp(r, "/* \"Boot Drivers\" = \"x\"; */\n"
	    "\"Boot Drivers\" = \"EISABus PCIBus EIDE\";\n"
	    "\"Active Drivers\" = \"VGA BPF\";\n") == 0);
	free(r);
	CHECK(table_set(t, "Kernel", "mach_kernel", &r) == 0 &&
	    strcmp(r + strlen(t), "\"Kernel\" = \"mach_kernel\";\n") == 0);
	free(r);
}

int main(void)
{
	test_ids_forms();
	test_table_value();
	test_real_tables();
	test_two_cards_one_driver();
	test_driver_without_ids_never_matches();
	test_write_location();
	test_table_set();
	printf("match: %d failures\n", failures);
	return failures != 0;
}
