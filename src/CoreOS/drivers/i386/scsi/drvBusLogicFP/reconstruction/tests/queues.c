#include <assert.h>
#include <string.h>
#include "io_mock.h"

u32 page_mask = 0x00000fffu;

#if !defined(__i386__)
#include <stdio.h>
#endif

void blfp_test_assert_failed(int line)
{
#if !defined(__i386__)
    fprintf(stderr, "queue test assertion failed at line %d\n", line);
#else
    (void)line;
#endif
    abort();
}

static unsigned callback_count;
static struct sccb *callback_last;

static int complete_sccb(struct sccb *sccb)
{
    ++callback_count;
    callback_last = sccb;
    return 0x12345678;
}

static void clear_manager(void)
{
    memset(BL_Card, 0, sizeof(BL_Card));
    memset(sccbMgrTbl, 0, sizeof(sccbMgrTbl));
    memset(scamInfo, 0, sizeof(scamInfo));
    callback_count = 0;
    callback_last = 0;
    blfp_io_reset();
}

static void queue_order_and_removal(void)
{
    struct sccb a, b, c;
    struct sccb_card *card = &BL_Card[0];
    struct sccb_mgr_target *target = &sccbMgrTbl[0][3];
    memset(&a, 0, sizeof(a)); memset(&b, 0, sizeof(b)); memset(&c, 0, sizeof(c));
    a.TargID = b.TargID = c.TargID = 3;

    assert(queueFindSccb(&a, 0) == 0);
    queueAddSccb(&a, 0); queueAddSccb(&b, 0); queueAddSccb(&c, 0);
    assert(target->selectHead == &a && target->selectTail == &c);
    assert(target->selectCount == 3);
    assert(a.Sccb_forwardlink == &b && b.Sccb_backlink == &a);
    assert(b.Sccb_forwardlink == &c && c.Sccb_backlink == &b);
    assert(queueFindSccb(&b, 0) == 1);
    assert(a.Sccb_forwardlink == &c && c.Sccb_backlink == &a);
    assert(target->selectCount == 2);
    assert(queueFindSccb(&a, 0) == 1);
    assert(target->selectHead == &c && target->selectTail == &c);
    assert(queueFindSccb(&c, 0) == 1);
    assert(target->selectHead == 0 && target->selectTail == 0);
    assert(target->selectCount == 0);

    queueAddSccb(&a, 0); queueAddSccb(&b, 0);
    card->tagQ_Lst = 3;
    assert(queueSearchSelect(card, 0) == (int)(unsigned long long)&b);
    assert(card->currentSCCB == &a);
    assert(target->selectHead == &b && b.Sccb_backlink == 0);
    assert(target->selectCount == 1 && card->tagQ_Lst == 4);
    assert((card->globalFlags & 0x40) != 0);
    card->currentSCCB = &a;
    assert(queueSelectFail(&card->currentSCCB, 0) == (u8)(unsigned long long)&a);
    assert(card->currentSCCB == 0 && target->selectHead == &a);
    assert(a.Sccb_forwardlink == &b && b.Sccb_backlink == &a);
    assert(target->selectCount == 2);
}

static void disconnect_and_flush(void)
{
    struct sccb active, waiting;
    struct sccb_card *card = &BL_Card[1];
    struct sccb_mgr_target *target = &sccbMgrTbl[1][5];
    memset(&active, 0, sizeof(active)); memset(&waiting, 0, sizeof(waiting));
    active.TargID = waiting.TargID = 5;
    waiting.Lun = 2; waiting.Sccb_tag = 3; waiting.SccbCallback = complete_sccb;
    card->currentSCCB = &active;
    assert(queueDisconnect(&waiting, 1) == 5);
    assert(target->disconnected[3] == &waiting);
    assert(((u8 *)target)[34] == 1);
    assert(card->currentSCCB == 0);

    card->currentSCCB = &active;
    card->cmdCounter = 2;
    assert(queueFlushSccb(1, 17) == 31);
    assert(waiting.HostStatus == 17 && target->disconnected[3] == 0);
    assert(((u8 *)target)[34] == 0);
    assert(callback_count == 1 && callback_last == &waiting);
    assert(card->currentSCCB == 0 && card->cmdCounter == 1);
}

static void residual_updates(void)
{
    struct sccb s;
    memset(&s, 0, sizeof(s));
    s.DataLength = 1000; s.Sccb_ATC = 280;
    assert(utilUpdateResidual(&s) == 0 && s.DataLength == 720);
    s.DataLength = 1000; s.Sccb_XferState = 2;
    assert(utilUpdateResidual(&s) == 0 && s.DataLength == 0);
    s.Sccb_XferState = 4; s.DataLength = 17; s.Sccb_sgseg = 0;
    s.SGEntries[0].length = 8; s.SGEntries[1].length = 9;
    assert(utilUpdateResidual(&s) == 0 && s.DataLength == 17);
}

