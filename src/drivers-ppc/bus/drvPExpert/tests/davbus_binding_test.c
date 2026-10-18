/* Exercise the production mac-io binder with firmware-shaped properties. */
#include <stdio.h>
#include <string.h>
#include <machdep/ppc/DeviceTree.h>
#include "../powermac/chips/keylargo_audio.h"
#include "../powermac/chips/davbus_audio.h"

typedef int lock_data_t;
#define KEYLARGO_FCR1_OFFSET 0x3c
#define POWERMAC_CLASS_YOSEMITE 1
#define POWERMAC_CLASS_SAWTOOTH 2
static struct { unsigned int io_base_phys,io_size,audio_base_phys; } powermac_io_info;
static struct { unsigned int class; } powermac_info;
static unsigned char mmio[0x80000];
static unsigned int checks,failures,reads,writes,lastOffset,i2cSearches;
static const PEKeyLargoTransport *keywest;
#define CHECK(x) do { ++checks;if(!(x)){++failures;fprintf(stderr,"%d: %s\n",__LINE__,#x);} } while(0)
#define POWERMAC_IO(a) (mmio+((a)-powermac_io_info.io_base_phys))
#define bzero(p,n) memset((p),0,(n))
static void lock_init(lock_data_t *p,boolean_t value) {(void)value;*p=0;}
static void lock_write(lock_data_t *p) {CHECK(!*p);++*p;}
static void lock_done(lock_data_t *p) {CHECK(*p==1);--*p;}
static boolean_t PEIsInInterruptContext(void) {return FALSE;}
static void eieio(void) {}
static void sync(void) {}
static unsigned int lwbrx(unsigned char *p)
{
    ++reads;lastOffset=(unsigned int)(p-mmio);
    return (unsigned int)p[0]|((unsigned int)p[1]<<8)|
        ((unsigned int)p[2]<<16)|((unsigned int)p[3]<<24);
}
static void stwbrx(unsigned int value,unsigned char *p)
{
    ++writes;lastOffset=(unsigned int)(p-mmio);
    p[0]=(unsigned char)value;p[1]=(unsigned char)(value>>8);
    p[2]=(unsigned char)(value>>16);p[3]=(unsigned char)(value>>24);
}
void PEKeyLargoBindTransport(const PEKeyLargoTransport *t) {keywest=t;}
void read_processor_clock_tval(tvalspec_t *now) {memset(now,0,sizeof(*now));}
#define KEYLARGO_BINDING_HOST_TEST 1
#include "../powermac/chips/keylargo.c"

