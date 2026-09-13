/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Thread.m - I/O thread methods for the Symbios 53C8xx driver.
 *
 * HISTORY
 *
 * Reconstructed from SYM53c8_reloc (divergences.md).
 *
 * threadExecuteRequest: / threadResetSCSIBus live on the main
 * @implementation SYM53c8 in SYM53c8Controller.m so the source-map
 * keys match -[SYM53c8 ...] and kl_ld does not see two class symbols.
 */

#import "SYM53c8Thread.h"

@implementation SYM53c8(IOThread)
@end
