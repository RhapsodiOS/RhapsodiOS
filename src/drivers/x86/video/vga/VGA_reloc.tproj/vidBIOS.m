/*
 * vidBIOS.m
 * VGA BIOS Emulation and Utility Functions
 *
 * Video BIOS support functions and VGA plane manipulation
 *
 * ============================================================================
 * FUNCTION ORGANIZATION
 * ============================================================================
 *
 * [Lines 170-226] CPU EMULATOR
 *   _emu486                            @ 0x1d40: Main 486 instruction emulator
 *
 * [Lines 228-335] VGA PLANE SELECTION
 *   _select_read_plane                 @ 0x2170: Select VGA read plane (0-3)
 *   _select_read_segment               @ 0x21a0: Select VGA read segment
 *   _select_write_plane                @ 0x2200: Select VGA write plane (0-3)
 *   _select_write_segment              @ 0x2240: Select VGA write segment
 *
 * [Lines 337-433] PIXEL FORMAT CONVERSION
 *   _vga_read_bpp4planar_to_bpp2packed32   @ 0x2290: Planar to packed conversion
 *   _vga_write_bpp2packed32_to_bpp4planar  @ 0x2380: Packed to planar conversion
 *
 * [Lines 435-669] CURSOR OPERATIONS
 *   _VGADisplayCursor                  @ 0x2470: Draw hardware cursor
 *   _VGARemoveCursor                   @ 0x2620: Remove/restore cursor
 *
 * [Lines 671-694] UTILITY FUNCTIONS
 *   _find_parameter                    @ 0x2e40: Parameter string search
 *   _SetET4000Brightness               @ 0x2f80: DAC brightness control
 *
 * [Lines 696-740] OPCODE HANDLER DEFAULT
 *   opcode_handler_default             Default stub for unimplemented opcodes
 *
 * [Lines 742-817] JUMP TABLES
 *   PTR_LAB_00003d90[256]              @ 0x3d90: Main opcode dispatch table
 *   PTR_LAB_00004190[256]              @ 0x4190: ModR/M dispatch table 1
 *   PTR_LAB_00004290[256]              @ 0x4290: ModR/M dispatch table 2
 *   PTR_DAT_00004390[256]              @ 0x4390: Register dispatch table
 *   PTR_LAB_00004640[256]              @ 0x4640: Parameter dispatch table
 *
 * [Lines 866-1079] EMU486 HELPER FUNCTIONS (static inline, internal only)
 *   emu486_get_jump_table_entry        @ 0x3893: Jump table lookup via ESI
 *   emu486_get_gp_register_ptr         @ 0x38a1: Get GP register pointer
 *   emu486_get_segment_register_ptr    @ 0x38ae: Get segment register pointer
 *   emu486_dispatch_modrm_1            @ 0x38bc: ModR/M dispatch (table 1)
 *   emu486_dispatch_modrm_2            @ 0x38d4: ModR/M dispatch (table 2)
 *   emu486_validate_address_bx_si      @ 0x38ec: Validate [BX+SI] addressing
 *   emu486_validate_address_bx_di      @ 0x3954: Validate [BX+DI] addressing
 *   emu486_validate_address_bp_si      @ 0x3968: Validate [BP+SI] addressing
 *   emu486_validate_address_bp_di      @ 0x397c: Validate [BP+DI] addressing
 *   emu486_validate_address_si         @ 0x3990: Validate [SI] addressing
 *   emu486_validate_address_di         @ 0x399c: Validate [DI] addressing
 *   emu486_validate_address_direct     @ 0x39a8: Validate [disp16] direct addressing
 *   emu486_validate_address_bx         @ 0x39b4: Validate [BX] addressing
 *   emu486_validate_memory_access      @ 0x3917: Memory bounds checking (general)
 *   emu486_dispatch_param              @ 0x3d18: Parameter-based dispatch
 *   emu486_check_io_permission         @ 0x3d69: I/O port permission check
 *
 * ============================================================================
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOVGAShared.h>
#import <driverkit/i386/ioPorts.h>
#import "IOVGADisplay.h"

// External globals from IOVGADisplay.m
extern unsigned int colr_mode;
extern unsigned int curr_read_plane;
extern unsigned int curr_write_plane;
extern unsigned int curr_read_segment;
extern unsigned int curr_write_segment;

// EMU486 state variables (from data section)
extern unsigned int DAT_00006060;      // Base pointer
extern unsigned int DAT_00006064;      // Page table pointer
extern unsigned int DAT_00006068;      // I/O permission bitmap pointer
extern unsigned int DAT_0000606c;      // Reserved
extern unsigned int DAT_00006070;      // EAX
extern unsigned int DAT_00006074;      // ECX
extern unsigned int DAT_00006078;      // EDX
extern unsigned int DAT_0000607c;      // EBX
extern unsigned int DAT_00006080;      // ESP
extern unsigned int DAT_00006084;      // EBP
extern unsigned int DAT_00006088;      // ESI
extern unsigned int DAT_0000608c;      // EDI
extern unsigned int DAT_00006090;      // IP
extern unsigned char DAT_00006094;     // FLAGS (low byte)
extern unsigned int DAT_00006098;      // CS
extern unsigned int DAT_0000609c;      // SS
extern unsigned int DAT_000060a0;      // DS
extern unsigned int DAT_000060a4;      // ES
extern unsigned int DAT_000060a8;      // FS
extern unsigned int DAT_000060ac;      // GS
extern unsigned char DAT_000060b4;     // Reserved (0x80c value for instruction dispatch)
extern unsigned char DAT_000060b5;     // Reserved
extern unsigned char DAT_000060b6;     // Reserved
extern unsigned char DAT_000060b7;     // Opcode dispatch flags
extern unsigned char DAT_000060b8;     // FLAGS (high byte)

// Individual EFLAGS bits (extracted by Ghidra from register state)
// These represent individual flag bits used in complex flag calculations
extern unsigned char unaff_AF;         // Auxiliary Carry Flag
extern unsigned char unaff_TF;         // Trap Flag
extern unsigned char unaff_IF;         // Interrupt Enable Flag
extern unsigned char unaff_NT;         // Nested Task Flag
extern unsigned char unaff_AC;         // Alignment Check
extern unsigned char unaff_VIF;        // Virtual Interrupt Flag
extern unsigned char unaff_VIP;        // Virtual Interrupt Pending
extern unsigned char unaff_ID;         // ID Flag

// Operation counter for VGA register access
static unsigned int __xxx_100 = 0;

/*
 * ============================================================================
 * EMU486 - x86 Real Mode Instruction Emulator
 * ============================================================================
 *
 * This emulator executes 16-bit real mode x86 instructions for VESA BIOS calls.
 * It implements a subset of the 486 instruction set needed for video BIOS.
 *
 * ARCHITECTURE:
 * -------------
 * 1. Main dispatch table (PTR_LAB_00003d90) - 256 entries indexed by opcode byte
 * 2. ModR/M dispatch tables (PTR_LAB_00004190, PTR_LAB_00004290) - For complex addressing
 * 3. Helper tables (PTR_DAT_00004390, PTR_LAB_00004640) - For register/parameter dispatch
 *
 * INSTRUCTION HANDLER NAMING:
 * ---------------------------
 * opcode_handler_XX - Where XX is the hexadecimal opcode (e.g., opcode_handler_B8 for MOV AX)
 *
 * COMMON x86 OPCODES (for reference when implementing):
 * -----------------------------------------------------
 * 0x00-0x05: ADD operations        0x88-0x8B: MOV reg/mem
 * 0x08-0x0D: OR operations         0xA0-0xA3: MOV accumulator
 * 0x20-0x25: AND operations        0xB0-0xBF: MOV immediate
 * 0x30-0x35: XOR operations        0xC3: RET near
 * 0x50-0x5F: PUSH/POP registers    0xCD: INT (software interrupt)
 * 0x70-0x7F: Conditional jumps     0xE8-0xE9: CALL/JMP
 * 0x80-0x83: Immediate operations  0xF6-0xF7: TEST/NOT/NEG/MUL/DIV
 *
 * TO POPULATE THIS TABLE:
 * -----------------------
 * 1. Examine decompiled code to identify handler functions
 * 2. Rename FUN_XXXXXXXX to opcode_handler_XX based on opcode
 * 3. Update jump table entries to point to correct handlers
 * 4. Implement missing handlers as needed
 */

// Forward declarations for x86 opcode handlers
void opcode_handler_default(void);  // Unimplemented opcode handler

// Opcode handlers are implemented later in this file (see line ~860+)
// No forward declarations needed - handlers are defined before jump table initialization

// Main x86 opcode dispatch table (256 entries, indexed by opcode byte)
// This is referenced at address 0x3d90 in the original binary
void *PTR_LAB_00003d90[256] = {
    // 0x00 - 0x0F
    opcode_handler_default,  // 0x00: ADD Eb, Gb
    opcode_handler_default,  // 0x01: ADD Ev, Gv
    opcode_handler_default,  // 0x02: ADD Gb, Eb
    opcode_handler_default,  // 0x03: ADD Gv, Ev
    opcode_handler_default,  // 0x04: ADD AL, Ib
    opcode_handler_default,  // 0x05: ADD eAX, Iv
    opcode_handler_default,  // 0x06: PUSH ES
    opcode_handler_default,  // 0x07: POP ES
    opcode_handler_default,  // 0x08: OR Eb, Gb
    opcode_handler_default,  // 0x09: OR Ev, Gv
    opcode_handler_default,  // 0x0A: OR Gb, Eb
    opcode_handler_default,  // 0x0B: OR Gv, Ev
    opcode_handler_default,  // 0x0C: OR AL, Ib
    opcode_handler_default,  // 0x0D: OR eAX, Iv
    opcode_handler_default,  // 0x0E: PUSH CS
    opcode_handler_default,  // 0x0F: Two-byte escape

    // 0x10 - 0x1F
    opcode_handler_default,  // 0x10: ADC Eb, Gb
    opcode_handler_default,  // 0x11: ADC Ev, Gv
    opcode_handler_default,  // 0x12: ADC Gb, Eb
    opcode_handler_default,  // 0x13: ADC Gv, Ev
    opcode_handler_default,  // 0x14: ADC AL, Ib
    opcode_handler_default,  // 0x15: ADC eAX, Iv
    opcode_handler_default,  // 0x16: PUSH SS
    opcode_handler_default,  // 0x17: POP SS
    opcode_handler_default,  // 0x18: SBB Eb, Gb
    opcode_handler_default,  // 0x19: SBB Ev, Gv
    opcode_handler_default,  // 0x1A: SBB Gb, Eb
    opcode_handler_default,  // 0x1B: SBB Gv, Ev
    opcode_handler_default,  // 0x1C: SBB AL, Ib
    opcode_handler_default,  // 0x1D: SBB eAX, Iv
    opcode_handler_default,  // 0x1E: PUSH DS
    opcode_handler_default,  // 0x1F: POP DS

    // TODO: Add remaining 0x20-0xFF entries
    // For now, fill with default handler
    [0x20 ... 0xFF] = opcode_handler_default
};