static void wait_trace(void)
{
    const u16 base = 0x100;
    const struct blfp_io_event reads[] = {
        {base + 108, 0xaa, 1, 0},
        {base + 64, 5, 1, 0},
        {base + 70, 0, 1, 0},
        {base + 66, 0, 1, 0},
        {base + 69, 0, 1, 0},
        {base + 66, 4, 1, 0},
        {base + 70, 1, 1, 0},
        {base + 64, 4, 1, 0}
    };
    const struct blfp_io_event expected[] = {
        {base + 108, 0xaa, 1, 0}, {base + 108, 7, 1, 1},
        {base + 66, 1, 1, 1}, {base + 64, 5, 1, 0},
        {base + 64, 4, 1, 1}, {base + 70, 0, 1, 0},
        {base + 70, 1, 1, 1}, {base + 66, 0, 1, 0},
        {base + 69, 0, 1, 0}, {base + 66, 4, 1, 0},
        {base + 70, 1, 1, 0}, {base + 70, 0, 1, 1},
        {base + 108, 0xaa, 1, 1}, {base + 66, 1, 1, 1},
        {base + 64, 4, 1, 0}, {base + 64, 5, 1, 1}
    };
    unsigned i;

    blfp_io_reset();
    blfp_io_script_events(reads, sizeof(reads) / sizeof(reads[0]));
    assert(Wait(base, 7) == 0);
    assert(blfp_io_trace_count == sizeof(expected) / sizeof(expected[0]));
    for (i = 0; i < blfp_io_trace_count; ++i) {
#if !defined(__i386__)
        if (blfp_io_trace[i].value != expected[i].value)
            fprintf(stderr, "trace[%u] got value=%x port=%x write=%u; expected value=%x port=%x write=%u\n",
                    i, (unsigned)blfp_io_trace[i].value, blfp_io_trace[i].port,
                    blfp_io_trace[i].write, (unsigned)expected[i].value,
                    expected[i].port, expected[i].write);
#endif
        assert(blfp_io_trace[i].port == expected[i].port);
        assert(blfp_io_trace[i].value == expected[i].value);
        assert(blfp_io_trace[i].width == expected[i].width);
        assert(blfp_io_trace[i].write == expected[i].write);
    }
}

static void port_widths_and_counters(void)
{
    const struct blfp_io_event reads[] = {
        {0x20, 0xa5, 1, 0}, {0x21, 0x1234, 2, 0},
        {0x23, 0x12345678, 4, 0}
    };
    u32 byteCount = xxx_8_0;
    u32 wordCount = xxx_11_0;
    u32 longCount = xxx_14_0;

    blfp_io_reset();
    blfp_io_script_events(reads, 3);
    assert(OS_InPortByte(0x20) == 0xa5);
    assert(OS_InPortWord(0x21) == 0x1234);
    assert(OS_InPortLong(0x23) == 0x12345678);
    assert(OS_OutPortByte(0x24, 0x5a) == 0);
    assert(OS_OutPortWord(0x26, 0x4567) == 0);
    assert(OS_OutPortLong(0x28, 0x89abcdef) == 0);
    assert(xxx_8_0 == byteCount + 1);
    assert(xxx_11_0 == wordCount + 1);
    assert(xxx_14_0 == longCount + 1);
    assert(blfp_io_trace_count == 6);
    assert(blfp_io_trace[0].width == 1 && !blfp_io_trace[0].write);
    assert(blfp_io_trace[1].width == 2 && !blfp_io_trace[1].write);
    assert(blfp_io_trace[2].width == 4 && !blfp_io_trace[2].write);
    assert(blfp_io_trace[3].width == 1 && blfp_io_trace[3].write);
    assert(blfp_io_trace[4].width == 2 && blfp_io_trace[4].write);
    assert(blfp_io_trace[5].width == 4 && blfp_io_trace[5].write);
}

static void page_boundaries(void)
{
    assert(doesCrossPage(0x1000, 260) == 0);
    assert(doesCrossPage(0x1efc, 260) == 0);
    assert(doesCrossPage(0x1efd, 260) == 1);
}

