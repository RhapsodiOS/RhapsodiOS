#include "io_mock.h"

struct blfp_io_event blfp_io_trace[512];
unsigned blfp_io_trace_count;

static u16 script_port;
static u8 script_width;
static const u32 *script_values;
static unsigned script_count;
static unsigned script_index;
static const struct blfp_io_event *script_events;
static unsigned script_event_count;

void blfp_io_reset(void)
{
    blfp_io_trace_count = 0;
    script_port = 0;
    script_width = 0;
    script_values = 0;
    script_count = 0;
    script_index = 0;
    script_events = 0;
    script_event_count = 0;
}

void blfp_io_script(u16 port, u8 width, const u32 *values, unsigned count)
{
    script_port = port;
    script_width = width;
    script_values = values;
    script_count = count;
    script_index = 0;
    script_events = 0;
    script_event_count = 0;
}

void blfp_io_script_events(const struct blfp_io_event *events, unsigned count)
{
    script_events = events;
    script_event_count = count;
    script_index = 0;
    script_count = 0;
}

static u32 blfp_read(u16 port, u8 width)
{
    u32 value = 0;
    if (script_events != 0 && script_index < script_event_count) {
        const struct blfp_io_event *event = &script_events[script_index];
        if (event->port == port && event->width == width && !event->write)
            value = event->value;
        ++script_index;
    } else if (script_events != 0) {
        value = 0xff;
    } else if (port == script_port && width == script_width && script_index < script_count) {
        value = script_values[script_index++];
    }
    blfp_io_trace[blfp_io_trace_count++] = (struct blfp_io_event){port, value, width, 0};
    return value;
}

static void blfp_write(u16 port, u32 value, u8 width)
{
    blfp_io_trace[blfp_io_trace_count++] = (struct blfp_io_event){port, value, width, 1};
}

u8 blfp_test_in8(u16 port) { return (u8)blfp_read(port, 1); }
u16 blfp_test_in16(u16 port) { return (u16)blfp_read(port, 2); }
u32 blfp_test_in32(u16 port) { return blfp_read(port, 4); }
void blfp_test_out8(u16 port, u8 value) { blfp_write(port, value, 1); }
void blfp_test_out16(u16 port, u16 value) { blfp_write(port, value, 2); }
void blfp_test_out32(u16 port, u32 value) { blfp_write(port, value, 4); }

#ifdef BLFP_TEST_STUB_SCAM_INIT
int ScamInit(u8 cardIndex, u8 adapterId, int reserved)
{
    (void)cardIndex;
    (void)adapterId;
    (void)reserved;
    return 0;
}
#endif

