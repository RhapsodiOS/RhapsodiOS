#include "AdaptecU2CHIMPrivate.h"
#include <machdep/ppc/pmap.h>
extern void bcopy(const void *source, void *destination, unsigned int count);

#define OSD_LOAD_LE32(address, value) \
    __asm__ ("lwbrx %0,0,%1" : "=r" (value) : "r" (address) : "memory")
#define OSD_STORE_LE32(address, value) \
    __asm__ volatile ("stwbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")
#define OSD_STORE_LE16(address, value) \
    __asm__ volatile ("sthbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")

void OSDBuildSCB(AdaptecU2HIOB *hiob)
{
    AdaptecU2IOB *iob = hiob->iob;
    AdaptecU2TargetTSCB *target = iob->taskSet.target;
    AdaptecU2AdapterTSCB *adapter = target->adapter;
    adapter->buildSCB(hiob, iob, target, adapter);
}

AdaptecU2BufferDescriptor *OSDGetSGList(AdaptecU2HIOB *hiob)
{
    return &hiob->iob->data;
}

void OSDCompleteHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2IOB *iob = hiob->iob;
    if (hiob->status == 1)
        iob->status = 1;
    else
        SCSIxTranslateError(iob, hiob);
    iob->post(iob);
}

void OSDCompleteSpecialHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2IOB *iob = hiob->iob;
    switch (iob->function) {
    case 4:
        if (iob->taskSet.target->type == 1 &&
            hiob->auxiliary.related != (AdaptecU2HIOB *)0xffffffff)
            iob->sense = (unsigned char *)hiob->auxiliary.related->iob->taskSet.target;
    case 1:
    case 2:
    case 5:
    case 10:
    case 11:
        if (hiob->status == 1)
            iob->status = 1;
        else
            SCSIxTranslateError(iob, hiob);
        break;
    case 6:
        iob->status = 1;
        iob->post(iob);
        if (iob->taskSet.adapter->flags & 0x40000000)
            OSDAsyncEvent(&iob->taskSet.adapter->hhcb, 7);
        return;
    default:
        iob->status = 16;
        break;
    }
    iob->post(iob);
}

unsigned int OSDGetBusAddress(AdaptecU2HHCB *hhcb, unsigned char category,
                              const unsigned char *virtualAddress)
{
    AdaptecU2AdapterTSCB *adapter = (AdaptecU2AdapterTSCB *)((unsigned char *)hhcb - 24);
    return adapter->osm.OSMGetBusAddress(adapter->osmContext, category, virtualAddress);
}

void OSDAdjustBusAddress(AdaptecU2HHCB *hhcb, unsigned int *busAddress, unsigned int offset)
{
    AdaptecU2AdapterTSCB *adapter = (AdaptecU2AdapterTSCB *)((unsigned char *)hhcb - 24);
    adapter->osm.OSMAdjustBusAddress(busAddress, offset);
}

unsigned int OSDReadPciConfiguration(AdaptecU2HHCB *hhcb, unsigned char offset)
{
    AdaptecU2AdapterTSCB *adapter = (AdaptecU2AdapterTSCB *)((unsigned char *)hhcb - 24);
    return adapter->osm.OSMReadPCIConfigurationDword(adapter->osmContext, offset);
}

void OSDWritePciConfiguration(AdaptecU2HHCB *hhcb, unsigned char offset, unsigned int value)
{
    AdaptecU2AdapterTSCB *adapter = (AdaptecU2AdapterTSCB *)((unsigned char *)hhcb - 24);
    adapter->osm.OSMWritePCIConfigurationDword(adapter->osmContext, offset, value);
}

