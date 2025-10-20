#import "psops.h"
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/PSopenstep.h generated from PSopenstep.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSOPENSTEP_H
#define PSOPENSTEP_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PScomposite(float x, float y, float w, float h, int gstateNum, float dx, float dy, int op);

APPKIT_EXTERN void PScompositerect(float x, float y, float w, float h, int op);

APPKIT_EXTERN void PSdissolve(float x, float y, float w, float h, int gstateNum, float dx, float dy, float delta);

APPKIT_EXTERN void PSsetalpha(float a);

APPKIT_EXTERN void PScurrentalpha(float *alpha);

#endif PSOPENSTEP_H
