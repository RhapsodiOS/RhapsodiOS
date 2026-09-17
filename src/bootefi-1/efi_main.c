#include "efi.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    gImageHandle = image;
    gST = systab;
    gBS = systab->BootServices;

    gST->ConOut->ClearScreen(gST->ConOut);
    gST->ConOut->OutputString(gST->ConOut,
        (CHAR16 *)L"RhapsodiOS UEFI loader\r\n");

    for (;;)
        ;
    return EFI_SUCCESS;
}