static void manager_initialization(void)
{
    struct sccb s;
    struct sccb_card *card = &BL_Card[2];
    struct sccb_mgr_target *target = &sccbMgrTbl[2][4];
    const struct blfp_io_event intRead[] = {{0x117, 0x20, 1, 0}};

    memset(BL_Card, 0x5a, sizeof(BL_Card));
    memset(sccbMgrTbl, 0x5a, sizeof(sccbMgrTbl));
    assert(SccbMgrTableInitAll() == 32);
    assert(card->currentSCCB == 0 && card->cardInfo == 0 && card->ioPort == 0);
    assert(card->discQCount == 0xff && card->ourId == 0);
    assert(card->tagQ_Lst == 0 && card->cmdCounter == 0 && card->globalFlags == 0);
    assert(target->selectHead == 0 && target->selectTail == 0);
    assert(target->selectCount == 0 && target->syncValue == 0);
    assert(target->disconnected[32] == 0);
    assert(((u8 *)target)[2] == 0 && ((u8 *)target)[3] == 0);

    memset(&s, 0, sizeof(s));
    s.OperationCode = SCATTER_GATHER_COMMAND;
    s.ControlByte = 0x20;
    s.DataLength = 0;
    s.TargID = 4; s.Lun = 3;
    target->status = 1;
    BL_CardFlags[40] = 0;
    assert(scsiInitSCCB(&s, 2) == 10);
    assert(s.Sccb_XferState == 6 && s.Sccb_XferCnt == 0);
    assert(s.Sccb_SGoffset == 0 && s.Sccb_idmsg == 0xc3);
    assert(s.ControlByte == 0x20 && (target->status & 4) != 0);
    assert(s.HostStatus == 0 && s.TargetStatus == 0 && s.Sccb_scsimsg == 8);

    card->ioPort = 0xe0;
    blfp_io_reset();
    blfp_io_script_events(intRead, 1);
    assert(SccbMgr_my_int(card) == 1);
    assert(blfp_io_trace_count == 1 && blfp_io_trace[0].port == 0x117);
}

static void eeprom_serial_paths(void)
{
    const struct blfp_io_event addr9Reads[] = {{0x229, 0x10, 1, 0}};
    const u8 commandWrites[] = {0x20, 0x28, 0x2a, 0x2e, 0x2a,
                                0x28, 0x2c, 0x28, 0x28, 0x2c, 0x28};
    const u8 addressBits[] = {0, 1, 0, 1, 0, 1, 0, 1, 0, 1};
    struct blfp_io_event readValues[18];
    u8 expectedWrites[41];
    unsigned reads = 0;
    unsigned writes = 0;
    unsigned i;
    unsigned outIndex = 0;

    blfp_io_reset();
    blfp_io_script_events(addr9Reads, 1);
    assert(utilEESendCmdAddr(0x200, 4, 0x155) == 0);
    assert(blfp_io_trace_count == 42);
    for (i = 0; i < blfp_io_trace_count; ++i) {
        if (blfp_io_trace[i].write)
            ++writes;
        else
            ++reads;
    }
    assert(reads == 1 && writes == 41);
    for (i = 0; i < sizeof(commandWrites); ++i)
        expectedWrites[outIndex++] = commandWrites[i];
    for (i = 0; i < sizeof(addressBits); ++i) {
        u8 low = addressBits[i] ? 0x2a : 0x28;
        expectedWrites[outIndex++] = low;
        expectedWrites[outIndex++] = (u8)(low | 4);
        expectedWrites[outIndex++] = low;
    }
    assert(outIndex == sizeof(expectedWrites));
    assert(!blfp_io_trace[0].write && blfp_io_trace[0].port == 0x229);
    for (i = 0; i < sizeof(expectedWrites); ++i) {
        assert(blfp_io_trace[i + 1].write);
        assert(blfp_io_trace[i + 1].port == 0x222);
        assert(blfp_io_trace[i + 1].value == expectedWrites[i]);
    }

    readValues[0] = (struct blfp_io_event){0x222, 0xc0, 1, 0};
    readValues[1] = (struct blfp_io_event){0x229, 0x10, 1, 0};
    for (i = 2; i < 18; ++i)
        readValues[i] = (struct blfp_io_event){0x222, 1, 1, 0};
    blfp_io_reset();
    blfp_io_script_events(readValues, 18);
    assert(utilEERead(0x200, 0x55) == 0xffff);
    reads = writes = 0;
    for (i = 0; i < blfp_io_trace_count; ++i) {
        if (blfp_io_trace[i].write)
            ++writes;
        else
            ++reads;
    }
    assert(reads == 18 && writes == 75);
}