typedef struct { const char *name;unsigned char bytes[24];int size; } Property;
struct OpaqueDTEntry {Property properties[10];unsigned int count;};
struct OpaqueDTEntryIterator {unsigned int child;};
static struct OpaqueDTEntry bus,audio,secondAudio,i2c;
static struct OpaqueDTEntryIterator iterator;
static int duplicate,hasI2C;
static void cell(unsigned char *p,unsigned int v)
{p[0]=(unsigned char)(v>>24);p[1]=(unsigned char)(v>>16);p[2]=(unsigned char)(v>>8);p[3]=(unsigned char)v;}
static Property *add(DTEntry node,const char *name,unsigned int size)
{
    Property *p=&node->properties[node->count++];p->name=name;p->size=(int)size;
    memset(p->bytes,0,sizeof(p->bytes));return p;
}
static Property *word(DTEntry node,const char *name,unsigned int value)
{Property *p=add(node,name,4);cell(p->bytes,value);return p;}
int DTFindEntry(const char *name,const char *value,DTEntry *entry)
{CHECK(!strcmp(name,"device_type") && !strcmp(value,"mac-io"));*entry=&bus;return kSuccess;}
int DTGetProperty(const DTEntry node,const char *name,void **bytes,int *size)
{
    unsigned int j;
    for(j=0;j<node->count;++j) if(!strcmp(node->properties[j].name,name)) {
        *bytes=node->properties[j].bytes;*size=node->properties[j].size;return kSuccess;
    }
    return kError;
}
int DTCreateEntryIterator(const DTEntry node,DTEntryIterator *it)
{CHECK(node==&bus);iterator.child=0;*it=&iterator;return kSuccess;}
int DTIterateEntries(DTEntryIterator it,DTEntry *child)
{
    if(it->child++==0) {*child=&audio;return kSuccess;}
    if(it->child==2 && duplicate) {*child=&secondAudio;return kSuccess;}
    if(hasI2C && it->child==(duplicate?3U:2U)) {
        ++i2cSearches;*child=&i2c;return kSuccess;
    }
    return kIterationDone;
}
int DTDisposeEntryIterator(DTEntryIterator it) {CHECK(it==&iterator);return kSuccess;}
static void fixture(unsigned int device)
{
    Property *p;
    memset(&keylargo_audio_state,0,sizeof(keylargo_audio_state));
    memset(&bus,0,sizeof(bus));memset(&audio,0,sizeof(audio));
    memset(&i2c,0,sizeof(i2c));
    memset(mmio,0,sizeof(mmio));duplicate=hasI2C=0;i2cSearches=0;
    powermac_io_info.io_base_phys=0x80800000U;
    powermac_io_info.io_size=0x80000;
    powermac_io_info.audio_base_phys=0x80814000U;
    powermac_info.class=device==0x17 || device==0x10?
        POWERMAC_CLASS_YOSEMITE:POWERMAC_CLASS_SAWTOOTH;
    word(&bus,"vendor-id",0x106b);word(&bus,"device-id",device);
    word(&bus,"#address-cells",1);word(&bus,"#size-cells",1);
    p=add(&bus,"assigned-addresses",20);cell(p->bytes,0x82008010U);
    cell(p->bytes+8,0x80800000U);cell(p->bytes+16,0x80000);
    p=add(&bus,"ranges",20);cell(p->bytes+4,0x82008010U);
    cell(p->bytes+12,0x80800000U);cell(p->bytes+16,0x80000);
    p=add(&audio,"name",7);memcpy(p->bytes,"davbus",7);
    p=add(&audio,"reg",24);cell(p->bytes,0x14000);cell(p->bytes+4,0x1000);
    cell(p->bytes+8,0x8800);cell(p->bytes+12,0x100);
    cell(p->bytes+16,0x8900);cell(p->bytes+20,0x100);
    secondAudio=audio;
    p=add(&i2c,"name",4);memcpy(p->bytes,"i2c",4);
    word(&i2c,"reg",0x18000);word(&i2c,"AAPL,address-step",0x10);
    word(&i2c,"AAPL,i2c-rate",100);
    keywest=(const PEKeyLargoTransport *)&bus;
    reads=writes=0;
}
static void initialize(unsigned int device)
{
    if(device==0x10 || device==0x17) (void)PEHeathrowDAVBusInitialize();
    else (void)PEKeyLargoInitialize();
}
static void rejected(unsigned int device)
{
    PEDAVBusInfo info;
    initialize(device);
    CHECK(PEDAVBusGetInfo(0x80814000U,&info)==KERN_FAILURE);
    CHECK(!reads && !writes);
}
int main(void)
{
    unsigned int devices[4]={0x22,0x25,0x10,0x17},i;
    PEDAVBusInfo info;
    for(i=0;i<4;++i) {
        fixture(devices[i]);initialize(devices[i]);
        CHECK(!reads && !writes && !keywest);
        CHECK(PEDAVBusGetInfo(0x80814000U,&info)==KERN_SUCCESS);
        CHECK(info.family==PEDAVBusFamilyForMacIO(0x106b,devices[i]));
        CHECK(PEDAVBusSetState(0x80814000U,kPEDAVBusReady)==KERN_SUCCESS);
        CHECK(lastOffset==(i>=2?0x38:0x3c));
        CHECK(PEDAVBusSetState(0x80814000U,kPEDAVBusOff)==KERN_SUCCESS);
    }
    fixture(0x3e);rejected(0x3e);
    fixture(0x17);duplicate=1;rejected(0x17);
    fixture(0x17);bus.properties[5].size=19;rejected(0x17);
    fixture(0x17);cell(bus.properties[5].bytes+12,0x80000000U);rejected(0x17);
    fixture(0x17);cell(audio.properties[1].bytes+16,0x8800);rejected(0x17);
    fixture(0x17);powermac_io_info.audio_base_phys=0x80815000U;rejected(0x17);
    fixture(0x17);powermac_info.class=POWERMAC_CLASS_SAWTOOTH;rejected(0x17);
    fixture(0x17);cell(bus.properties[0].bytes,0x1234);rejected(0x17);
    fixture(0x17);hasI2C=1;(void)PEKeyLargoInitialize();
    CHECK(!i2cSearches && !keywest && !reads && !writes);
    fixture(0x22);CHECK(PEHeathrowDAVBusInitialize()!=KERN_SUCCESS);
    CHECK(PEDAVBusGetInfo(0x80814000U,&info)==KERN_FAILURE);
    fixture(0x22);hasI2C=1;CHECK(PEKeyLargoInitialize()==KERN_SUCCESS);
    CHECK(keywest && !reads && !writes);
    CHECK(PEDAVBusSetState(0x80814000U,kPEDAVBusReady)==KERN_SUCCESS);
    CHECK(*keywest->audioMuxOwner==kPEAudioMuxDAVbus);
    CHECK(PEDAVBusSetState(0x80814000U,kPEDAVBusOff)==KERN_SUCCESS);
    printf("davbus binding: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
