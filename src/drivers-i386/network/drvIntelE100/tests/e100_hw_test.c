/*
 * e100_hw_test.c - unit tests for E100Hw.c against a simulated device:
 * a microwire EEPROM of 6 or 8 address bits, one MDI PHY, and the SCB
 * command byte.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see ../LICENSE.
 */
#include <stdio.h>

#include "E100Regs.h"
#include "E100Hw.h"
#include "e100_test_ports.h"

#define IO 0xC000U

static int failures;

static void
check(int ok, const char *test, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s: %s\n", test, what);
        failures++;
    }
}

/* --- the simulated device ---------------------------------------------- */

static unsigned long delayTotal;
static int seq;                         /* orders writes across registers */

static int scbStuck;                    /* the command byte never clears  */
static unsigned char scbStatus;
static unsigned char cmdLog[8];
static int cmdCount, cmdSeq, genptrSeq;
static unsigned long genptr, portValue;

static unsigned short eeWords[256];
static int eeAddrBits, eePresent, eeOpcode;
static int eeCs, eeSk, eeDo, eePhase, eeBitsIn;
static unsigned int eeShift;
static unsigned short eeData;

static unsigned short phyRegs[32];
static int phyAddress, mdiHang;
static unsigned long mdiValue;

static void
resetSim(void)
{
    int i;

    delayTotal = 0;
    seq = 0;
    scbStuck = 0;
    scbStatus = 0;
    cmdCount = cmdSeq = genptrSeq = 0;
    genptr = portValue = 0;
    for (i = 0; i < 256; i++)
        eeWords[i] = (unsigned short)(0x1000 + i);
    eeAddrBits = 6;
    eePresent = 1;
    eeOpcode = -1;
    eeCs = eeSk = 0;
    eeDo = 1;
    eePhase = eeBitsIn = 0;
    eeShift = 0;
    for (i = 0; i < 32; i++)
        phyRegs[i] = 0;
    phyAddress = 1;
    mdiHang = 0;
    mdiValue = 0;
}

/* A 93C46/93C66-style part: acts on the rising edge of SK while CS is high. */
static void
eeWrite(unsigned short v)
{
    int cs = (v & E100_EE_CS) != 0;
    int sk = (v & E100_EE_SK) != 0;
    int di = (v & E100_EE_DI) != 0;

    if (!cs) {
        eeCs = eeSk = 0;
        eeDo = 1;
        return;
    }
    if (!eeCs) {
        eePhase = eeBitsIn = 0;
        eeShift = 0;
    }
    eeCs = 1;
    if (sk && !eeSk && eePresent) {
        switch (eePhase) {
        case 0:                         /* opcode */
            eeShift = (eeShift << 1) | (unsigned int)di;
            if (++eeBitsIn == 3) {
                eeOpcode = (int)eeShift;
                eePhase = 1;
                eeBitsIn = 0;
                eeShift = 0;
            }
            break;
        case 1:                         /* address */
            eeShift = (eeShift << 1) | (unsigned int)di;
            if (++eeBitsIn == eeAddrBits) {
                eeData = eeWords[eeShift];
                eeDo = 0;               /* the dummy zero */
                eePhase = 2;
                eeBitsIn = 0;
            }
            break;
        default:                        /* data, most significant first */
            eeDo = (eeData >> (15 - eeBitsIn)) & 1;
            eeBitsIn++;
            break;
        }
    }
    eeSk = sk;
}

unsigned char
e100TestInb(unsigned int port)
{
    if (port == IO + E100_SCB_CMD)
        return (unsigned char)(scbStuck ? E100_CUC_START : 0);
    if (port == IO + E100_SCB_STATUS)
        return scbStatus;
    return 0xFF;
}

unsigned short
e100TestInw(unsigned int port)
{
    if (port == IO + E100_EECTL)
        return (unsigned short)(eeDo ? E100_EE_DO : 0);
    return 0xFFFF;
}

unsigned long
e100TestInl(unsigned int port)
{
    if (port == IO + E100_MDICTL)
        return mdiValue;
    return 0xFFFFFFFFUL;
}

void
e100TestOutb(unsigned int port, unsigned char value)
{
    if (port == IO + E100_SCB_CMD) {
        if (cmdCount < 8)
            cmdLog[cmdCount++] = value;
        cmdSeq = ++seq;
    }
}

void
e100TestOutw(unsigned int port, unsigned short value)
{
    if (port == IO + E100_EECTL)
        eeWrite(value);
}