static void scsi_setup_paths(void)
{
    struct sccb s;
    struct sccb *sccb = &s;
    struct sccb_mgr_target target;
    u8 i;

    memset(&s, 0, sizeof(s));
    memset(&target, 0, sizeof(target));
    s.CdbLength = 10;
    s.RequestSenseLength = 26;
    s.Sccb_XferState = 6;
    s.Sccb_idmsg = 0xc7;
    s.ControlByte = 0x5a;
    s.Sccb_MGRFlags = 0xabcd;
    for (i = 0; i < 12; ++i)
        s.Cdb[i] = i + 0x10;
    assert(scsiSenseSetup(&sccb) == 5);
    assert(s.Save_CdbLen == 10 && s.CdbLength == 6);
    for (i = 0; i <= 5; ++i)
        assert(s.Save_Cdb[i] == i + 0x10);
    assert(s.Cdb[0] == 3 && s.Cdb[1] == 0 && s.Cdb[2] == 0);
    assert(s.Cdb[3] == 0 && s.Cdb[4] == 26 && s.Cdb[5] == 0);
    assert(s.Sccb_XferCnt == 26 && s.Sccb_ATC == 0);
    assert(s.Sccb_XferState == 0x0a && s.Sccb_idmsg == 0x87);
    assert(s.ControlByte == 0 && s.Sccb_MGRFlags == 1);

    blfp_io_reset();
    assert(scsiSetSyncValue(0x300, 3, 0x19, &target) == 0);
    assert(target.syncValue == 0x19);
    assert(blfp_io_trace_count == 1 && blfp_io_trace[0].port == 0x363);
    assert(blfp_io_trace[0].value == 0x19 && blfp_io_trace[0].write);
}

static void fetch_message_paths(void)
{
    struct sccb s;
    const struct blfp_io_event ordinary[] = {
        {0x444, 0x20, 1, 0}, {0x474, 5, 1, 0}, {0x442, 0, 1, 0}
    };
    const struct blfp_io_event reject[] = {
        {0x444, 0x20, 1, 0}, {0x474, 9, 1, 0},
        {0x442, 0x20, 1, 0}, {0x44e, 1, 1, 0}, {0x444, 0, 1, 0}
    };
    memset(&s, 0, sizeof(s));

    blfp_io_reset();
    blfp_io_script_events(ordinary, 3);
    assert(scsiFetchMsg(0x400, &s) == 5);
    assert(blfp_io_trace_count == 5);
    assert(blfp_io_trace[0].port == 0x444 && !blfp_io_trace[0].write);
    assert(blfp_io_trace[1].port == 0x446 && blfp_io_trace[1].value == 0x80);
    assert(blfp_io_trace[2].port == 0x474 && !blfp_io_trace[2].write);
    assert(blfp_io_trace[3].port == 0x444 && blfp_io_trace[3].value == 0x12);
    assert(blfp_io_trace[4].port == 0x442 && !blfp_io_trace[4].write);

    blfp_io_reset();
    blfp_io_script_events(reject, 5);
    assert(scsiFetchMsg(0x400, &s) == 0);
    assert(s.Sccb_scsimsg == 9);
    assert(blfp_io_trace_count == 9);
    assert(blfp_io_trace[6].port == 0x442 && blfp_io_trace[6].value == 0x20);
    assert(blfp_io_trace[8].port == 0x444 && blfp_io_trace[8].value == 0x0a);
}

static void small_phase_and_scam_helpers(void)
{
    struct sccb s;
    struct sccb_card card;
    u32 consecutiveClear[16] = {0};
    const u32 waitValues[] = {0, 4};
    memset(&s, 0, sizeof(s));
    memset(&card, 0, sizeof(card));
    card.currentSCCB = &s;

    s.Sccb_XferState = 4;
    s.Sccb_sgseg = 3;
    s.Sccb_SGoffset = 99;
    blfp_io_reset();
    assert(dataXferProcessor(0x400, &card) == 0);
    assert(card.globalFlags == 0x20);
    card.globalFlags = 0x20;
    assert(dataXferProcessor(0x400, &card) == 0);
    assert(s.Sccb_sgseg == 19 && s.Sccb_SGoffset == 0);
    card.globalFlags = 0;
    s.Sccb_XferState = 0;
    assert(dataXferProcessor(0x400, &card) == 0);
    assert((card.globalFlags & 0x20) != 0);
    {
        union { struct sccb *pointer; u32 word; } expected;
        expected.pointer = &s;
        assert(dataXferProcessor(0x400, &card) == (int)expected.word);
    }

    blfp_io_reset();
    blfp_io_script(0x474, 1, consecutiveClear, 16);
    assert(ScamWireOrData(0x400, 1) == 0);
    assert(blfp_io_trace_count == 16);
    {
        u32 resetSamples[17] = {1};
        blfp_io_reset();
        blfp_io_script(0x474, 1, resetSamples, 17);
        assert(ScamWireOrData(0x400, 1) == 0);
        assert(blfp_io_trace_count == 17);
    }
    blfp_io_reset();
    blfp_io_script(0x444, 1, consecutiveClear, 16);
    assert(ScamWireOrSig(0x400, 1) == 0);
    assert(blfp_io_trace_count == 16);
    blfp_io_reset();
    blfp_io_script(0x442, 1, waitValues, 2);
    assert(ScamWaitSelection(0x400) == 4);
    assert(blfp_io_trace_count == 2);
    assert(ScamValidQ(0x00) == 1);
    assert(ScamValidQ(0x18) == 0);
    blfp_io_reset();
    assert(phaseStatus(0x400) == 0);
    assert(blfp_io_trace_count == 1);
    assert(blfp_io_trace[0].port == 0x464 && blfp_io_trace[0].value == 0x2a &&
           blfp_io_trace[0].write);
}

