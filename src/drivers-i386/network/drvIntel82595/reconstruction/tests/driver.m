#import "support.h"
#import "Intel82595.h"

/* Exercise production methods through the Objective-C runtime. */
@interface Intel82595 (TestAccess)
- (void)prepare;
- (void)useIRQ:(int)value;
- (unsigned int)usedMemory;
- (unsigned short)txStart;
- (unsigned short)rxEnd;
- (enet_addr_t)address;
@end
@implementation Intel82595 (TestAccess)
- (void)prepare
{
    [super initFromDeviceDescription:nil];
    ioBase = 0x300; irq = 5; currentBank = 3; myStepping = 2;
    networkInterface = [IONetwork new];
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:32];
    memoryUsed = 0; receiveLower = receiveNext = 0; receiveUpper = 0x6400;
    transmitLower = 0x6400; transmitActive = NO;
}
- (void)useIRQ:(int)value { irq = value; }
- (unsigned int)usedMemory { return memoryUsed; }
- (unsigned short)txStart { return transmitLower; }
- (unsigned short)rxEnd { return receiveUpper; }
- (enet_addr_t)address { return myAddress; }
@end

@interface Probe525 : CogentEM525 @end
@implementation Probe525
- initFromDeviceDescription:(IODeviceDescription *)d { probeInits++; return self; }
@end
@interface Probe595 : CogentEM595 @end
@implementation Probe595
- initFromDeviceDescription:(IODeviceDescription *)d { probeInits++; return self; }
@end
@interface Probe10 : IntelEEPro10 @end
@implementation Probe10
- initFromDeviceDescription:(IODeviceDescription *)d { probeInits++; return self; }
@end
@interface ProbePlus : IntelEEPro10Plus @end
@implementation ProbePlus
- initFromDeviceDescription:(IODeviceDescription *)d { probeInits++; return self; }
@end
@interface TestTuple : IOPCMCIATuple { unsigned char bytes[16]; }
- fill:(unsigned char)value;
@end
@implementation IOPCMCIATuple
- (unsigned char)code { return 0; }
- (unsigned int)length { return 0; }
- (unsigned char *)data { return NULL; }
@end
@implementation IOPCMCIADeviceDescription
- (unsigned int)numTuples { return 0; }
- (id *)tupleList { return NULL; }
@end
@implementation TestTuple
- fill:(unsigned char)value { memset(bytes, value, sizeof(bytes)); return self; }
- (unsigned char)code { return 0x22; }
- (unsigned char *)data { return bytes; }
- (unsigned int)length { return 16; }
@end
@interface TestPCMCIA : IOPCMCIADeviceDescription @end
@implementation TestPCMCIA
- (unsigned int)numTuples { return 2; }
- (id *)tupleList
{
    static id tuples[2];
    if (tuples[0] == nil) {
        tuples[0] = [[TestTuple new] fill:0x12];
        tuples[1] = [[TestTuple new] fill:0x34];
    }
    return tuples;
}
@end

static void receiveHeader(unsigned short next, unsigned short status, unsigned short length)
{
    unsigned short *words = (unsigned short *)ram;
    words[0] = 8; words[1] = status; words[2] = next; words[3] = length;
    words[4] = 0x1234; words[5] = 0xabcd;
}

