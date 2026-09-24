/* Minimal IA32 UEFI declarations.  Only what the loader touches. */
#ifndef _BOOTEFI_EFI_H_
#define _BOOTEFI_EFI_H_

typedef unsigned char       UINT8;
typedef unsigned short      UINT16;
typedef unsigned int        UINT32;
typedef unsigned long long  UINT64;
typedef int                 INT32;
typedef UINT32              UINTN;      /* IA32: pointer-sized */
typedef UINT16              CHAR16;
typedef UINTN               EFI_STATUS;
typedef void *              EFI_HANDLE;
typedef UINT64              EFI_PHYSICAL_ADDRESS;
typedef UINT64              EFI_VIRTUAL_ADDRESS;
typedef UINT8               BOOLEAN;

#define EFI_SUCCESS             0

/* A function, not a macro, so the status expression is evaluated once: as a
 * macro, EFI_ERROR(gBS->Call(...)) made every firmware call twice. */
static __inline__ int EFI_ERROR(EFI_STATUS s)
{
    return ((INT32)s) < 0 || s != EFI_SUCCESS;
}

#define EFI_BUFFER_TOO_SMALL    ((EFI_STATUS)0x80000005)

typedef struct { UINT32 d1; UINT16 d2, d3; UINT8 d4[8]; } EFI_GUID;

#define EFI_BLOCK_IO_PROTOCOL_GUID \
  {0x964e5b21,0x6459,0x11d2,{0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b}}

#define EFI_LOADED_IMAGE_PROTOCOL_GUID \
  {0x5b1b31a1,0x9562,0x11d2,{0x8e,0x3f,0x00,0xa0,0xc9,0x69,0x72,0x3b}}
#define EFI_DEVICE_PATH_PROTOCOL_GUID \
  {0x09576e91,0x6d3f,0x11d2,{0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b}}

/* Loaded image: the leading fields only; the loader reads DeviceHandle. */
typedef struct {
    UINT32      Revision;
    EFI_HANDLE  ParentHandle;
    void       *SystemTable;
    EFI_HANDLE  DeviceHandle;
} EFI_LOADED_IMAGE_PROTOCOL;

/* Memory types and allocation */
typedef enum { AllocateAnyPages, AllocateMaxAddress, AllocateAddress }
        EFI_ALLOCATE_TYPE;
typedef enum {
    EfiReservedMemoryType, EfiLoaderCode, EfiLoaderData,
    EfiBootServicesCode, EfiBootServicesData, EfiRuntimeServicesCode,
    EfiRuntimeServicesData, EfiConventionalMemory, EfiUnusableMemory,
    EfiACPIReclaimMemory, EfiACPIMemoryNVS, EfiMemoryMappedIO,
    EfiMemoryMappedIOPortSpace, EfiPalCode, EfiPersistentMemory,
    EfiMaxMemoryType
} EFI_MEMORY_TYPE;

typedef struct {
    UINT32                  Type;
    UINT32                  Pad;
    EFI_PHYSICAL_ADDRESS    PhysicalStart;
    EFI_VIRTUAL_ADDRESS     VirtualStart;
    UINT64                  NumberOfPages;
    UINT64                  Attribute;
} EFI_MEMORY_DESCRIPTOR;

/* Text protocols */
typedef struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
        EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
    void       *Reset;
    EFI_STATUS (*OutputString)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *, CHAR16 *);
    void       *TestString;
    void       *QueryMode;
    void       *SetMode;
    void       *SetAttribute;
    EFI_STATUS (*ClearScreen)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *);
    void       *SetCursorPosition;
    void       *EnableCursor;
    void       *Mode;
};

typedef struct { UINT16 ScanCode; CHAR16 UnicodeChar; } EFI_INPUT_KEY;
typedef struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL
        EFI_SIMPLE_TEXT_INPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL {
    void       *Reset;
    EFI_STATUS (*ReadKeyStroke)(EFI_SIMPLE_TEXT_INPUT_PROTOCOL *,
                                EFI_INPUT_KEY *);
    void       *WaitForKey;
};