static void manager_probe_rejects_bad_signature(void)
{
    struct sccb_mgr_info info;
    const u32 wrongSignature[] = {0};
    memset(&info, 0, sizeof(info));
    info.ioBase = 0x400;
    blfp_io_reset();
    blfp_io_script(0x400, 1, wrongSignature, 1);
    assert(SccbMgr_sense_adapter(&info) == -1);
    assert(blfp_io_trace_count == 1);
    assert(blfp_io_trace[0].port == 0x400 && !blfp_io_trace[0].write);
}

static void manager_reset_without_bus_interrupt(void)
{
    struct sccb_mgr_info info;
    struct sccb_card card;
    const struct blfp_io_event reads[] = {
        {0x429, 0, 1, 0}, {0x46c, 0, 1, 0}, {0x442, 1, 1, 0},
        {0x46c, 0, 1, 0}, {0x440, 0, 1, 0}, {0x446, 0, 1, 0},
        {0x442, 1, 1, 0}, {0x446, 0, 1, 0}, {0x440, 0, 1, 0},
        {0x417, 0, 1, 0}, {0x429, 0, 1, 0}, {0x436, 0, 1, 0}
    };
    memset(&info, 0, sizeof(info));
    memset(&card, 0, sizeof(card));
    info.ioBase = 0x400;
    card.discQCount = 1;
    card.ioPort = 0x400;
    card.cardInfo = &info;
    blfp_io_reset();
    blfp_io_script_events(reads, sizeof(reads) / sizeof(reads[0]));
    assert(SccbMgr_scsi_reset(&card) == 0);
    assert(blfp_io_trace_count > 30);
    assert(blfp_io_trace[blfp_io_trace_count - 1].port == 0x436 &&
           !blfp_io_trace[blfp_io_trace_count - 1].write);
}

static void transfer_restart_paths(void)
{
    struct sccb s;
    memset(&s, 0, sizeof(s));
    s.DataLength = 100;
    s.Sccb_ATC = 30;
    hostDataXferRestart(&s);
    assert(s.Sccb_XferCnt == 70);

    s.Sccb_XferState = 4;
    s.Sccb_ATC = 12;
    s.SGEntries[0].length = 8;
    s.SGEntries[1].length = 16;
    hostDataXferRestart(&s);
    assert(s.Sccb_XferCnt == 0);
    assert(s.Sccb_sgseg == 1 && s.Sccb_SGoffset == 12);

    s.Sccb_ATC = 8;
    hostDataXferRestart(&s);
    assert(s.Sccb_sgseg == 1 && s.Sccb_SGoffset == 0);
}

static void phase_command_and_data_paths(void)
{
    struct sccb s;
    memset(&s, 0, sizeof(s));
    BL_Card[0].currentSCCB = &s;
    s.CdbLength = 6;
    for (u8 i = 0; i < 6; ++i)
        s.Cdb[i] = (u8)(0x10 + i);
    blfp_io_reset();
    phaseCommand(0x400, 0);
    assert(s.Sccb_scsistat == 6);
    assert(blfp_io_trace[0].port == 0x444 && blfp_io_trace[0].write);
    assert(blfp_io_trace[1].port == 0x429 && !blfp_io_trace[1].write);
    assert(blfp_io_trace[2].port == 0x429 && blfp_io_trace[2].write &&
           blfp_io_trace[2].value == 2);
    assert(blfp_io_trace[3].port == 0x488 && blfp_io_trace[3].value == 0x8410);
    assert(blfp_io_trace[9].port == 0x494 && blfp_io_trace[9].value == 0x2010);

    s.Sccb_XferCnt = 1;
    blfp_io_reset();
    phaseDataOut(0x400, 0);
    assert(s.Sccb_scsistat == 7);
    assert(blfp_io_trace[0].port == 0x446 && blfp_io_trace[0].value == 0x80);
    assert(blfp_io_trace[2].port == 0x464 && blfp_io_trace[2].value == 0xca);
    s.Sccb_XferCnt = 1;
    blfp_io_reset();
    phaseDataIn(0x400, 0);
    assert(s.Sccb_scsistat == 8 && (s.Sccb_XferState & 1) != 0);
    assert(blfp_io_trace[0].port == 0x446 && blfp_io_trace[0].value == 0x80);
}

static void default_map_programming(void)
{
    blfp_io_reset();
    autoLoadDefaultMap(0x400);
    assert(blfp_io_trace_count == 47);
    assert(blfp_io_trace[0].port == 0x429 && !blfp_io_trace[0].write);
    assert(blfp_io_trace[1].port == 0x429 && blfp_io_trace[1].value == 2);
    assert(blfp_io_trace[2].port == 0x480 && blfp_io_trace[2].value == 0x86c0);
    assert(blfp_io_trace[18].port == 0x4a0 && blfp_io_trace[18].value == 0x4812);
    assert(blfp_io_trace[46].port == 0x429 && blfp_io_trace[46].write);
}