void OSDStandard64BuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                           AdaptecU2TargetTSCB *target, AdaptecU2AdapterTSCB *adapter)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    unsigned char control = 0, length = iob->cdbLength;
    unsigned int count, address;
    scb[35] = 0;
    if (!(hiob->control.flags & 0x2000)) {
        control = 0x40;
        if (hiob->control.flags & 0x4000)
            control |= SCSIscontrol[iob->taskAttribute];
    }
    scb[13] = target->target;
    scb[39] = target->lun;
    if (iob->data.size != 0) {
        OSD_LOAD_LE32(iob->data.virtualAddress + 4, count);
        if (count != 0x80000000) {
            if ((int)count >= 0) {
                OSD_STORE_LE32(scb + 16, iob->data.busAddress);
                control |= 0x80;
            } else
                length |= 0x80;
            OSD_STORE_LE16(scb + 28, count & 0xffff);
            scb[30] = count >> 16;
            OSD_LOAD_LE32(iob->data.virtualAddress, address);
            OSD_STORE_LE32(scb + 24, address);
            scb[15] = 8;
        } else
            length |= 0x40;
    } else
        length |= 0x40;
    scb[14] = length;
    if (iob->cdbLength > 12) {
        bcopy(iob->cdb, iob->reserve.virtualAddress, iob->cdbLength);
        address = iob->reserve.busAddress;
        adapter->osm.OSMAdjustBusAddress(&address, 0);
        OSD_STORE_LE32(scb, address);
    } else
        bcopy(iob->cdb, scb, iob->cdbLength);
    scb[12] = control;
    scb[38] = hiob->scb->next->number;
    OSD_STORE_LE32(scb + 40, hiob->scb->next->busAddress);
    flush_cache((vm_offset_t)scb, 64);
}

void OSDSwapping32BuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                           AdaptecU2TargetTSCB *target, AdaptecU2AdapterTSCB *adapter)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    unsigned char control = 0, length = iob->cdbLength;
    unsigned int count, address;
    scb[0] = 0;
    if (adapter->hhcb.devices[(unsigned char)target->target].flags & 0x4000) {
        if (!(hiob->control.flags & 0x2000)) {
            control = 0x40;
            if (hiob->control.flags & 0x4000)
                control |= SCSIscontrol[iob->taskAttribute];
        }
    }
    scb[2] = target->target;
    scb[31] = target->lun;
    if (iob->data.size != 0) {
        OSD_LOAD_LE32(iob->data.virtualAddress + 4, count);
        if (count != 0x80000000) {
            if ((int)count >= 0) {
                address = iob->data.busAddress;
                adapter->osm.OSMAdjustBusAddress(&address, 8);
                OSD_STORE_LE32(scb + 4, address);
                control |= 0x80;
            } else
                length |= 0x80;
            OSD_STORE_LE16(scb + 24, count & 0xffff);
            scb[26] = count >> 16;
            OSD_LOAD_LE32(iob->data.virtualAddress, address);
            OSD_STORE_LE32(scb + 20, address);
        } else
            length |= 0x40;
    } else
        length |= 0x40;
    scb[3] = length;
    if (iob->cdbLength > 12) {
        bcopy(iob->cdb, iob->reserve.virtualAddress, iob->cdbLength);
        address = iob->reserve.busAddress;
        adapter->osm.OSMAdjustBusAddress(&address, 0);
        OSD_STORE_LE32(scb + 8, address);
    } else
        bcopy(iob->cdb, scb + 8, iob->cdbLength);
    scb[1] = control;
    scb[28] = hiob->scb->next->number;
    flush_cache((vm_offset_t)scb, 32);
}

void OSDStandardAdvBuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                            AdaptecU2TargetTSCB *target, AdaptecU2AdapterTSCB *adapter)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    unsigned char control = 0, lun = target->lun, sgControl = 8;
    unsigned int count, address;
    scb[28] = 0;
    if (!(hiob->control.flags & 0x2000)) {
        lun |= 0x40;
        if (hiob->control.flags & 0x4000)
            control = SCSIscontrol[iob->taskAttribute];
    }
    scb[2] = lun;
    scb[1] = target->target;
    if (iob->data.size != 0) {
        OSD_LOAD_LE32(iob->data.virtualAddress + 4, count);
        if (count != 0x80000000) {
            if ((int)count >= 0) {
                OSD_STORE_LE32(scb + 8, iob->data.busAddress);
                control |= 0x80;
            } else
                sgControl = 10;
            OSD_STORE_LE16(scb + 44, count & 0xffff);
            scb[46] = count >> 16;
            OSD_LOAD_LE32(iob->data.virtualAddress, address);
            OSD_STORE_LE32(scb + 40, address);
        } else
            sgControl = 9;
    } else
        sgControl = 9;
    scb[7] = sgControl;
    scb[6] = iob->cdbLength;
    if (iob->cdbLength > 12) {
        bcopy(iob->cdb, iob->reserve.virtualAddress, iob->cdbLength);
        address = iob->reserve.busAddress;
        adapter->osm.OSMAdjustBusAddress(&address, 0);
        OSD_STORE_LE32(scb + 16, address);
    } else
        bcopy(iob->cdb, scb + 16, iob->cdbLength);
    scb[0] = control;
    scb[5] = hiob->scb->next->number;
    OSD_STORE_LE32(scb + 32, hiob->scb->next->busAddress);
    flush_cache((vm_offset_t)scb, 64);
}

void OSDSwappingAdvBuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                            AdaptecU2TargetTSCB *target, AdaptecU2AdapterTSCB *adapter)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    unsigned char control = 0, lun = target->lun, sgControl = 8;
    unsigned int count, address;
    scb[38] = 0;
    if (adapter->hhcb.devices[(unsigned char)target->target].flags & 0x4000) {
        if (!(hiob->control.flags & 0x2000)) {
            lun |= 0x40;
            if (hiob->control.flags & 0x4000)
                control = SCSIscontrol[iob->taskAttribute];
        }
    }
    scb[13] = lun;
    scb[12] = target->target;
    if (iob->data.size != 0) {
        OSD_LOAD_LE32(iob->data.virtualAddress + 4, count);
        if (count != 0x80000000) {
            if ((int)count >= 0) {
                OSD_STORE_LE32(scb + 16, iob->data.busAddress);
                control |= 0x80;
            } else
                sgControl = 10;
            OSD_STORE_LE16(scb + 4, count & 0xffff);
            scb[6] = count >> 16;
            OSD_LOAD_LE32(iob->data.virtualAddress, address);
            OSD_STORE_LE32(scb, address);
        } else
            sgControl = 9;
    } else
        sgControl = 9;
    scb[15] = sgControl;
    scb[14] = iob->cdbLength;
    if (iob->cdbLength > 12) {
        bcopy(iob->cdb, iob->reserve.virtualAddress, iob->cdbLength);
        address = iob->reserve.busAddress;
        adapter->osm.OSMAdjustBusAddress(&address, 0);
        OSD_STORE_LE32(scb + 24, address);
    } else
        bcopy(iob->cdb, scb + 24, iob->cdbLength);
    scb[38] = control;
    scb[11] = hiob->scb->next->number;
    flush_cache((vm_offset_t)scb, 64);
}

void OSDAsyncEvent(AdaptecU2HHCB *hhcb, unsigned int event, ...)
{
    AdaptecU2AdapterTSCB *adapter = (AdaptecU2AdapterTSCB *)((unsigned char *)hhcb - 24);
    unsigned int mapped = 0;
    switch (event - 1) {
    case 0: mapped = 1; break;
    case 2: mapped = 3; break;
    case 4: mapped = 2; break;
    case 5:
        mapped = 4;
        adapter->flags |= 0x40000000;
        break;
    case 6:
        mapped = 5;
        adapter->flags &= ~0x40000000;
        break;
    case 7: mapped = 8; break;
    default: break;
    }
    adapter->osm.OSMEvent(adapter->osmContext, mapped, 0);
}

AdaptecU2PciLocation *OSDGetHostAddress(AdaptecU2HHCB *hhcb)
{
    return (AdaptecU2PciLocation *)((unsigned char *)hhcb - 16);
}
