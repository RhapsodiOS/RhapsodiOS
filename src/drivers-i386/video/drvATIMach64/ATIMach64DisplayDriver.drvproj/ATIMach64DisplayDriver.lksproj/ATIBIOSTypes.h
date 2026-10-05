#ifndef __ATI_BIOS_TYPES_H__
#define __ATI_BIOS_TYPES_H__

#include <stddef.h>

/* Selector-based BIOS service status returned by the reconstructed driver. */
typedef enum {
    ATIBIOSStatusSuccess = 0,
    ATIBIOSStatusNotInitialized = 1,
    ATIBIOSStatusError = 2,
    ATIBIOSStatusInvalid = 3
} ATIBIOSStatus;

typedef struct { unsigned char bytes[30]; } ATI_CRTCRecord;

enum {
    ATIBIOSRegisterBufferSize = 48,
    ATIBIOSPrivateSize = 36,
    ATIBIOS_OFFSET_EAX = 4,
    ATIBIOS_OFFSET_EBX = 8,
    ATIBIOS_OFFSET_ECX = 12,
    ATIBIOS_OFFSET_EDX = 16,
    ATIBIOS_OFFSET_EDI = 20,
    ATIBIOS_OFFSET_ESI = 24,
    ATIBIOS_OFFSET_EBP = 28,
    ATIBIOS_OFFSET_CODE_SELECTOR = 32,
    ATIBIOS_OFFSET_DATA_SELECTOR = 34,
    ATIBIOS_OFFSET_ES = 36,
    ATIBIOS_OFFSET_FLAGS = 40,
    ATIBIOS_OFFSET_ENTRY_OFFSET = 44
};

enum {
    ATIBIOS_OFFSET_4 = ATIBIOS_OFFSET_EAX,
    ATIBIOS_OFFSET_8 = ATIBIOS_OFFSET_EBX,
    ATIBIOS_OFFSET_12 = ATIBIOS_OFFSET_ECX,
    ATIBIOS_OFFSET_16 = ATIBIOS_OFFSET_EDX,
    ATIBIOS_OFFSET_20 = ATIBIOS_OFFSET_EDI,
    ATIBIOS_OFFSET_24 = ATIBIOS_OFFSET_ESI,
    ATIBIOS_OFFSET_28 = ATIBIOS_OFFSET_EBP,
    ATIBIOS_OFFSET_32 = ATIBIOS_OFFSET_CODE_SELECTOR,
    ATIBIOS_OFFSET_34 = ATIBIOS_OFFSET_DATA_SELECTOR,
    ATIBIOS_OFFSET_36 = ATIBIOS_OFFSET_ES,
    ATIBIOS_OFFSET_40 = ATIBIOS_OFFSET_FLAGS,
    ATIBIOS_OFFSET_44 = ATIBIOS_OFFSET_ENTRY_OFFSET
};

typedef struct {
    unsigned int reserved0;
    unsigned int eax;
    unsigned int ebx;
    unsigned int ecx;
    unsigned int edx;
    unsigned int edi;
    unsigned int esi;
    unsigned int ebp;
    unsigned short codeSelector;
    unsigned short dataSelector;
    unsigned int es;
    unsigned int flags;
    unsigned int entryOffset;
} ATIBIOSRegisters;

typedef struct {
    unsigned short limit;
    unsigned int base;
} ATIBIOSDescriptor;

typedef struct {
    ATIBIOSDescriptor descriptor[4];
    unsigned int stackPointer;
} ATIBIOSPrivate;

/* Assembly references these C symbols with the Mach-O leading underscore. */
extern unsigned int ATI_Bios_Offset;
extern unsigned short ATI_Bios_Selector;
extern unsigned short ATI_Bios_StackOffset;
extern unsigned short ATI_Bios_StackSelector;
extern unsigned short kernDataSel;
extern int ATIbios16(ATIBIOSRegisters *registers);
extern void _ATIbios32(ATIBIOSRegisters *registers);

#define ATI_STATIC_ASSERT(expression, name) typedef char name[(expression) ? 1 : -1]
ATI_STATIC_ASSERT(sizeof(ATIBIOSRegisters) == ATIBIOSRegisterBufferSize, ATIBIOS_register_buffer_is_48);
ATI_STATIC_ASSERT(sizeof(ATIBIOSPrivate) == ATIBIOSPrivateSize, ATIBIOS_private_is_36);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, eax) == ATIBIOS_OFFSET_EAX, ATIBIOS_eax_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, ebx) == ATIBIOS_OFFSET_EBX, ATIBIOS_ebx_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, ecx) == ATIBIOS_OFFSET_ECX, ATIBIOS_ecx_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, edx) == ATIBIOS_OFFSET_EDX, ATIBIOS_edx_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, edi) == ATIBIOS_OFFSET_EDI, ATIBIOS_edi_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, esi) == ATIBIOS_OFFSET_ESI, ATIBIOS_esi_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, ebp) == ATIBIOS_OFFSET_EBP, ATIBIOS_ebp_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, codeSelector) == ATIBIOS_OFFSET_CODE_SELECTOR, ATIBIOS_code_selector_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, dataSelector) == ATIBIOS_OFFSET_DATA_SELECTOR, ATIBIOS_data_selector_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, es) == ATIBIOS_OFFSET_ES, ATIBIOS_es_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, flags) == ATIBIOS_OFFSET_FLAGS, ATIBIOS_flags_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSRegisters, entryOffset) == ATIBIOS_OFFSET_ENTRY_OFFSET, ATIBIOS_entry_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSDescriptor, limit) == 0, ATIBIOS_descriptor_limit_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSDescriptor, base) == 4, ATIBIOS_descriptor_base_offset);
ATI_STATIC_ASSERT(offsetof(ATIBIOSPrivate, stackPointer) == 32, ATIBIOS_private_stack_offset);

#endif