static void transfer_pad_status_short_circuit(void)
{
    const u32 status[] = {1};
    blfp_io_reset();
    blfp_io_script(0x443, 1, status, 1);
    assert(scsiXferPad(0x400, 0) == 1);
    assert(blfp_io_trace_count == 3);
    assert(blfp_io_trace[0].port == 0x447 && blfp_io_trace[0].value == 2);
    assert(blfp_io_trace[1].port == 0x447 && blfp_io_trace[1].value == 0);
    assert(blfp_io_trace[2].port == 0x443 && !blfp_io_trace[2].write);
}

static void bus_master_transfer_registers(void)
{
    struct sccb s;
    union { u32 word; void *pointer; } data;
    memset(&s, 0, sizeof(s));
    data.word = 0x1000;
    s.DataPointer = data.pointer;
    s.SccbVirtDataPtr = 0x100;
    s.Sccb_XferCnt = 0x12345;
    s.Sccb_XferState = 1;
    blfp_io_reset();
    busMstrDataXferStart(0x400, &s);
    assert(blfp_io_trace_count == 8);
    assert(blfp_io_trace[0].port == 0x41c && blfp_io_trace[0].value == 0x1100);
    assert(blfp_io_trace[1].port == 0x41e && blfp_io_trace[1].value == 0);
    assert(blfp_io_trace[2].port == 0x448 && blfp_io_trace[2].value == 0x12345);
    assert(blfp_io_trace[5].port == 0x446 && blfp_io_trace[5].value == 0xe0);
    assert(blfp_io_trace[7].port == 0x41b && blfp_io_trace[7].value == 0x21);

    memset(&s, 0, sizeof(s));
    s.DataLength = 8;
    s.Sccb_XferState = 1;
    s.SGEntries[0].length = 8;
    s.SGEntries[0].address = 0x12345678;
    blfp_io_reset();
    busMstrSGDataXferStart(0x400, &s);
    assert(s.Sccb_XferCnt == 8);
    assert(blfp_io_trace[2].port == 0x480 && blfp_io_trace[2].value == 0x12345678);
    assert(blfp_io_trace[3].port == 0x484 && blfp_io_trace[3].value == 0xa1000008);
    assert(blfp_io_trace[4].port == 0x428 && blfp_io_trace[4].value == 16);
    assert(blfp_io_trace[5].port == 0x448 && blfp_io_trace[5].value == 8);
    assert(blfp_io_trace[6].port == 0x446 && blfp_io_trace[6].value == 0xe0);
}

static void host_transfer_abort_completion(void)
{
    struct sccb s;
    memset(&s, 0, sizeof(s));
    s.DataLength = 8;
    blfp_io_reset();
    hostDataXferAbort(0x400, 0, &s);
    assert((s.Sccb_XferState & 2) != 0);
    assert(blfp_io_trace[blfp_io_trace_count - 1].port == 0x417);
    assert(blfp_io_trace[blfp_io_trace_count - 1].value == 5);

    memset(&s, 0, sizeof(s));
    s.DataLength = 8;
    s.Sccb_XferState = 4;
    blfp_io_reset();
    hostDataXferAbort(0x400, 0, &s);
    assert((s.Sccb_XferState & 2) != 0);
    assert(s.Sccb_sgseg == 1 && s.Sccb_SGoffset == 0);
}

static void phase_fifo_residual_accounting(void)
{
    struct sccb s;
    const u32 residual[] = {4};
    memset(&s, 0, sizeof(s));
    BL_Card[0].currentSCCB = &s;
    s.Sccb_scsistat = 7;
    s.Sccb_XferCnt = 10;
    s.Sccb_ATC = 3;
    blfp_io_reset();
    blfp_io_script(0x448, 4, residual, 1);
    phaseChkFifo(0x400, 0);
    assert(s.Sccb_ATC == 9 && s.Sccb_XferCnt == 4);
    assert((s.Sccb_XferState & 2) == 0);
    assert(blfp_io_trace[0].port == 0x448 && !blfp_io_trace[0].write);
    assert(blfp_io_trace[1].port == 0x448 && blfp_io_trace[1].write &&
           blfp_io_trace[1].width == 1);
}