// VRAM buffer for cursor operations
static unsigned int _vramBuf_125 = 0;
static unsigned int _vramBuf_129 = 0;
static unsigned int DAT_000060cc = 0;
static unsigned int DAT_000060d4 = 0;

// Reference to mask array (defined in IOVGADisplay.m)
extern const unsigned int mask_array[16];

// VGA register ports
#define VGA_GC_INDEX        0x3CE
#define VGA_GC_DATA         0x3CF
#define VGA_SEQ_INDEX       0x3C4
#define VGA_SEQ_DATA        0x3C5
#define VGA_CRTC_INDEX      0x3D4
#define VGA_CRTC_DATA       0x3D5
#define VGA_SEGMENT_REG     0x3CD  // Segment select register

// VGA Graphics Controller registers
#define VGA_GC_READ_MAP     0x04  // Read Map Select
#define VGA_GC_MODE         0x05  // Graphics Mode

// VGA Sequencer registers
#define VGA_SEQ_MAP_MASK    0x02  // Map Mask (write plane select)

// VGA CRT Controller registers
#define VGA_CRTC_EXT_REG    0x36  // Extended register for segment control

// Ghidra pseudo-C helper macros
#define CONCAT22(high16, low16) ((unsigned int)((unsigned short)(high16) << 16) | (unsigned short)(low16))
#define CONCAT31(high24, low8) ((unsigned int)(((unsigned int)(high24) & 0xFFFFFF) << 8) | (unsigned char)(low8))

// CPU flag calculation macros (matching Ghidra's analysis)
#define POPCOUNT(x) __builtin_popcount(x)

// 8-bit (byte) carry/borrow macros
#define CARRY1(a, b) ((unsigned char)(a) + (unsigned char)(b) > 0xFF)
#define SCARRY1(a, b) (((char)(a) > 0 && (char)(b) > 0 && (char)((a)+(b)) < 0) || \
                       ((char)(a) < 0 && (char)(b) < 0 && (char)((a)+(b)) >= 0))
#define SBORROW1(a, b) (((char)(a) >= 0 && (char)(b) < 0 && (char)((a)-(b)) < 0) || \
                        ((char)(a) < 0 && (char)(b) >= 0 && (char)((a)-(b)) >= 0))

// 16-bit (word) carry/borrow macros
#define CARRY2(a, b) ((unsigned short)(a) + (unsigned short)(b) > 0xFFFF)
#define SCARRY2(a, b) (((short)(a) > 0 && (short)(b) > 0 && (short)((a)+(b)) < 0) || \
                       ((short)(a) < 0 && (short)(b) < 0 && (short)((a)+(b)) >= 0))
#define SBORROW2(a, b) (((short)(a) >= 0 && (short)(b) < 0 && (short)((a)-(b)) < 0) || \
                        ((short)(a) < 0 && (short)(b) >= 0 && (short)((a)-(b)) >= 0))

// 32-bit (dword) carry/borrow macros
#define CARRY4(a, b) ((unsigned int)(a) + (unsigned int)(b) > 0xFFFFFFFF || \
                      (unsigned int)(a) + (unsigned int)(b) < (unsigned int)(a))
#define SCARRY4(a, b) (((int)(a) > 0 && (int)(b) > 0 && (int)((a)+(b)) < 0) || \
                       ((int)(a) < 0 && (int)(b) < 0 && (int)((a)+(b)) >= 0))
#define SBORROW4(a, b) (((int)(a) >= 0 && (int)(b) < 0 && (int)((a)-(b)) < 0) || \
                        ((int)(a) < 0 && (int)(b) >= 0 && (int)((a)-(b)) >= 0))

/*
 * 486 emulator for BIOS calls
 * Emulates 16-bit real mode x86 code execution
 */
unsigned int _emu486(unsigned char *base_ptr, unsigned int *in_regs, unsigned int *out_regs,
                     unsigned int param4, unsigned int param5, unsigned int param6)
{
    unsigned int *reg_ptr;
    unsigned char *ip;
    int i;

    // Save parameters
    DAT_00006064 = param4;
    DAT_00006068 = param5;
    DAT_0000606c = param6;
    DAT_00006060 = (unsigned int)base_ptr;

    // Copy input registers (16 dwords)
    reg_ptr = (unsigned int *)&DAT_00006070;
    for (i = 0; i < 0x10; i++) {
        reg_ptr[i] = in_regs[i];
    }

    // Convert segment registers to linear addresses
    DAT_000060a4 = (unsigned int)(base_ptr + (DAT_000060a4 * 0x10));  // ES
    DAT_00006098 = (unsigned int)(base_ptr + (DAT_00006098 * 0x10));  // CS
    DAT_0000609c = (unsigned int)(base_ptr + (DAT_0000609c * 0x10));  // SS
    DAT_000060a0 = (unsigned int)(base_ptr + (DAT_000060a0 * 0x10));  // DS
    DAT_000060a8 = (unsigned int)(base_ptr + (DAT_000060a8 * 0x10));  // FS
    DAT_000060ac = (unsigned int)(base_ptr + (DAT_000060ac * 0x10));  // GS

    // Calculate instruction pointer
    ip = (unsigned char *)(DAT_0000609c + DAT_00006090);

    // Initialize flags
    DAT_000060b8 = 0;
    DAT_00006094 = 0x40 | 0x04;

    // Execute instructions via jump table until we hit base_ptr
    if ((unsigned int)ip != DAT_00006060) {
        DAT_000060b4 = 0x80c;
        // Jump to instruction handler based on opcode
        ((void (*)(void))(PTR_LAB_00003d90[*ip]))();
    }

    // Convert linear addresses back to segment:offset
    DAT_00006090 = (unsigned int)ip - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    // Copy output registers
    reg_ptr = (unsigned int *)&DAT_00006070;
    for (i = 0; i < 0x10; i++) {
        out_regs[i] = reg_ptr[i];
    }

    return 0;
}

/*
 * VGA plane selection functions
 */
void _select_read_plane(unsigned char plane)
{
    unsigned char reg_val;

    // Read current Graphics Controller index
    reg_val = inb(VGA_GC_INDEX);
    outb(VGA_GC_INDEX, (reg_val & 0xF0) | VGA_GC_READ_MAP);
    __xxx_100++;

    // Read current value
    reg_val = inb(VGA_GC_DATA);

    // Write index again
    reg_val = inb(VGA_GC_INDEX);
    outb(VGA_GC_INDEX, (reg_val & 0xF0) | VGA_GC_READ_MAP);
    __xxx_100++;

    // Write new plane value
    outb(VGA_GC_DATA, (reg_val & 0xFC) | (plane & 0x03));
    __xxx_100 += 3;

    curr_read_plane = (int)(char)plane;
}

void _select_read_segment(char segment)
{
    int saved_xxx_100;
    unsigned char reg_val;

    saved_xxx_100 = __xxx_100;

    // Check CRTC extended register
    reg_val = inb(VGA_CRTC_INDEX);
    outb(VGA_CRTC_INDEX, (reg_val & 0xC0) | VGA_CRTC_EXT_REG);
    __xxx_100++;

    reg_val = inb(VGA_CRTC_DATA);

    // Only proceed if bit 4 is clear
    if ((reg_val & 0x10) == 0) {
        // Read segment register and set upper nibble
        reg_val = inb(VGA_SEGMENT_REG);
        reg_val = (reg_val & 0x0F) | (segment << 4);
        outb(VGA_SEGMENT_REG, reg_val);
        __xxx_100 = saved_xxx_100 + 2;

        curr_read_segment = (int)segment;
    }
}

void _select_write_plane(unsigned char plane)
{
    unsigned char mask;
    unsigned char reg_val;

    // Convert plane number to bit mask
    mask = 1 << (plane & 0x03);

    // Read current Sequencer index
    reg_val = inb(VGA_SEQ_INDEX);
    outb(VGA_SEQ_INDEX, (reg_val & 0xF8) | VGA_SEQ_MAP_MASK);
    __xxx_100++;

    // Read current value
    reg_val = inb(VGA_SEQ_DATA);

    // Write index again
    reg_val = inb(VGA_SEQ_INDEX);
    outb(VGA_SEQ_INDEX, (reg_val & 0xF8) | VGA_SEQ_MAP_MASK);
    __xxx_100++;

    // Write new mask value
    outb(VGA_SEQ_DATA, (reg_val & 0xF0) | mask);
    __xxx_100 += 3;

    curr_write_plane = (int)(char)plane;
}

void _select_write_segment(unsigned char segment)
{
    int saved_xxx_100;
    unsigned char reg_val;

    saved_xxx_100 = __xxx_100;

    // Check CRTC extended register
    reg_val = inb(VGA_CRTC_INDEX);
    outb(VGA_CRTC_INDEX, (reg_val & 0xC0) | VGA_CRTC_EXT_REG);
    __xxx_100++;

    reg_val = inb(VGA_CRTC_DATA);

    // Only proceed if bit 4 is clear
    if ((reg_val & 0x10) == 0) {
        // Read segment register and set lower nibble
        reg_val = inb(VGA_SEGMENT_REG);
        reg_val = (reg_val & 0xF0) | (segment & 0x0F);
        outb(VGA_SEGMENT_REG, reg_val);
        __xxx_100 = saved_xxx_100 + 2;

        curr_write_segment = (int)(char)segment;
    }
}

