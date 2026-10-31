#ifndef BLFP_IO_MOCK_H
#define BLFP_IO_MOCK_H
#include "../../BusLogicFP.drvproj/BusLogicFP.lksproj/FlashPoint.h"

struct blfp_io_event {
    u16 port;
    u32 value;
    u8 width;
    u8 write;
};

extern struct blfp_io_event blfp_io_trace[512];
extern unsigned blfp_io_trace_count;
void blfp_io_reset(void);
void blfp_io_script(u16 port, u8 width, const u32 *values, unsigned count);
void blfp_io_script_events(const struct blfp_io_event *events, unsigned count);

#endif