void
e100TestOutl(unsigned int port, unsigned long value)
{
    int phy, reg;

    if (port == IO + E100_SCB_GENPTR) {
        genptr = value;
        genptrSeq = ++seq;
    } else if (port == IO + E100_PORT) {
        portValue = value;
    } else if (port == IO + E100_MDICTL) {
        phy = (int)((value >> E100_MDI_PHY_SHIFT) & 0x1F);
        reg = (int)((value >> E100_MDI_REG_SHIFT) & 0x1F);
        if (mdiHang) {
            mdiValue = 0;
        } else if (phy != phyAddress) {
            mdiValue = E100_MDI_READY;  /* reads as 0, as QEMU's does */
        } else {
            if ((value & 0x0C000000UL) == E100_MDI_OP_WRITE)
                phyRegs[reg] = (unsigned short)(value & 0xFFFFUL);
            mdiValue = E100_MDI_READY | phyRegs[reg];
        }
    }
}

void
e100TestDelay(unsigned int microseconds)
{
    delayTotal += microseconds;
}

/* --- tests ----------------------------------------------------------- */

static void
test_scb_command(void)
{
    static const char t[] = "SCB command";

    resetSim();
    check(e100ScbCommandPtr(IO, E100_CUC_START, 0x00123450UL) == 1, t, "accepted");
    check(genptr == 0x00123450UL, t, "pointer written");
    check(cmdCount == 1 && cmdLog[0] == E100_CUC_START, t, "command written");
    check(genptrSeq != 0 && genptrSeq < cmdSeq, t, "pointer before command");

    resetSim();
    scbStuck = 1;
    check(e100ScbCommand(IO, E100_CUC_RESUME) == 0, t, "reports a busy SCB");
    check(cmdCount == 0, t, "writes nothing while busy");
    check(delayTotal >= 20000UL, t, "waits at least 20 ms first");
}

static void
test_cu_resume(void)
{
    static const char t[] = "CU resume";

    resetSim();
    check(e100CuResume(IO, 0) == 1, t, "plain resume accepted");
    check(cmdCount == 1 && cmdLog[0] == E100_CUC_RESUME, t, "one command");

    resetSim();
    check(e100CuResume(IO, 1) == 1, t, "erratum resume accepted");
    check(cmdCount == 2 && cmdLog[0] == E100_CUC_NOP
          && cmdLog[1] == E100_CUC_RESUME, t, "NOP, then resume");
}

static void
test_port_and_waits(void)
{
    static const char t[] = "PORT and waits";
    volatile unsigned short status;

    resetSim();
    e100PortCommand(IO, E100_PORT_SELECTIVE_RESET);
    check(portValue == E100_PORT_SELECTIVE_RESET, t, "PORT written");
    check(delayTotal >= 10UL, t, "settles at least 10 us");

    resetSim();
    status = E100_CB_C | E100_CB_OK;
    check(e100WaitCB(&status, 5) == 1, t, "completed CB");
    status = 0;
    check(e100WaitCB(&status, 5) == 0, t, "CB timeout");
    check(delayTotal == 10UL, t, "2 us per loop");

    resetSim();
    scbStatus = 0x40;
    check(e100WaitCuIdle(IO) == 0, t, "CU suspended is not idle");
    scbStatus = 0x10;
    check(e100WaitCuIdle(IO) == 1, t, "RU state does not matter");
}

static void
test_eeprom(int bits)
{
    static const char t[] = "EEPROM";
    int last = (1 << bits) - 1;

    resetSim();
    eeAddrBits = bits;
    check(e100EepromAddressBits(IO) == bits, t, "address width found");
    check(eeOpcode == E100_EE_OP_READ, t, "read opcode 110b");
    check(e100EepromRead(IO, bits, 5) == 0x1005, t, "word 5");
    check(e100EepromRead(IO, bits, last) == 0x1000 + last, t, "last word");
    check(!eeCs, t, "deselected afterwards");
}

static void
test_eeprom_absent(void)
{
    resetSim();
    eePresent = 0;
    check(e100EepromAddressBits(IO) == 0, "EEPROM absent", "reports 0");
}

static void
test_mdi(void)
{
    static const char t[] = "MDI";

    resetSim();
    phyRegs[MII_PHYID1] = INTEL_PHYID1;
    check(e100MdiRead(IO, 1, MII_PHYID1) == INTEL_PHYID1, t, "read");
    check(e100MdiRead(IO, 5, MII_PHYID1) == 0, t, "no PHY at 5");
    check(e100MdiWrite(IO, 1, MII_BMCR, 0x1200) == 1 && phyRegs[MII_BMCR] == 0x1200,
          t, "write");
    mdiHang = 1;
    check(e100MdiRead(IO, 1, MII_BMSR) == -1, t, "read timeout");
    check(e100MdiWrite(IO, 1, MII_BMCR, 0) == 0, t, "write timeout");
}

int
main(void)
{
    test_scb_command();
    test_cu_resume();
    test_port_and_waits();
    test_eeprom(6);
    test_eeprom(8);
    test_eeprom_absent();
    test_mdi();
    if (failures == 0)
        printf("e100_hw_test: all passed\n");
    return failures != 0;
}