/*
 * VGA pixel format conversion functions
 */
void _vga_read_bpp4planar_to_bpp2packed32(unsigned short *src, unsigned int *dst)
{
    unsigned int plane1_data;
    unsigned int plane0_data;

    // Read from plane 1 (inverted)
    _select_read_plane(1);
    plane1_data = (unsigned int)(unsigned short)~(*src);

    // Read from plane 0 (inverted)
    _select_read_plane(0);
    plane0_data = (unsigned int)(unsigned short)~(*src);

    // Convert from 4bpp planar to 2bpp packed32 format
    // This does complex bit interleaving between the two planes
    *dst =
        // Plane 1 bits
        ((plane1_data & 0x8000) << 2) | ((plane1_data & 0x4000) << 5) |
        ((plane1_data & 0x2000) << 8) | ((plane1_data & 0x1000) << 0xB) |
        ((plane1_data & 0x0800) << 0xE) | ((plane1_data & 0x0400) << 0x11) |
        ((plane1_data & 0x0200) << 0x14) | ((plane1_data & 0x0100) << 0x17) |
        ((plane1_data & 0x0080) >> 6) | ((plane1_data & 0x0040) >> 3) |
        ((plane1_data & 0x0020)) | ((plane1_data & 0x0010) << 3) |
        ((plane1_data & 0x0008) << 6) | ((plane1_data & 0x0004) << 9) |
        ((plane1_data & 0x0002) << 0xC) | ((plane1_data & 0x0001) << 0xF) |

        // Plane 0 bits
        ((plane0_data & 0x8000) * 2) | ((plane0_data & 0x4000) << 4) |
        ((plane0_data & 0x2000) << 7) | ((plane0_data & 0x1000) << 10) |
        ((plane0_data & 0x0800) << 0xD) | ((plane0_data & 0x0400) << 0x10) |
        ((plane0_data & 0x0200) << 0x13) | ((plane0_data & 0x0100) << 0x16) |
        ((plane0_data & 0x0080) >> 7) | ((plane0_data & 0x0040) >> 4) |
        ((plane0_data & 0x0020) >> 1) | ((plane0_data & 0x0010) << 2) |
        ((plane0_data & 0x0008) << 5) | ((plane0_data & 0x0004) << 8) |
        ((plane0_data & 0x0002) << 0xB) | ((plane0_data & 0x0001) << 0xE);
}

void _vga_write_bpp2packed32_to_bpp4planar(unsigned int *src, unsigned short *dst)
{
    unsigned int data;
    unsigned char low_byte;
    unsigned char high_byte;
    unsigned int high_word;
    unsigned char high_word_low_byte;

    // Write to plane 1
    _select_write_plane(1);
    data = *src;
    low_byte = (unsigned char)data;
    high_word = data >> 16;
    high_word_low_byte = (unsigned char)(data >> 16);

    *dst = ((unsigned short)(~(
        (unsigned char)(data >> 0x1F) |
        (unsigned char)((high_word & 0x2000) >> 0xC) |
        (unsigned char)((high_word & 0x0800) >> 9) |
        (unsigned char)((high_word & 0x0200) >> 6) |
        (unsigned char)((high_word & 0x0080) >> 3) |
        (high_word_low_byte & 0x20) |
        ((high_word_low_byte & 0x08) << 3) |
        ((high_word_low_byte & 0xAA) << 6)
    )) << 8) | (unsigned short)(~(
        (unsigned char)((data & 0x8000) >> 0xF) |
        (unsigned char)((data & 0x2000) >> 0xC) |
        (unsigned char)((data & 0x0800) >> 9) |
        (unsigned char)((data & 0x0200) >> 6) |
        (unsigned char)((data & 0x0080) >> 3) |
        (low_byte & 0x20) |
        ((low_byte & 0x08) << 3) |
        ((low_byte & 0xAA) << 6)
    ));

    // Write to plane 0
    _select_write_plane(0);
    data = *src;
    low_byte = (unsigned char)data;
    high_word = data >> 16;
    high_word_low_byte = (unsigned char)(data >> 16);

    *dst = ((unsigned short)(~(
        (unsigned char)((high_word & 0x5555) >> 0xE) |
        (unsigned char)((high_word & 0x1000) >> 0xB) |
        ((unsigned char)(data >> 0x18) & 4) |
        (unsigned char)((high_word & 0x0100) >> 5) |
        (unsigned char)((high_word & 0x0040) >> 2) |
        ((high_word_low_byte & 0x10) * 2) |
        ((high_word_low_byte & 0x04) << 4) |
        (high_word_low_byte << 7)
    )) << 8) | (unsigned short)(~(
        (unsigned char)((data & 0x4000) >> 0xE) |
        (unsigned char)((data & 0x1000) >> 0xB) |
        ((unsigned char)(data >> 8) & 4) |
        (unsigned char)((data & 0x0100) >> 5) |
        (unsigned char)((data & 0x0040) >> 2) |
        ((low_byte & 0x10) * 2) |
        ((low_byte & 0x04) << 4) |
        (low_byte << 7)
    ));
}

/*
 * VGA cursor functions
 */
void _VGADisplayCursor(int *displayInfo, int *shmem)
{
    unsigned short cursorPos;
    unsigned int saved_read_segment;
    unsigned int saved_read_plane;
    unsigned char saved_seq_reg;
    unsigned char seq_val;
    unsigned int top, bottom, left, right;
    short aligned_left;
    unsigned int *saveBuffer;
    unsigned int *cursorImage;
    unsigned int *cursorMask;
    short clip_top;
    int rowBytes;
    unsigned int bankSize;
    unsigned int row, col;
    int vramAddr;
    unsigned char leftShift;
    unsigned char rightShift;
    short clip_right;

    // Save VGA state
    saved_read_segment = curr_read_segment;
    saved_read_plane = curr_read_plane;
    seq_val = inb(VGA_SEQ_INDEX);
    outb(VGA_SEQ_INDEX, (seq_val & 0xF8) | VGA_SEQ_MAP_MASK);
    __xxx_100++;
    saved_seq_reg = inb(VGA_SEQ_DATA);

    // Get cursor position and bounds from shmem
    bottom = shmem[9];
    top = shmem[0xd];
    left = (short)bottom;

    // Adjust top if needed
    if ((short)bottom < (short)top) {
        top = (top & 0xFFFF0000) | left;
    }

    // Adjust bottom if needed
    if ((short)(top >> 16) < (short)(bottom >> 16)) {
        bottom = (bottom & 0xFFFF) | ((top >> 16) << 16);
    }

    // Calculate aligned left edge (16-pixel aligned)
    clip_top = (short)shmem[0xc];
    clip_right = (short)shmem[0xc];
    aligned_left = ((short)shmem[8] - clip_right) & 0xFFF0;
    aligned_left += clip_right;

    // Store cursor bounds in shmem
    shmem[3] = (aligned_left + 0x20) << 16 | (unsigned short)aligned_left;
    shmem[4] = bottom;

    // Calculate cursor position and shift amounts
    cursorPos = *(unsigned short *)(shmem + 8);
    leftShift = (cursorPos & 0xF) * 2;
    rightShift = (cursorPos & 0xF) * -2 + 0x20;

    // Get pointers to buffers
    saveBuffer = (unsigned int *)(shmem + 0x92);  // Offset 0x248 bytes
    row = (short)bottom - (short)shmem[9];
    cursorImage = (unsigned int *)(shmem + shmem[0] * 0x10 + row + 0x12);
    cursorMask = (unsigned int *)(shmem + shmem[0] * 0x10 + row + 0x52);

    // Calculate VRAM address and segment
    clip_right = (short)((unsigned int)shmem[0xc] >> 16);
    rowBytes = displayInfo[0] >> 4;  // Bytes per row / 16
    bankSize = 0x10000 / rowBytes;
    col = (short)bottom - (short)top;
    vramAddr = ((aligned_left - clip_top) >> 4) * 2 + 0xA0000 +
               (col % bankSize) * rowBytes * 2;

    // Set initial segment
    _select_write_segment(col / bankSize);
    _select_read_segment(col / bankSize);

    // Draw cursor scanlines
    if (col < ((bottom >> 16) - top)) {
        do {
            // Check if we need to switch segments
            if (col % bankSize == 0) {
                _select_write_segment(col / bankSize);
                _select_read_segment(col / bankSize);
            }

            // Draw left part of cursor
            if (clip_top <= aligned_left) {
                _vga_read_bpp4planar_to_bpp2packed32((unsigned short *)vramAddr, &_vramBuf_125);
                *saveBuffer = _vramBuf_125;
                saveBuffer++;
                _vramBuf_125 = (_vramBuf_125 & ~(*cursorMask << leftShift)) |
                               (*cursorImage << leftShift);
                _vga_write_bpp2packed32_to_bpp4planar(&_vramBuf_125, (unsigned short *)vramAddr);
            }

            // Draw right part of cursor if it extends beyond 16 pixels
            if ((short)(aligned_left + 0x20) <= clip_right) {
                if ((cursorPos & 0xF) == 0) {
                    // Cursor is aligned, just skip
                    saveBuffer++;
                } else {
                    // Cursor spans two words
                    _vga_read_bpp4planar_to_bpp2packed32((unsigned short *)(vramAddr + 2), &DAT_000060cc);
                    *saveBuffer = DAT_000060cc;
                    saveBuffer++;
                    DAT_000060cc = (DAT_000060cc & ~(*cursorMask >> (rightShift & 0x1F))) |
                                   (*cursorImage >> (rightShift & 0x1F));
                    _vga_write_bpp2packed32_to_bpp4planar(&DAT_000060cc, (unsigned short *)(vramAddr + 2));
                }
            }

            // Move to next scanline
            vramAddr += rowBytes * 2;
            cursorImage++;
            cursorMask++;
            col++;
        } while (col < ((bottom >> 16) - top));
    }

    // Restore VGA state
    _select_read_segment(saved_read_segment);
    _select_write_segment(saved_read_segment);
    _select_read_plane(saved_read_plane);
    _select_write_plane(saved_read_plane);

    seq_val = inb(VGA_SEQ_INDEX);
    outb(VGA_SEQ_INDEX, (seq_val & 0xF8) | VGA_SEQ_MAP_MASK);
    outb(VGA_SEQ_DATA, saved_seq_reg);
    __xxx_100 += 2;
}

