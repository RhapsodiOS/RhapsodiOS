/* Post-ExitBootServices handoff.  Reproduces boot2's startprog(): flat GDT,
 * paging off, lret to selector 0x28.  Never returns. */
        .text
        .globl  _efi_handoff
        .globl  efi_handoff
_efi_handoff:
efi_handoff:
        movl    4(%esp), %ecx           /* kernel entry */

        cli

        /* Paging off.  UEFI permits identity-mapped paging on IA32; the
         * kernel requires it disabled. */
        movl    %cr0, %eax
        andl    $0x7FFFFFFF, %eax
        movl    %eax, %cr0
        xorl    %eax, %eax
        movl    %eax, %cr3

        lgdt    gdt_desc

        movl    $0x20, %eax
        movw    %ax, %ds
        movw    %ax, %es
        movw    %ax, %fs
        movw    %ax, %gs
        movw    %ax, %ss
        movl    $0xFFF0, %esp

        pushl   $0x28
        pushl   %ecx
        lret

        .data
        .align  4
        .globl  gdt_desc
        .globl  _gdt_desc
gdt_desc:
_gdt_desc:
        .word   47                      /* NGDTENT * 8 - 1 */
        .long   0                       /* filled in by efi_exit_and_start */
