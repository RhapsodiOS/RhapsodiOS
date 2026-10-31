#ifndef I556_ADAPTER_TEST_IOPORTS_H
#define I556_ADAPTER_TEST_IOPORTS_H
/* Test-only replacements: never execute privileged port instructions. */
unsigned char inb(unsigned short port);
unsigned short inw(unsigned short port);
unsigned long inl(unsigned short port);
void outb(unsigned short port, unsigned char value);
void outw(unsigned short port, unsigned short value);
void outl(unsigned short port, unsigned long value);
#endif