void _VGARemoveCursor(int *displayInfo, int shmem_ptr)
{
    unsigned short cursorPos;
    unsigned int saved_read_segment;
    unsigned int saved_read_plane;
    unsigned char saved_seq_reg;
    unsigned char seq_val;
    unsigned int leftMask, rightMask;
    unsigned int top_bounds, left_bounds;
    int bottom_bounds, right_bounds;
    short left, right, top, bottom;
    int rowBytes;
    unsigned int bankSize;
    unsigned int row;
    int vramAddr;
    unsigned int *saveBuffer;
    int *shmem = (int *)shmem_ptr;

    // Save VGA state
    saved_read_segment = curr_read_segment;
    saved_read_plane = curr_read_plane;
    leftMask = 0;
    rightMask = 0;

    top_bounds = *(unsigned int *)(shmem_ptr + 0x30);
    left_bounds = *(unsigned int *)(shmem_ptr + 0xc);
    bottom_bounds = *(int *)(shmem_ptr + 0x10);

    seq_val = inb(VGA_SEQ_INDEX);
    outb(VGA_SEQ_INDEX, (seq_val & 0xF8) | VGA_SEQ_MAP_MASK);
    __xxx_100++;
    saved_seq_reg = inb(VGA_SEQ_DATA);

    // Extract bounds
    left = (short)left_bounds;
    right = (short)top_bounds;
    rowBytes = displayInfo[0] >> 4;
    bankSize = 0x10000 / rowBytes;
    top = (short)bottom_bounds;
    bottom = (short)*(unsigned int *)(shmem_ptr + 0x34);

    // Calculate segment and VRAM address
    row = ((unsigned int)(top - bottom)) / bankSize;
    vramAddr = ((left - right) >> 4) * 2 + 0xA0000 +
               (((unsigned int)(top - bottom)) % bankSize) * rowBytes * 2;

    _select_write_segment(row);
    _select_read_segment(row);

    cursorPos = *(unsigned short *)(shmem_ptr + 0x20);
    saveBuffer = (unsigned int *)(shmem_ptr + 0x248);

    // Calculate edge masks
    if (right <= left) {
        leftMask = mask_array[(int)*(short *)(shmem_ptr + 0x28) - (int)left];
    }

    bottom = (short)((unsigned int)left_bounds >> 16);
    if (bottom <= (short)((unsigned int)top_bounds >> 16)) {
        rightMask = ~mask_array[0x10 - ((int)bottom - (int)*(short *)(shmem_ptr + 0x2a))];
    }

    row = (int)top - (int)bottom;
    bottom_bounds = bottom_bounds >> 16;

    // Restore cursor scanlines
    if (row < (unsigned int)(bottom_bounds - bottom)) {
        do {
            // Check if we need to switch segments
            if (row % bankSize == 0) {
                _select_write_segment(row / bankSize);
                _select_read_segment(row / bankSize);
            }

            // Restore left part
            if (right <= left) {
                _vga_read_bpp4planar_to_bpp2packed32((unsigned short *)vramAddr, &_vramBuf_129);
                _vramBuf_129 = (leftMask & *saveBuffer) | (~leftMask & _vramBuf_129);
                saveBuffer++;
                _vga_write_bpp2packed32_to_bpp4planar(&_vramBuf_129, (unsigned short *)vramAddr);
            }

            // Restore right part if cursor spans two words
            if (bottom <= (short)((unsigned int)top_bounds >> 16)) {
                if ((cursorPos & 0xF) == 0) {
                    saveBuffer++;
                } else {
                    _vga_read_bpp4planar_to_bpp2packed32((unsigned short *)(vramAddr + 2), &DAT_000060d4);
                    DAT_000060d4 = (rightMask & *saveBuffer) | (~rightMask & DAT_000060d4);
                    saveBuffer++;
                    _vga_write_bpp2packed32_to_bpp4planar(&DAT_000060d4, (unsigned short *)(vramAddr + 2));
                }
            }

            vramAddr += rowBytes * 2;
            row++;
        } while (row < (unsigned int)(bottom_bounds - bottom));
    }

    // Restore VGA state
    _select_read_segment(saved_read_segment);
    _select_write_segment(saved_read_segment);
    _select_read_plane(saved_read_plane);
    _select_write_plane(saved_read_plane);

    seq_val = inb(VGA_SEQ_INDEX);
    outb(VGA_SEQ_INDEX, (seq_val & 0xF8) | VGA_SEQ_MAP_MASK);
    outb(VGA_SEQ_DATA, saved_seq_reg);
    __xxx_100 += 2;
}

/*
 * Utility functions
 */
void *_find_parameter(const char *paramName, const char *searchString)
{
    unsigned int nameLen;
    const char *p;
    char c;

    // Calculate length of paramName (like strlen)
    nameLen = 0xFFFFFFFF;
    p = paramName;
    do {
        if (nameLen == 0) break;
        nameLen--;
        c = *p++;
    } while (c != '\0');
    nameLen = ~nameLen - 1;  // Actual length

    // Search for paramName in searchString
    c = *searchString;
    while (c != '\0') {
        // Compare paramName with current position
        if (strncmp(searchString, paramName, nameLen) == 0) {
            // Found match, skip past parameter name
            searchString += nameLen;

            // Skip whitespace (space and tab)
            while ((c = *searchString) != '\0' && (c == ' ' || c == '\t')) {
                searchString++;
            }

            // Return pointer to value if not at end
            if (c != '\0') {
                return (void *)searchString;
            }
            return NULL;
        }

        // Move to next character
        searchString++;
        c = *searchString;
    }

    return NULL;
}

void _SetET4000Brightness(int level)
{
    unsigned char value;

    // VGA DAC ports
    #define VGA_DAC_WRITE_INDEX  0x3C8
    #define VGA_DAC_DATA         0x3C9

    // Program palette entry 3 (white) with scaled brightness
    outb(VGA_DAC_WRITE_INDEX, 3);
    __xxx_100++;
    value = (unsigned char)((unsigned int)(level * 0x3F) >> 6);
    outb(VGA_DAC_DATA, value);  // Red
    __xxx_100++;
    outb(VGA_DAC_DATA, value);  // Green
    __xxx_100++;
    outb(VGA_DAC_DATA, value);  // Blue
    __xxx_100++;

    // Program palette entry 2 (gray) with 75% brightness
    outb(VGA_DAC_WRITE_INDEX, 2);
    __xxx_100++;
    value = (unsigned char)((unsigned int)(level * 3) >> 2);
    outb(VGA_DAC_DATA, value);  // Red
    __xxx_100++;
    outb(VGA_DAC_DATA, value);  // Green
    __xxx_100++;
    outb(VGA_DAC_DATA, value);  // Blue
    __xxx_100++;

    // Program palette entry 1 (darker gray) with 46.875% brightness
    outb(VGA_DAC_WRITE_INDEX, 1);
    __xxx_100++;
    value = (unsigned char)((unsigned int)(level * 0xF) >> 5);
    outb(VGA_DAC_DATA, value);  // Red
    __xxx_100++;
    outb(VGA_DAC_DATA, value);  // Green
    __xxx_100++;
    outb(VGA_DAC_DATA, value);  // Blue
    __xxx_100++;

    // Program palette entry 0 (black) to pure black
    outb(VGA_DAC_WRITE_INDEX, 0);
    __xxx_100++;
    outb(VGA_DAC_DATA, 0);  // Red
    __xxx_100++;
    outb(VGA_DAC_DATA, 0);  // Green
    __xxx_100++;
    outb(VGA_DAC_DATA, 0);  // Blue
    __xxx_100 += 1;
}

/*
 * x86 Opcode Handler - Default/Unimplemented
 */
void opcode_handler_default(void)
{
    // Default handler for unimplemented opcodes
    // In a real implementation, this should handle or log the unimplemented opcode
    IOLog("EMU486: Unimplemented opcode encountered\n");
}

/*
 * ============================================================================
 * x86 Opcode Handlers - Actual Instruction Implementations
 * ============================================================================
 */

/*
 * opcode_handler_modrm_complex
 * Original: UndefinedFunction_00001ecc @ 0x1ecc
 *
 * Handles complex opcodes that require multiple dispatch stages.
 * Uses both jump table lookup and ModR/M byte dispatch.
 */
void opcode_handler_modrm_complex(void)
{
    extern unsigned int extraout_EDX;
    extern void *DAT_000043b0[];

    // Get jump table entry based on ESI register
    emu486_get_jump_table_entry();

    // Dispatch via ModR/M table 1
    emu486_dispatch_modrm_1();

    // Final dispatch via table at 0x43b0 using EDX
    ((void (*)(void))(DAT_000043b0[extraout_EDX & 0xFFFFFF38]))();
}

/*
 * opcode_handler_or_eb_ib
 * Original: UndefinedFunction_00001ee8 @ 0x1ee8
 *
 * OR Eb, Ib - Logical OR of byte register/memory with immediate byte
 * Sets flags: SF, ZF, PF, CF=0, OF=0
 */