/* Block I/O */
typedef struct {
    UINT32   MediaId;
    BOOLEAN  RemovableMedia;
    BOOLEAN  MediaPresent;
    BOOLEAN  LogicalPartition;
    BOOLEAN  ReadOnly;
    BOOLEAN  WriteCaching;
    UINT32   BlockSize;
    UINT32   IoAlign;
    UINT64   LastBlock;
} EFI_BLOCK_IO_MEDIA;

typedef struct _EFI_BLOCK_IO_PROTOCOL EFI_BLOCK_IO_PROTOCOL;
struct _EFI_BLOCK_IO_PROTOCOL {
    UINT64              Revision;
    EFI_BLOCK_IO_MEDIA *Media;
    void               *Reset;
    EFI_STATUS        (*ReadBlocks)(EFI_BLOCK_IO_PROTOCOL *, UINT32 MediaId,
                                    UINT64 Lba, UINTN BufferSize,
                                    void *Buffer);
    void               *WriteBlocks;
    void               *FlushBlocks;
};

/* Boot services.  Unused slots are placeholders that keep the offsets right. */
typedef struct {
    char        Hdr[24];
    void       *RaiseTPL;
    void       *RestoreTPL;
    EFI_STATUS (*AllocatePages)(EFI_ALLOCATE_TYPE, EFI_MEMORY_TYPE,
                                UINTN Pages, EFI_PHYSICAL_ADDRESS *);
    EFI_STATUS (*FreePages)(EFI_PHYSICAL_ADDRESS, UINTN Pages);
    EFI_STATUS (*GetMemoryMap)(UINTN *MapSize, EFI_MEMORY_DESCRIPTOR *Map,
                               UINTN *MapKey, UINTN *DescriptorSize,
                               UINT32 *DescriptorVersion);
    EFI_STATUS (*AllocatePool)(EFI_MEMORY_TYPE, UINTN Size, void **Buffer);
    EFI_STATUS (*FreePool)(void *Buffer);
    void       *CreateEvent;
    void       *SetTimer;
    EFI_STATUS (*WaitForEvent)(UINTN, void **, UINTN *);
    void       *SignalEvent;
    void       *CloseEvent;
    void       *CheckEvent;
    void       *InstallProtocolInterface;
    void       *ReinstallProtocolInterface;
    void       *UninstallProtocolInterface;
    EFI_STATUS (*HandleProtocol)(EFI_HANDLE, EFI_GUID *, void **);
    void       *Reserved;
    void       *RegisterProtocolNotify;
    EFI_STATUS (*LocateHandle)(UINT32 SearchType, EFI_GUID *, void *,
                               UINTN *BufferSize, EFI_HANDLE *);
    void       *LocateDevicePath;
    void       *InstallConfigurationTable;
    void       *LoadImage;
    void       *StartImage;
    void       *Exit;
    void       *UnloadImage;
    EFI_STATUS (*ExitBootServices)(EFI_HANDLE, UINTN MapKey);
    void       *GetNextMonotonicCount;
    EFI_STATUS (*Stall)(UINTN Microseconds);
    EFI_STATUS (*SetWatchdogTimer)(UINTN, UINT64, UINTN, CHAR16 *);
} EFI_BOOT_SERVICES;

#define ByProtocol 2

typedef struct {
    char                             Hdr[24];
    CHAR16                          *FirmwareVendor;
    UINT32                           FirmwareRevision;
    EFI_HANDLE                       ConsoleInHandle;
    EFI_SIMPLE_TEXT_INPUT_PROTOCOL  *ConIn;
    EFI_HANDLE                       ConsoleOutHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOut;
    EFI_HANDLE                       StandardErrorHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *StdErr;
    void                            *RuntimeServices;
    EFI_BOOT_SERVICES               *BootServices;
} EFI_SYSTEM_TABLE;

extern EFI_SYSTEM_TABLE  *gST;
extern EFI_BOOT_SERVICES *gBS;
extern EFI_HANDLE         gImageHandle;

#endif /* _BOOTEFI_EFI_H_ */