static void message_decode_error_paths(void)
{
    struct sccb s;
    const u32 disconnect[] = {2};
    memset(&s, 0, sizeof(s));
    BL_Card[0].currentSCCB = &s;
    blfp_io_reset();
    assert(scsiDecodeMsg(0x55, 0x400, 0) == 0);
    assert(s.HostStatus == SCCB_PHASE_SEQUENCE_FAIL && s.Sccb_scsistat == 7);
    assert(blfp_io_trace[blfp_io_trace_count - 2].port == 0x444 &&
           blfp_io_trace[blfp_io_trace_count - 2].value == 0x0a);
    assert(blfp_io_trace[blfp_io_trace_count - 1].port == 0x465 &&
           blfp_io_trace[blfp_io_trace_count - 1].value == 0x28);

    blfp_io_reset();
    blfp_io_script(0x474, 1, disconnect, 1);
    assert(phaseMsgIn(0x400, 0) == 0);
    assert(blfp_io_trace_count == 2);
    assert(blfp_io_trace[1].port == 0x465 && blfp_io_trace[1].value == 0x2a);
}

static void dma_completion_phase_filter(void)
{
    struct sccb s;
    memset(&s, 0, sizeof(s));
    BL_Card[0].currentSCCB = &s;
    s.Sccb_scsistat = 6;
    blfp_io_reset();
    assert(scsiChkDmaDone(0x400, 0) == -1);
    assert(blfp_io_trace_count == 0);
}

static void negotiation_register_programming(void)
{
    struct sccb s;
    struct sccb_mgr_target *target = &sccbMgrTbl[0][3];
    const u32 ready[] = {0x80};
    memset(&s, 0, sizeof(s));
    BL_Card[0].currentSCCB = &s;
    s.TargID = 3;
    target->status = 0x40;
    target->eepromValue = 0xff;
    assert(scsiInitSyncNego(0x400, 0) == 0);
    assert(target->status == 0xc0 && target->eepromValue == 0xfc);

    target->status = 0x20;
    target->eepromValue = 0x80;
    assert(scsiInitWideNego(0x400, 0) == 0);
    assert(target->status == 0x20 && target->eepromValue == 0);

    blfp_io_reset();
    blfp_io_script(0x443, 1, ready, 1);
    assert(scsiInitSyncRespond(0x400, 12, 5) == 0x80);
    assert(blfp_io_trace[5].port == 0x48e && blfp_io_trace[5].value == 0x860c);
    assert(blfp_io_trace[7].port == 0x492 && blfp_io_trace[7].value == 0x8605);

    blfp_io_reset();
    blfp_io_script(0x442, 1, ready, 1);
    assert(scsiInitWideRespond(0x400, 1) == 0x80);
    assert(blfp_io_trace[5].port == 0x48e && blfp_io_trace[5].value == 0x6800);
    assert(blfp_io_trace[6].port == 0x492 && blfp_io_trace[6].value == 0x8601);
}

static void busfree_auto_completion_and_msgout(void)
{
    struct sccb s;
    const u32 busFreeStatus[] = {0xa0, 0x80};
    const u32 completeStatus[] = {0};
    struct sccb_mgr_target *target;

    clear_manager();
    memset(&s, 0, sizeof(s));
    s.TargID = 4;
    s.Sccb_scsistat = 3;
    BL_Card[1].currentSCCB = &s;
    target = &sccbMgrTbl[1][4];
    target->eepromValue = 0xff;
    blfp_io_reset();
    assert(phaseBusFree(0x400, 1) == 5);
    assert(target->status == 0xc0 && target->eepromValue == 0xfc);
    assert((BL_Card[1].globalFlags & 0x40) != 0);
    assert(blfp_io_trace[0].port == 0x447 && blfp_io_trace[0].value == 2);

    clear_manager();
    memset(&s, 0, sizeof(s));
    s.TargID = 2;
    s.Lun = 3;
    s.SccbCallback = complete_sccb;
    sccbMgrTbl[0][2].opaque0[3] = 0xaa;
    BL_Card[0].currentSCCB = &s;
    blfp_io_reset();
    blfp_io_script(0x468, 1, completeStatus, 1);
    assert(autoCmdCmplt(0x400, 0) == 0x12345678);
    assert(callback_count == 1 && sccbMgrTbl[0][2].opaque0[3] == 0);

    clear_manager();
    blfp_io_script(0x443, 1, busFreeStatus, 2);
    assert(phaseMsgOut(0x400, 0) == 0);
    assert((BL_CardFlags[0] & 0x40) != 0);
    assert(blfp_io_trace[2].port == 0x474 && blfp_io_trace[2].value == 6);
}