int main(void)
{
    Intel82595 *card;
    IntelEEPro10 *pro;
    IntelEEPro10Plus *plus;
    Intel82595ISA *isa;
    CogentEM595 *pcmcia;
    netbuf_t packet;
    unsigned int length;
    unsigned short buffer[4];
    enet_addr_t address;
    enetMulti_t first, second;
    queue_head_t *queue;
    IOEISADeviceDescription *description = [IOEISADeviceDescription new];

    resetHardware();
    assert([Probe525 probe:description]); assert([Probe595 probe:description]);
    assert([Probe10 probe:description]); assert([ProbePlus probe:description]);
    assert(probeInits == 4 && frees == 0);

    resetHardware(); card = [Intel82595 new]; [card prepare];
    assert([card resetAndEnable:YES]); assert([card isRunning]);
    assert([card usedMemory] == 64512 && [card txStart] == 57344 && [card rxEnd] == 57344);
    assert(regs[1][8] == 0 && regs[1][9] == 223);
    assert(regs[1][10] == 224 && regs[1][11] == 251);
    enableResult = -1;
    assert(![card resetAndEnable:YES]); assert(![card isRunning]);

    resetHardware(); plus = [IntelEEPro10Plus new]; [plus prepare];
    assert([plus rxInit] && [plus txInit]);
    assert([plus usedMemory] == 30720 && [plus txStart] == 25600);
    [plus useIRQ:12]; assert([plus irqConfig]); assert((regs[1][2] & 7) == 7);
    [plus useIRQ:6]; assert(![plus irqConfig]);
    /* Preserve the shipped PRO/10+ busConfig's unconditional YES. */
    assert([plus busConfig]);
    pro = [IntelEEPro10 new]; [pro prepare];
    [pro useIRQ:9]; assert([pro irqConfig]); assert((regs[1][2] & 7) == 0);
    [pro useIRQ:3]; assert([pro irqConfig]); assert((regs[1][2] & 7) == 1);
    isa = [Intel82595ISA new]; [isa prepare];
    [isa useIRQ:9]; assert([isa irqConfig]); assert((regs[1][2] & 7) == 2);
    [pro intelEEPro10PnPInit];
    assert(pnpCount == 34 && pnpBytes[0] == 0 && pnpBytes[1] == 0);
    assert(pnpBytes[2] == 0x6a && pnpBytes[33] == 0x43);

    resetHardware(); [card prepare];
    packet = nb_alloc(3); packet->data[0] = 0x1234; packet->data[1] = 0xabcd;
    [card transmit:packet];
    assert(frees == 1 && loopbacks == 1 && timeoutValue == 3000);
    assert(ram[0x6400] == 4 && ram[0x6406] == 3);
    assert(ram[0x6408] == 0x34 && ram[0x640b] == 0xab);
    packet = nb_alloc(4); [card transmit:packet]; assert(frees == 1);
    ram[0x6402] = 0x23; ram[0x6403] = 0x28;
    assert([card _transmitInterruptOccurred]);
    assert(outputPackets == 1 && collisions == 20 && frees == 2 && loopbacks == 2);

    resetHardware(); [card prepare]; receiveHeader(0x100, 0x2000, 3);
    assert([card _receiveInterruptOccurred]);
    assert(inputPackets == 1 && inputErrors == 0 && locks == 0 && stopPointer == 0xff);
    resetHardware(); [card prepare]; receiveHeader(0x100, 0x2000, 3); allocFails = 1;
    assert([card _receiveInterruptOccurred]);
    assert(inputPackets == 0 && inputErrors == 1 && stopPointer == 0xff && locks == 0);
    resetHardware(); [card prepare]; receiveHeader(0x100, 0x2002, 3); unwanted = 1;
    assert([card _receiveInterruptOccurred]); assert(inputPackets == 0 && frees == 1);
    resetHardware(); [card prepare]; receiveHeader(0, 0x2000, 3);
    length = 0; [card receivePacket:buffer length:&length timeout:0];
    assert(length == 3 && buffer[0] == 0x1234 && buffer[1] == 0xabcd && stopPointer == 0x63ff);
    resetHardware(); [card prepare]; length = 77;
    [card receivePacket:buffer length:&length timeout:0]; assert(length == 0);
    receiveHeader(0x100, 0, 3); length = 77;
    [card receivePacket:buffer length:&length timeout:0]; assert(length == 77);

    resetHardware(); [card prepare]; queue = [card multicastQueue];
    memset(&first, 0, sizeof(first)); memset(&second, 0, sizeof(second));
    memset(&first.address, 0x12, 6); memset(&second.address, 0x34, 6);
    queue->next = (queue_chain_t *)&first; first.link.next = (queue_chain_t *)&second;
    second.link.next = queue;
    [card addMulticastAddress:&first.address];
    assert(ram[0x7400] == 3 && ram[0x7406] == 12);
    assert(ram[0x7408] == 0x12 && ram[0x740e] == 0x34);
    allocFails = 1; assert(![card _mcSetup]);

    resetHardware(); pcmcia = [CogentEM595 new]; [pcmcia prepare];
    deviceDescription = [TestPCMCIA new]; assert([pcmcia coldInit]);
    address = [pcmcia address]; assert(address.ether_addr_octet[0] == 0x12);
    puts("82595 Objective-C driver regressions: passed");
    return 0;
}