unsigned int opcode_handler_or_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    extern unsigned char *unaff_ESI;
    extern unsigned char *unaff_EDI;
    extern unsigned int *in_stack_00000018;
    unsigned char result;
    unsigned int flags;
    int i;
    unsigned int *reg_ptr;

    // Perform OR operation
    result = *unaff_EDI | imm;
    *unaff_EDI = result;

    // Calculate CPU flags
    // Preserved from input (via in_* parameters - Ghidra notation for register state)
    flags = 0;

    // Sign Flag (SF) - bit 7
    if ((char)result < 0) flags |= 0x80;

    // Zero Flag (ZF) - bit 6
    if (result == 0) flags |= 0x40;

    // Parity Flag (PF) - bit 2 (even parity)
    if ((POPCOUNT(result) & 1) == 0) flags |= 0x04;

    // Carry and Overflow are cleared by OR
    // Other flags preserved from previous state

    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * opcode_handler_adc_eb_ib
 * Original: UndefinedFunction_00001eef @ 0x1eef
 *
 * ADC Eb, Ib - Add with carry byte register/memory with immediate byte
 * Sets flags: SF, ZF, PF, CF, OF, AF
 */
unsigned int opcode_handler_adc_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    extern unsigned char *unaff_ESI;
    extern unsigned char *unaff_EDI;
    extern unsigned int *in_stack_00000018;
    unsigned char oldVal, tempResult, result;
    unsigned int flags;
    unsigned int oldFlags;
    int i;
    unsigned int *reg_ptr;
    unsigned char carry;

    // Get old value and carry flag
    oldFlags = (DAT_00006094 & 0xFF) << 8;
    carry = (oldFlags & 0x100) ? 1 : 0;
    oldVal = *unaff_EDI;

    // Perform ADC operation: dest = dest + src + CF
    tempResult = oldVal + imm;
    result = tempResult + carry;
    *unaff_EDI = result;

    // Calculate CPU flags
    flags = 0;

    // Carry Flag (CF) - bit 0
    if ((oldVal > (0xFF - imm)) || (tempResult > (0xFF - carry))) flags |= 0x01;

    // Parity Flag (PF) - bit 2
    if ((POPCOUNT(result) & 1) == 0) flags |= 0x04;

    // Auxiliary Carry (AF) - bit 4 (preserved from old flags)
    if (oldFlags & 0x1000) flags |= 0x10;

    // Zero Flag (ZF) - bit 6
    if (result == 0) flags |= 0x40;

    // Sign Flag (SF) - bit 7
    if ((char)result < 0) flags |= 0x80;

    // Overflow Flag (OF) - bit 11
    if (SCARRY1(oldVal, imm) != SCARRY1(tempResult, carry)) flags |= 0x800;

    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * opcode_handler_sbb_eb_ib
 * Original: UndefinedFunction_00001efd @ 0x1efd
 *
 * SBB Eb, Ib - Subtract with borrow byte register/memory with immediate byte
 * Sets flags: SF, ZF, PF, CF, OF, AF
 */
unsigned int opcode_handler_sbb_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    extern unsigned char *unaff_ESI;
    extern unsigned char *unaff_EDI;
    extern unsigned int *in_stack_00000018;
    unsigned char oldVal, tempResult, result;
    unsigned int flags;
    unsigned int oldFlags;
    int i;
    unsigned int *reg_ptr;
    unsigned char borrow;

    // Get old value and carry/borrow flag
    oldFlags = (DAT_00006094 & 0xFF) << 8;
    borrow = (oldFlags & 0x100) ? 1 : 0;
    oldVal = *unaff_EDI;

    // Perform SBB operation: dest = dest - src - CF
    tempResult = oldVal - imm;
    result = tempResult - borrow;
    *unaff_EDI = result;

    // Calculate CPU flags
    flags = 0;

    // Carry Flag (CF) - bit 0 (borrow occurred)
    if ((oldVal < imm) || (tempResult < borrow)) flags |= 0x01;

    // Parity Flag (PF) - bit 2
    if ((POPCOUNT(result) & 1) == 0) flags |= 0x04;

    // Auxiliary Carry (AF) - bit 4 (preserved from old flags)
    if (oldFlags & 0x1000) flags |= 0x10;

    // Zero Flag (ZF) - bit 6
    if (result == 0) flags |= 0x40;

    // Sign Flag (SF) - bit 7
    if ((char)result < 0) flags |= 0x80;

    // Overflow Flag (OF) - bit 11
    if (SBORROW1(oldVal, imm) != SBORROW1(tempResult, borrow)) flags |= 0x800;

    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * AND Eb, Ib @ 0x1f0b
 * Logical AND immediate byte with byte operand
 * Clears OF and CF, sets SF/ZF/PF
 */
unsigned int opcode_handler_and_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    unsigned int result;
    unsigned int flags;
    unsigned int *reg_ptr;
    unsigned int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    // Perform AND operation
    result = *unaff_EDI & imm;
    *unaff_EDI = (unsigned char)result;

    // Set flags: SF, ZF, PF (CF and OF are cleared)
    flags = 0;
    if ((char)result < 0) {
        flags |= 0x80;  // SF - Sign Flag
    }
    if ((unsigned char)result == 0) {
        flags |= 0x40;  // ZF - Zero Flag
    }
    if ((POPCOUNT(result) & 1) == 0) {
        flags |= 0x04;  // PF - Parity Flag
    }
    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x813;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * SUB Eb, Ib @ 0x1f12
 * Subtract immediate byte from byte operand
 * Sets all arithmetic flags
 */
unsigned int opcode_handler_sub_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    unsigned char oldVal;
    unsigned int result;
    unsigned int flags;
    unsigned int *reg_ptr;
    unsigned int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    oldVal = *unaff_EDI;
    result = oldVal - imm;
    *unaff_EDI = (unsigned char)result;

    // Calculate all arithmetic flags
    flags = 0;

    // CF - Carry Flag (borrow occurred)
    if (imm > oldVal) {
        flags |= 0x01;
    }

    // PF - Parity Flag
    if ((POPCOUNT(result) & 1) == 0) {
        flags |= 0x04;
    }

    // AF - Auxiliary Carry Flag (half-borrow)
    if ((imm & 0x0F) > (oldVal & 0x0F)) {
        flags |= 0x10;
    }

    // ZF - Zero Flag
    if ((unsigned char)result == 0) {
        flags |= 0x40;
    }

    // SF - Sign Flag
    if ((char)result < 0) {
        flags |= 0x80;
    }

    // OF - Overflow Flag (signed overflow)
    if (SBORROW1(oldVal, imm)) {
        flags |= 0x800;
    }

    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x81a;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * XOR Eb, Ib @ 0x1f19
 * Logical XOR immediate byte with byte operand
 * Clears OF and CF, sets SF/ZF/PF
 */
unsigned int opcode_handler_xor_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    unsigned int result;
    unsigned int flags;
    unsigned int *reg_ptr;
    unsigned int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    // Perform XOR operation
    result = *unaff_EDI ^ imm;
    *unaff_EDI = (unsigned char)result;

    // Set flags: SF, ZF, PF (CF and OF are cleared)
    flags = 0;
    if ((char)result < 0) {
        flags |= 0x80;  // SF - Sign Flag
    }
    if ((unsigned char)result == 0) {
        flags |= 0x40;  // ZF - Zero Flag
    }
    if ((POPCOUNT(result) & 1) == 0) {
        flags |= 0x04;  // PF - Parity Flag
    }
    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x821;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * CMP Eb, Ib @ 0x1f20
 * Compare immediate byte with byte operand (subtract without storing)
 * Sets all arithmetic flags but doesn't modify the destination
 */