static void scam_wire_cycles(void)
{
    u8 idString[32] = {0};
    u32 cycleEnd[53];
    const u32 cardControl[] = {0x10, 0x10};
    unsigned i, used = 0;

    cycleEnd[used++] = 0x80;
    for (i = 0; i < 16; ++i)
        cycleEnd[used++] = 0;
    cycleEnd[used++] = 0x20;
    cycleEnd[used++] = 0;
    cycleEnd[used++] = 0x20;
    for (i = 0; i < 16; ++i)
        cycleEnd[used++] = 0;
    cycleEnd[used++] = 0x40;
    for (i = 0; i < 16; ++i)
        cycleEnd[used++] = 0;
    assert(used == sizeof(cycleEnd) / sizeof(cycleEnd[0]));

    blfp_io_reset();
    blfp_io_script(0x474, 1, cycleEnd, used);
    assert(ScamIsolate(0x400, idString) == 255);
    assert(blfp_io_trace[0].port == 0x474 && blfp_io_trace[0].write &&
           blfp_io_trace[0].value == 0xa0);

    blfp_io_reset();
    blfp_io_script(0x429, 1, cardControl, 2);
    assert(ScamBusFree(0x400) == 0);
    assert(blfp_io_trace[1].port == 0x429 && blfp_io_trace[1].write &&
           blfp_io_trace[1].value == 0x18);
    assert(blfp_io_trace[blfp_io_trace_count - 1].port == 0x429 &&
           blfp_io_trace[blfp_io_trace_count - 1].value == 0x10);
}

static void manager_entry_abort_and_select(void)
{
    struct sccb s;
    const u32 managerStatus[] = {0, 0x10};

    clear_manager();
    memset(&s, 0, sizeof(s));
    BL_Card[0].ioPort = 0x400;
    BL_Card[0].discQCount = 0;
    s.TargID = 2;
    s.SccbCallback = complete_sccb;
    blfp_io_reset();
    blfp_io_script(0x40c, 1, managerStatus, 2);
    assert(SccbMgr_start_sccb(&BL_Card[0], &s) == 0);
    assert(BL_Card[0].cmdCounter == 1);
    assert(sccbMgrTbl[0][2].selectCount == 1);
    assert(sccbMgrTbl[0][2].selectHead == &s);

    callback_count = 0;
    BL_Card[0].currentSCCB = 0;
    assert(SccbMgr_abort_sccb(&BL_Card[0], &s) == 0);
    assert(callback_count == 1 && s.SccbStatus == 2);
    assert(BL_Card[0].cmdCounter == 0);
    assert(sccbMgrTbl[0][2].selectCount == 0);

    clear_manager();
    memset(&s, 0, sizeof(s));
    BL_Card[1].currentSCCB = &s;
    s.TargID = 3;
    s.CdbLength = 6;
    s.Cdb[0] = 0x12;
    sccbMgrTbl[1][3].status = 0xe0;
    blfp_io_reset();
    assert(scsiSelect(0x400, 1) == 0);
    assert(sccbMgrTbl[1][3].selectEligible == 1);
    assert(blfp_io_trace[blfp_io_trace_count - 1].port == 0x429);
    {
        unsigned i;
        int sawCdb = 0;
        for (i = 0; i < blfp_io_trace_count; ++i) {
            if (blfp_io_trace[i].write && blfp_io_trace[i].port == 0x488 &&
                blfp_io_trace[i].value == 0x8412)
                sawCdb = 1;
        }
        assert(sawCdb);
    }
}

static void scam_id_matching(void)
{
    char idString[32] = {0};
    u8 index;

    clear_manager();
    for (index = 0; index < 16; ++index)
        scamInfo[0][index].state = 17;
    scamInfo[0][3].state = 16;
    idString[0] = 0x21;
    idString[1] = 3;
    assert(scamMatchId(0, idString) == 3);
    assert(scamInfo[0][3].state == 18);
    assert(scamInfo[0][3].idString[0] == 0x21);
    assert((BL_Card[0].globalFlags & 0x80) != 0);

    clear_manager();
    scamInfo[0][5].state = 17;
    for (index = 0; index < sizeof(idString); ++index)
        scamInfo[0][5].idString[index] = (u8)idString[index];
    assert(scamMatchId(0, idString) == 5);
    assert(scamInfo[0][5].state == 18);
    assert(BL_Card[0].globalFlags == 0);
}

int main(void)
{
    clear_manager();
    queue_order_and_removal();
    clear_manager();
    disconnect_and_flush();
    clear_manager();
    residual_updates();
    wait_trace();
    port_widths_and_counters();
    page_boundaries();
    manager_initialization();
    eeprom_serial_paths();
    scsi_setup_paths();
    fetch_message_paths();
    small_phase_and_scam_helpers();
    manager_probe_rejects_bad_signature();
    manager_reset_without_bus_interrupt();
    transfer_restart_paths();
    phase_command_and_data_paths();
    default_map_programming();
    transfer_pad_status_short_circuit();
    bus_master_transfer_registers();
    host_transfer_abort_completion();
    phase_fifo_residual_accounting();
    message_decode_error_paths();
    dma_completion_phase_filter();
    negotiation_register_programming();
    busfree_auto_completion_and_msgout();
    scam_wire_cycles();
    manager_entry_abort_and_select();
    scam_id_matching();
    return 0;
}