unsigned int opcode_handler_cmp_eb_ib(unsigned int param_1, unsigned int param_2, unsigned char imm)
{
    unsigned char oldVal;
    unsigned int result;
    unsigned int flags;
    unsigned int *reg_ptr;
    unsigned int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    oldVal = *unaff_EDI;
    result = oldVal - imm;
    // NOTE: CMP does not store the result, only sets flags

    // Calculate all arithmetic flags
    flags = 0;

    // CF - Carry Flag (borrow would occur)
    if (imm > oldVal) {
        flags |= 0x01;
    }

    // PF - Parity Flag
    if ((POPCOUNT(result) & 1) == 0) {
        flags |= 0x04;
    }

    // AF - Auxiliary Carry Flag (half-borrow)
    if ((imm & 0x0F) > (oldVal & 0x0F)) {
        flags |= 0x10;
    }

    // ZF - Zero Flag
    if ((unsigned char)result == 0) {
        flags |= 0x40;
    }

    // SF - Sign Flag
    if ((char)result < 0) {
        flags |= 0x80;
    }

    // OF - Overflow Flag (signed overflow)
    if (SBORROW1(oldVal, imm)) {
        flags |= 0x800;
    }

    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x828;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * Complex ModR/M dispatch variant 2 @ 0x1f27
 * Handles complex addressing modes using second dispatch table
 */
void opcode_handler_modrm_complex_2(void)
{
    int *regPtr;

    DAT_000060b4 = 0x82f;

    // Get register pointer based on ModR/M byte
    regPtr = (int *)emu486_get_gp_register_ptr();

    // Dispatch using second ModR/M table
    emu486_dispatch_modrm_2();

    return;
}

/*
 * ADC Ev, Iv @ 0x1f56
 * Add with carry immediate word/dword to word/dword operand
 * Operand size determined by BL register (4=dword, 2=word)
 */
unsigned int opcode_handler_adc_ev_iv(unsigned int param_1, unsigned int param_2, unsigned int imm)
{
    unsigned short uVar1;
    unsigned int uVar2;
    unsigned short uVar3;
    unsigned int uVar4;
    unsigned char bVar5;
    unsigned short uVar7;
    unsigned int *reg_ptr;
    int i;
    unsigned int carry;
    unsigned int flags;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;
    bool bVar10, bVar11, bVar12, bVar13;

    if (unaff_BL == '\x04') {
        // 32-bit (dword) operation
        uVar2 = (unsigned int)((DAT_00006094 & 1) != 0);  // Get carry flag
        uVar4 = *unaff_EDI + imm;
        bVar10 = CARRY4(*unaff_EDI, imm) || CARRY4(uVar4, uVar2);
        bVar13 = SCARRY4(*unaff_EDI, imm) != SCARRY4(uVar4, uVar2);
        *unaff_EDI = uVar4 + uVar2;
        bVar12 = (int)*unaff_EDI < 0;
        bVar11 = *unaff_EDI == 0;
        bVar5 = POPCOUNT(*unaff_EDI & 0xff);
    } else {
        // 16-bit (word) operation
        uVar1 = (unsigned short)((DAT_00006094 & 1) != 0);  // Get carry flag
        uVar7 = (unsigned short)imm;
        uVar3 = (unsigned short)*unaff_EDI + uVar7;
        bVar10 = CARRY2((unsigned short)*unaff_EDI, uVar7) || CARRY2(uVar3, uVar1);
        bVar13 = SCARRY2((unsigned short)*unaff_EDI, uVar7) != SCARRY2(uVar3, uVar1);
        *(unsigned short *)unaff_EDI = uVar3 + uVar1;
        bVar12 = (short)(unsigned short)*unaff_EDI < 0;
        bVar11 = (unsigned short)*unaff_EDI == 0;
        bVar5 = POPCOUNT((unsigned short)*unaff_EDI & 0xff);
    }

    // Set all flags
    flags = (unsigned int)(unaff_NT & 1) * 0x4000 | (unsigned int)bVar13 * 0x800 |
            (unsigned int)(unaff_IF & 1) * 0x200 | (unsigned int)(unaff_TF & 1) * 0x100 |
            (unsigned int)bVar12 * 0x80 | (unsigned int)bVar11 * 0x40 |
            (unsigned int)((DAT_00006094 & 0x10) != 0) * 0x10 | (unsigned int)((bVar5 & 1) == 0) * 4 |
            (unsigned int)bVar10 | (unsigned int)(unaff_ID & 1) * 0x200000 |
            (unsigned int)(unaff_VIP & 1) * 0x100000 | (unsigned int)(unaff_VIF & 1) * 0x80000 |
            (unsigned int)(unaff_AC & 1) * 0x40000;
    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * SBB Ev, Iv @ 0x1f72
 * Subtract with borrow immediate word/dword from word/dword operand
 * Operand size determined by BL register (4=dword, 2=word)
 */
unsigned int opcode_handler_sbb_ev_iv(unsigned int param_1, unsigned int param_2, unsigned int imm)
{
    unsigned short uVar1;
    unsigned int uVar2;
    unsigned short uVar3;
    unsigned int uVar4;
    unsigned char bVar5;
    unsigned short uVar7;
    unsigned int *reg_ptr;
    int i;
    unsigned int flags;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;
    bool bVar10, bVar11, bVar12, bVar13;

    if (unaff_BL == '\x04') {
        // 32-bit (dword) operation
        uVar2 = (unsigned int)((DAT_00006094 & 1) != 0);  // Get carry flag
        uVar4 = *unaff_EDI - imm;
        bVar10 = *unaff_EDI < imm || uVar4 < uVar2;
        bVar13 = SBORROW4(*unaff_EDI, imm) != SBORROW4(uVar4, uVar2);
        *unaff_EDI = uVar4 - uVar2;
        bVar12 = (int)*unaff_EDI < 0;
        bVar11 = *unaff_EDI == 0;
        bVar5 = POPCOUNT(*unaff_EDI & 0xff);
    } else {
        // 16-bit (word) operation
        uVar1 = (unsigned short)((DAT_00006094 & 1) != 0);  // Get carry flag
        uVar7 = (unsigned short)imm;
        uVar3 = (unsigned short)*unaff_EDI - uVar7;
        bVar10 = (unsigned short)*unaff_EDI < uVar7 || uVar3 < uVar1;
        bVar13 = SBORROW2((unsigned short)*unaff_EDI, uVar7) != SBORROW2(uVar3, uVar1);
        *(unsigned short *)unaff_EDI = uVar3 - uVar1;
        bVar12 = (short)(unsigned short)*unaff_EDI < 0;
        bVar11 = (unsigned short)*unaff_EDI == 0;
        bVar5 = POPCOUNT((unsigned short)*unaff_EDI & 0xff);
    }

    // Set all flags
    flags = (unsigned int)(unaff_NT & 1) * 0x4000 | (unsigned int)bVar13 * 0x800 |
            (unsigned int)(unaff_IF & 1) * 0x200 | (unsigned int)(unaff_TF & 1) * 0x100 |
            (unsigned int)bVar12 * 0x80 | (unsigned int)bVar11 * 0x40 |
            (unsigned int)((DAT_00006094 & 0x10) != 0) * 0x10 | (unsigned int)((bVar5 & 1) == 0) * 4 |
            (unsigned int)bVar10 | (unsigned int)(unaff_ID & 1) * 0x200000 |
            (unsigned int)(unaff_VIP & 1) * 0x100000 | (unsigned int)(unaff_VIF & 1) * 0x80000 |
            (unsigned int)(unaff_AC & 1) * 0x40000;
    DAT_00006094 = flags;

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * Complex ModR/M dispatch variant 3 @ 0x1fc2
 * Uses jump table lookup and ModR/M dispatch
 */
void opcode_handler_modrm_complex_3(void)
{
    extern unsigned int extraout_EDX;
    extern void *DAT_000043b0[];

    // Get jump table entry based on ESI register
    emu486_get_jump_table_entry();

    // Dispatch via ModR/M table 1
    emu486_dispatch_modrm_1();

    // Final dispatch via table at 0x43b0 using EDX
    ((void (*)(void))(DAT_000043b0[extraout_EDX & 0xFFFFFF38]))();
}

/*
 * Complex ModR/M dispatch variant 4 @ 0x1fd5
 * Uses register pointer and ModR/M dispatch with new table
 */
void opcode_handler_modrm_complex_4(void)
{
    extern unsigned int extraout_EDX;
    extern void *PTR_DAT_000043b4[];

    // Get register pointer based on ModR/M byte
    emu486_get_gp_register_ptr();

    // Dispatch using second ModR/M table
    emu486_dispatch_modrm_2();

    // Final dispatch via table at 0x43b4 using EDX
    ((void (*)(void))(PTR_DAT_000043b4[extraout_EDX & 0xFFFFFF38]))();
}

/*
 * Simple dispatcher @ 0x1fe8
 * Direct dispatch using DAT_000043b0 table
 */
void opcode_handler_dispatch_simple(unsigned int param_1, unsigned int param_2)
{
    extern void *DAT_000043b0[];

    // Dispatch via table at 0x43b0 using param_2
    ((void (*)(void))(DAT_000043b0[param_2 & 0xFFFFFF38]))();
}

/*
 * PUSH CS @ 0x2003
 * Push code segment register onto stack
 */
unsigned int opcode_handler_push_cs(void)
{
    unsigned int segValue;
    unsigned int *reg_ptr;
    int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    // Calculate segment value to push (CS relative to base)
    segValue = (DAT_00006098 - (int)DAT_00006060) >> 4;

    if (unaff_BL == '\x04') {
        // 32-bit operation - push dword
        DAT_00006080 = DAT_00006080 + -4;
        *(unsigned int *)(DAT_00006080 + DAT_000060a0) = segValue;
    } else {
        // 16-bit operation - push word
        DAT_00006080 = DAT_00006080 + -2;
        *(short *)(DAT_00006080 + DAT_000060a0) = (short)segValue;
    }

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * POP r32/r16 @ 0x21be
 * Pop word/dword from stack into general purpose register
 * Register selection via param_2 & 0xffffff07
 */
unsigned int opcode_handler_pop_reg(unsigned int param_1, unsigned int param_2)
{
    unsigned int *reg_ptr;
    int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;
    unsigned int regIndex;

    // Select register (0-7 for EAX-EDI)
    regIndex = param_2 & 0xffffff07;

    if (unaff_BL == '\x04') {
        // 32-bit operation - pop dword
        DAT_00006080 = DAT_00006080 + 4;
        (&DAT_00006070)[regIndex] = *(unsigned int *)(DAT_00006080 + DAT_000060a0 + -4);
    } else {
        // 16-bit operation - pop word (preserve high 16 bits)
        DAT_00006080 = DAT_00006080 + 2;
        *(unsigned short *)(&DAT_00006070 + regIndex) =
            *(unsigned short *)(DAT_00006080 + DAT_000060a0 + -2);
    }

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * PUSHA/PUSHAD @ 0x220d
 * Push all general purpose registers onto stack
 * Order: EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX
 */
unsigned int opcode_handler_pusha(void)
{
    unsigned int savedESP;
    unsigned int *reg_ptr;
    int i;
    unsigned int *stackPtr;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    savedESP = DAT_00006080;  // Save ESP value before modification

    if (unaff_BL == '\x04') {
        // PUSHAD - push all 32-bit registers (8 dwords = 32 bytes)
        DAT_00006080 = DAT_00006080 + -0x20;
        stackPtr = (unsigned int *)(DAT_00006080 + DAT_000060a0);

        stackPtr[0] = DAT_0000608c;  // EDI
        stackPtr[1] = DAT_00006088;  // ESI
        stackPtr[2] = DAT_00006084;  // EBP
        stackPtr[3] = savedESP;      // ESP (original value)
        stackPtr[4] = DAT_0000607c;  // EBX
        stackPtr[5] = DAT_00006078;  // EDX
        stackPtr[6] = DAT_00006074;  // ECX
        stackPtr[7] = DAT_00006070;  // EAX
    } else {
        // PUSHA - push all 16-bit registers (8 words = 16 bytes)
        DAT_00006080 = DAT_00006080 + -0x10;
        stackPtr = (unsigned int *)(DAT_00006080 + DAT_000060a0);

        stackPtr[0] = DAT_0000608c;  // DI
        *(short *)((int)stackPtr + 2) = (short)DAT_00006088;  // SI
        stackPtr[1] = DAT_00006084;  // BP
        *(short *)((int)stackPtr + 6) = (short)savedESP;  // SP
        stackPtr[2] = DAT_0000607c;  // BX
        *(short *)((int)stackPtr + 10) = (short)DAT_00006078;  // DX
        stackPtr[3] = DAT_00006074;  // CX
        *(short *)((int)stackPtr + 14) = (short)DAT_00006070;  // AX
    }

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * POPA/POPAD @ 0x22c2
 * Pop all general purpose registers from stack
 * Order: EDI, ESI, EBP, (skip ESP), EBX, EDX, ECX, EAX
 * ESP value from stack is discarded
 */
unsigned int opcode_handler_popa(void)
{
    unsigned int *reg_ptr;
    int i;
    int stackAddr;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    if (unaff_BL == '\x04') {
        // POPAD - pop all 32-bit registers (8 dwords = 32 bytes)
        DAT_00006080 = DAT_00006080 + 0x20;
        stackAddr = DAT_00006080 + DAT_000060a0;

        DAT_0000608c = *(unsigned int *)(stackAddr + -0x20);  // EDI
        DAT_00006088 = *(unsigned int *)(stackAddr + -0x1c);  // ESI
        DAT_00006084 = *(unsigned int *)(stackAddr + -0x18);  // EBP
        // Skip ESP at (stackAddr + -0x14)
        DAT_0000607c = *(unsigned int *)(stackAddr + -0x10);  // EBX
        DAT_00006078 = *(unsigned int *)(stackAddr + -0xc);   // EDX
        DAT_00006074 = *(unsigned int *)(stackAddr + -8);     // ECX
        DAT_00006070 = *(unsigned int *)(stackAddr + -4);     // EAX
    } else {
        // POPA - pop all 16-bit registers (8 words = 16 bytes)
        // CONCAT22 preserves high 16 bits while loading low 16 bits
        DAT_00006080 = DAT_00006080 + 0x10;
        stackAddr = DAT_00006080 + DAT_000060a0;

        // Extract high 16 bits: reg >> 16, then CONCAT with new low 16 bits
        DAT_0000608c = CONCAT22(DAT_0000608c >> 16,
                                (short)*(unsigned int *)(stackAddr + -0x10));  // DI
        DAT_00006088 = CONCAT22(DAT_00006088 >> 16,
                                (short)((unsigned int)*(unsigned int *)(stackAddr + -0x10) >> 0x10));  // SI
        DAT_00006084 = CONCAT22(DAT_00006084 >> 16,
                                (short)*(unsigned int *)(stackAddr + -0xc));  // BP
        // Skip SP at (stackAddr + -0xa)
        DAT_0000607c = CONCAT22(DAT_0000607c >> 16,
                                (short)*(unsigned int *)(stackAddr + -8));  // BX
        DAT_00006078 = CONCAT22(DAT_00006078 >> 16,
                                (short)((unsigned int)*(unsigned int *)(stackAddr + -8) >> 0x10));  // DX
        DAT_00006074 = CONCAT22(DAT_00006074 >> 16,
                                (short)*(unsigned int *)(stackAddr + -4));  // CX
        DAT_00006070 = CONCAT22(DAT_00006070 >> 16,
                                (short)((unsigned int)*(unsigned int *)(stackAddr + -4) >> 0x10));  // AX
    }

    // Continue execution if not at end
    if (DAT_00006060 != (unsigned int)unaff_ESI) {
        DAT_000060b4 = 0x80c;
        return ((unsigned int (*)(void))(PTR_LAB_00003d90[*unaff_ESI]))();
    }

    // Exit emulation - save state
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    return 0;
}

/*
 * Emulation Exit Handler @ 0x2372
 * Unconditionally exits emulation with error code 0x1000000
 * This appears to be an error handler or special exit condition
 */
unsigned int opcode_handler_exit_error(void)
{
    unsigned int *reg_ptr;
    int i;
    unsigned int *in_stack_00000018 = (unsigned int *)unaff_EBP;

    // Save state without checking continuation condition
    // This is a forced exit, likely due to an error or special condition
    DAT_00006090 = (int)unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *in_stack_00000018++ = *reg_ptr++;
    }

    // Return error code (bit 24 set indicates error condition)
    return 0x1000000;
}

/*
 * Additional jump tables for EMU486 instruction dispatch
 * These are used by the indirect jump functions (FUN_000038bc, FUN_000038d4, etc.)
 */

// Jump table at 0x4190 - Used by FUN_000038bc
void *PTR_LAB_00004190[256] = {
    [0x00 ... 0xFF] = opcode_handler_default
};

// Jump table at 0x4290 - Used by FUN_000038d4
void *PTR_LAB_00004290[256] = {
    [0x00 ... 0xFF] = opcode_handler_default
};

// Jump table at 0x4390 - Used by FUN_00003893
void *PTR_DAT_00004390[256] = {
    [0x00 ... 0xFF] = opcode_handler_default
};

// Jump table at 0x43b0 - Used by opcode_handler_modrm_complex
void *DAT_000043b0[256] = {
    [0x00 ... 0xFF] = opcode_handler_default
};

// Jump table at 0x43b4 - Used by opcode_handler_modrm_complex_4
void *PTR_DAT_000043b4[256] = {
    [0x00 ... 0xFF] = opcode_handler_default
};

// Jump table at 0x4640 - Used by FUN_00003d18
void *PTR_LAB_00004640[256] = {
    [0x00 ... 0xFF] = opcode_handler_default
};

/*
 * ============================================================================
 * EMU486 Helper Functions - Infrastructure for CPU Emulation
 * ============================================================================
 * These functions support the instruction dispatch and execution mechanism.
 * They are NOT opcode handlers themselves, but utilities used by handlers.
 * All helpers are static inline for performance and to avoid namespace pollution.
 */

/*
 * emu486_get_jump_table_entry
 * Original: FUN_00003893 @ 0x3893
 *
 * Returns a jump table entry based on bits 3-5 of the ESI register.
 * Used for register-based instruction dispatch.
 */
static inline void emu486_get_jump_table_entry(void)
{
    extern unsigned char *unaff_ESI;

    // Return value from table: *(PTR_DAT_00004390 + ((ESI & 0x38) >> 1))
    // This is called by opcode handlers to get register-specific dispatch entries
    IOLog("EMU486: Jump table lookup from ESI\n");
}

/*
 * emu486_get_gp_register_ptr
 * Original: FUN_000038a1 @ 0x38a1
 *
 * Returns pointer to general-purpose register (EAX-EDI) based on ESI bits 3-5.
 * This allows dynamic register selection in instruction handlers.
 */
static inline int emu486_get_gp_register_ptr(void)
{
    extern unsigned char *unaff_ESI;

    // ESI bits 3-5 select which register: 000=EAX, 001=ECX, 010=EDX, 011=EBX,
    //                                     100=ESP, 101=EBP, 110=ESI, 111=EDI
    return (int)&DAT_00006070 + ((*unaff_ESI & 0x38) >> 1);
}

/*
 * emu486_get_segment_register_ptr
 * Original: FUN_000038ae @ 0x38ae
 *
 * Returns pointer to segment register (CS, DS, ES, SS, FS, GS) based on ESI bits 3-5.
 */
static inline int emu486_get_segment_register_ptr(void)
{
    extern unsigned char *unaff_ESI;

    // ESI bits 3-5 select which segment: 000=ES, 001=CS, 010=SS, 011=DS,
    //                                    100=FS, 101=GS
    return (int)&DAT_00006098 + ((*unaff_ESI & 0x38) >> 1);
}

/*
 * emu486_dispatch_modrm_1
 * Original: FUN_000038bc @ 0x38bc
 *
 * Handles ModR/M byte dispatch for instructions with complex addressing modes.
 * Swaps nibbles of the opcode byte to create an index into PTR_LAB_00004190.
 * This table handles the first class of ModR/M instructions.
 */
static inline void emu486_dispatch_modrm_1(void)
{
    extern unsigned char *unaff_ESI;
    unsigned int index;

    // Parse opcode: swap nibbles (0xAB becomes 0xBA), mask to 0x7C, add flags
    index = ((*unaff_ESI << 4) | (*unaff_ESI >> 4)) & 0x7C;
    index |= DAT_000060b7;

    // Dispatch to appropriate ModR/M handler
    ((void (*)(void))(PTR_LAB_00004190[index / sizeof(void *)]))();
}

/*
 * emu486_dispatch_modrm_2
 * Original: FUN_000038d4 @ 0x38d4
 *
 * Handles ModR/M byte dispatch for the second class of addressing modes.
 * Uses PTR_LAB_00004290 table with same indexing scheme as modrm_1.
 */
static inline void emu486_dispatch_modrm_2(void)
{
    extern unsigned char *unaff_ESI;
    unsigned int index;

    // Parse opcode: swap nibbles, mask, and add flags
    index = ((*unaff_ESI << 4) | (*unaff_ESI >> 4)) & 0x7C;
    index |= DAT_000060b7;

    // Dispatch to appropriate ModR/M handler
    ((void (*)(void))(PTR_LAB_00004290[index / sizeof(void *)]))();
}

/*
 * emu486_validate_address_bx_si
 * Original: UndefinedFunction_000038ec @ 0x38ec
 *
 * Validates memory access using BX+SI addressing mode.
 * Calculates effective address, adds segment base, and validates bounds.
 *
 * Returns:
 *   - param_1 if access is valid
 *   - 0x4000000 if address >= 0x10000 (out of 16-bit range)
 *   - 0x2000000 | offset if page table validation fails
 */
static inline unsigned int emu486_validate_address_bx_si(unsigned int param_1,
                                                         unsigned int param_2,
                                                         unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Calculate effective address: (BX + SI) & 0xFFFF
    effectiveAddr = (DAT_0000607c + DAT_00006088) & 0xFFFF;

    // Special case: if DAT_000060b4 == 0x18, return success immediately
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    // Check if address is within 16-bit range
    if (effectiveAddr < 0x10000) {
        // Get segment base from register array
        // CONCAT31 combines upper 24 bits of param_3 with low 8 bits from DAT_000060b4
        // This selects which segment register to use
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));

        // Calculate physical address
        physicalAddr = effectiveAddr + segmentBase;

        // Calculate offset from base
        offset = physicalAddr - DAT_00006060;

        // Validate: must be < 1MB and page must be valid
        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            // Valid access
            return param_1;
        }

        // Page fault - return error with offset
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        // Address out of 16-bit range
        offset = 0x4000000;
    }

    // Exit emulation with error - save state
    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }

    return offset;
}

/*
 * emu486_validate_address_bx_di
 * Original: UndefinedFunction_00003954 @ 0x3954
 *
 * Validates memory access using BX+DI addressing mode.
 */
static inline unsigned int emu486_validate_address_bx_di(unsigned int param_1,
                                                         unsigned int param_2,
                                                         unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Calculate effective address: (BX + DI) & 0xFFFF
    effectiveAddr = (DAT_0000607c + DAT_0000608c) & 0xFFFF;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_bp_si
 * Original: UndefinedFunction_00003968 @ 0x3968
 *
 * Validates memory access using BP+SI addressing mode.
 */
static inline unsigned int emu486_validate_address_bp_si(unsigned int param_1,
                                                         unsigned int param_2,
                                                         unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Calculate effective address: (BP + SI) & 0xFFFF
    effectiveAddr = (DAT_00006084 + DAT_00006088) & 0xFFFF;

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 + (param_3 & 0xFFFFFF00));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_bp_di
 * Original: UndefinedFunction_0000397c @ 0x397c
 *
 * Validates memory access using BP+DI addressing mode.
 */
static inline unsigned int emu486_validate_address_bp_di(unsigned int param_1,
                                                         unsigned int param_2,
                                                         unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Calculate effective address: (BP + DI) & 0xFFFF
    effectiveAddr = (DAT_00006084 + DAT_0000608c) & 0xFFFF;

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 + (param_3 & 0xFFFFFF00));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_si
 * Original: UndefinedFunction_00003990 @ 0x3990
 *
 * Validates memory access using SI-only addressing mode.
 */
static inline unsigned int emu486_validate_address_si(unsigned int param_1,
                                                      unsigned int param_2,
                                                      unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    // Get SI register value & 0xFFFF
    effectiveAddr = DAT_00006088 & 0xFFFF;

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_di
 * Original: UndefinedFunction_0000399c @ 0x399c
 *
 * Validates memory access using DI-only addressing mode.
 */
static inline unsigned int emu486_validate_address_di(unsigned int param_1,
                                                      unsigned int param_2,
                                                      unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    // Get DI register value & 0xFFFF
    effectiveAddr = DAT_0000608c & 0xFFFF;

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_direct
 * Original: UndefinedFunction_000039a8 @ 0x39a8
 *
 * Validates memory access using direct addressing (displacement from instruction).
 * The displacement is read from the instruction stream (pointed to by unaff_ESI).
 * Note: IP is adjusted by +2 to skip the 16-bit displacement.
 */
static inline unsigned int emu486_validate_address_direct(unsigned int param_1,
                                                          unsigned int param_2,
                                                          unsigned int param_3)
{
    extern unsigned int *unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    // Read displacement from instruction stream (16-bit)
    effectiveAddr = (*unaff_ESI) & 0xFFFF;

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    // Save IP with +2 adjustment (skip 16-bit displacement in instruction)
    DAT_00006090 = (int)unaff_ESI + (2 - DAT_0000609c);
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_bx
 * Original: UndefinedFunction_000039b4 @ 0x39b4
 *
 * Validates memory access using BX-only addressing mode.
 */
static inline unsigned int emu486_validate_address_bx(unsigned int param_1,
                                                      unsigned int param_2,
                                                      unsigned int param_3)
{
    extern int unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    // Get BX register value & 0xFFFF
    effectiveAddr = DAT_0000607c & 0xFFFF;

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    DAT_00006090 = unaff_ESI - DAT_0000609c;
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_bx_si_disp8
 * Original: UndefinedFunction_000039bf @ 0x39bf
 *
 * Validates memory access using [BX+SI+disp8] addressing mode.
 * The 8-bit displacement is read from instruction stream.
 */
static inline unsigned int emu486_validate_address_bx_si_disp8(unsigned int param_1,
                                                               unsigned int param_2,
                                                               unsigned int param_3)
{
    extern char *unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Calculate effective address: BX + SI + disp8 (sign-extended)
    effectiveAddr = (*unaff_ESI + DAT_0000607c + DAT_00006088) & 0xFFFF;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    // Save IP with +1 adjustment (skip 8-bit displacement in instruction)
    DAT_00006090 = (int)unaff_ESI + (1 - DAT_0000609c);
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_address_bx_di_disp8
 * Original: UndefinedFunction_000039d4 @ 0x39d4
 *
 * Validates memory access using [BX+DI+disp8] addressing mode.
 * The 8-bit displacement is read from instruction stream.
 */
static inline unsigned int emu486_validate_address_bx_di_disp8(unsigned int param_1,
                                                               unsigned int param_2,
                                                               unsigned int param_3)
{
    extern char *unaff_ESI;
    unsigned int effectiveAddr;
    unsigned int physicalAddr;
    unsigned int offset;
    unsigned int segmentBase;
    unsigned int *reg_ptr;
    unsigned int *out_regs;
    int i;

    // Calculate effective address: BX + DI + disp8 (sign-extended)
    effectiveAddr = (*unaff_ESI + DAT_0000607c + DAT_0000608c) & 0xFFFF;

    // Special case check
    if (DAT_000060b4 == 0x18) {
        return param_1;
    }

    if (effectiveAddr < 0x10000) {
        segmentBase = *(int *)((int)&DAT_00006098 +
                               CONCAT31((int)(((unsigned int)param_3 >> 8) & 0xFFFFFF),
                                        DAT_000060b4));
        physicalAddr = effectiveAddr + segmentBase;
        offset = physicalAddr - DAT_00006060;

        if ((offset < 0x100000) &&
            (*(char *)((offset >> 0xC) + DAT_00006064) != '\0')) {
            return param_1;
        }
        offset = (physicalAddr - DAT_00006060) | 0x2000000;
    } else {
        offset = 0x4000000;
    }

    // Save IP with +1 adjustment (skip 8-bit displacement in instruction)
    DAT_00006090 = (int)unaff_ESI + (1 - DAT_0000609c);
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    out_regs = (unsigned int *)unaff_EBP;
    reg_ptr = &DAT_00006070;
    for (i = 0x10; i != 0; i--) {
        *out_regs++ = *reg_ptr++;
    }
    return offset;
}

/*
 * emu486_validate_memory_access
 * Original: FUN_00003917 @ 0x3917
 *
 * Validates that a memory access is within allowed emulated memory bounds.
 * Checks both range (< 1MB) and page table validity.
 * Returns 0x2000000 | offset on page fault, or param_1 to continue.
 */
static inline unsigned int emu486_validate_memory_access(unsigned int param_1)
{
    extern int unaff_ESI;
    extern int unaff_EDI;
    unsigned int offset;
    int i;
    unsigned int *reg_ptr;
    unsigned int *out_regs;

    // Check if address is in valid range and page table entry is valid
    offset = unaff_EDI - DAT_00006060;
    if ((offset < 0x100000) &&
        (*(char *)((offset >> 12) + DAT_00006064) != '\0')) {
        // Valid memory access - continue execution
        return param_1;
    }

    // INVALID MEMORY ACCESS - Trigger page fault
    // Save instruction pointer
    DAT_00006090 = unaff_ESI - DAT_0000609c;

    // Convert segment registers back to segment:offset format
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    // Copy registers to output
    reg_ptr = &DAT_00006070;
    out_regs = (unsigned int *)0x1c;  // Stack offset
    for (i = 0; i < 0x10; i++) {
        *out_regs = *reg_ptr;
        reg_ptr++;
        out_regs++;
    }

    // Return page fault error code
    return offset | 0x2000000;
}

/*
 * emu486_dispatch_param
 * Original: FUN_00003d18 @ 0x3d18
 *
 * Parameter-based dispatch using PTR_LAB_00004640 table.
 * Masks parameter with 0xFFFFFF0F and uses as index.
 */
static inline void emu486_dispatch_param(unsigned int param_1, unsigned int param_2)
{
    // Mask parameter and dispatch
    ((void (*)(void))(PTR_LAB_00004640[param_2 & 0xFFFFFF0F]))();
}

/*
 * emu486_check_io_permission
 * Original: FUN_00003d69 @ 0x3d69
 *
 * Checks I/O port access permissions using bitmap at DAT_00006068.
 * Returns param_1 if allowed, or 0x3000000 | port_number on I/O fault.
 */
static inline unsigned int emu486_check_io_permission(unsigned int param_1, unsigned int param_2)
{
    extern int unaff_ESI;
    unsigned int bitOffset;
    unsigned int wordOffset;
    unsigned int *permissionTable;
    int i;
    unsigned int *reg_ptr;
    unsigned int *out_regs;

    // Calculate bit position in I/O permission bitmap
    // Port number is in lower 16 bits of param_2
    wordOffset = ((param_2 & 0xFFFF) >> 3) & 0xFFFFFFFC;
    bitOffset = param_2 & 0x1F;

    // Get permission table pointer
    permissionTable = (unsigned int *)(wordOffset + DAT_00006068);

    // Test bit in permission bitmap (1 = allowed, 0 = denied)
    if (((*permissionTable >> bitOffset) & 1) != 0) {
        // Port access allowed - continue execution
        return param_1;
    }

    // I/O PERMISSION DENIED - Trigger I/O fault
    // Save instruction pointer
    DAT_00006090 = unaff_ESI - DAT_0000609c;

    // Convert segment registers back to segment:offset format
    DAT_000060a4 = (DAT_000060a4 - DAT_00006060) >> 4;
    DAT_00006098 = (DAT_00006098 - DAT_00006060) >> 4;
    DAT_0000609c = (DAT_0000609c - DAT_00006060) >> 4;
    DAT_000060a0 = (DAT_000060a0 - DAT_00006060) >> 4;
    DAT_000060a8 = (DAT_000060a8 - DAT_00006060) >> 4;
    DAT_000060ac = (DAT_000060ac - DAT_00006060) >> 4;

    // Copy registers to output
    reg_ptr = &DAT_00006070;
    out_regs = (unsigned int *)0x1c;  // Stack offset
    for (i = 0; i < 0x10; i++) {
        *out_regs = *reg_ptr;
        reg_ptr++;
        out_regs++;
    }

    // Return I/O permission fault error code
    return (param_2 & 0xFFFF) | 0x3000000;
}
