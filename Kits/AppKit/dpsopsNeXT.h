#import "dpsopsOpenStep.h"
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSmousekey.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSmousekey.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSMOUSEKEY_H
#define DPSMOUSEKEY_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPShidecursor(DPSContext ctxt);

APPKIT_EXTERN void DPSshowcursor(DPSContext ctxt);

APPKIT_EXTERN void DPSobscurecursor(DPSContext ctxt);

APPKIT_EXTERN void DPSrevealcursor(DPSContext ctxt);

APPKIT_EXTERN void DPSsetcursor(DPSContext ctxt, float x, float y, float hotx, float hoty);

APPKIT_EXTERN void DPSadjustcursor(DPSContext ctxt, float dx, float dy);

APPKIT_EXTERN void DPScurrentmouse(DPSContext ctxt, int winNum, float *x, float *y);

APPKIT_EXTERN void DPSsetmouse(DPSContext ctxt, float x, float y);

APPKIT_EXTERN void DPSbuttondown(DPSContext ctxt, int *truth);

APPKIT_EXTERN void DPSrightbuttondown(DPSContext ctxt, int *truth);

APPKIT_EXTERN void DPSstilldown(DPSContext ctxt, int eNum, int *truth);

APPKIT_EXTERN void DPSrightstilldown(DPSContext ctxt, int eNum, int *truth);

#endif DPSMOUSEKEY_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSevent.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSevent.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSEVENT_H
#define DPSEVENT_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSprinteventtimes(DPSContext ctxt);

APPKIT_EXTERN void DPSiniteventtimes(DPSContext ctxt);

APPKIT_EXTERN void DPSposteventbycontext(DPSContext ctxt, int type, float x, float y, int time, int flags, int win, int subtype, int data1, int data2, int context, int *success);

APPKIT_EXTERN void DPSsetflushexposures(DPSContext ctxt, int flag);

APPKIT_EXTERN void DPSsetwaitcursorenabled(DPSContext ctxt, int flag);

APPKIT_EXTERN void DPScurrentwaitcursorenabled(DPSContext ctxt, int *flag);

APPKIT_EXTERN void DPSsetactiveapp(DPSContext ctxt, int cntxt);

APPKIT_EXTERN void DPScurrentactiveapp(DPSContext ctxt, int *cntxt);

#endif DPSEVENT_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSmisc.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSmisc.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSMISC_H
#define DPSMISC_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSosname(DPSContext ctxt, int size, char str[]);

APPKIT_EXTERN void DPSostype(DPSContext ctxt, int *result);

APPKIT_EXTERN void DPSnextrelease(DPSContext ctxt, int size, char result[]);

APPKIT_EXTERN void DPScurrentrusage(DPSContext ctxt, float *now, float *uTime, float *sTime, int *msgSend, int *msgRcv, int *nSignals, int *nVCSw, int *nIvCSw);

APPKIT_EXTERN void DPSplaysound(DPSContext ctxt, const char *name, int priority);

APPKIT_EXTERN void DPScleardictstack(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentuser(DPSContext ctxt, int *uid, int *gid);

APPKIT_EXTERN void DPSsetwriteblock(DPSContext ctxt, int flag);

APPKIT_EXTERN void DPScurrentwriteblock(DPSContext ctxt, int *flag);

APPKIT_EXTERN void DPSmachportdevice(DPSContext ctxt, int w, int h, const int bbox[], int bboxSize, const float matrix[], const char *host, const char *port, const char *pixelDict);

APPKIT_EXTERN void DPScountframebuffers(DPSContext ctxt, int *count);

APPKIT_EXTERN void DPSframebuffer(DPSContext ctxt, int index, int nameLen, char name[], int *slot, int *unit, int *ROMid, int *x, int *y, int *w, int *h, int *depth);

APPKIT_EXTERN void DPSsetframebuffertransfer(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentframebuffertransfer(DPSContext ctxt);

#endif DPSMISC_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSwindow.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSwindow.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSWINDOW_H
#define DPSWINDOW_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSwindow(DPSContext ctxt, float x, float y, float w, float h, int type, int *num);

APPKIT_EXTERN void DPStermwindow(DPSContext ctxt, int num);

APPKIT_EXTERN void DPSwindowdevice(DPSContext ctxt, int num);

APPKIT_EXTERN void DPSwindowdeviceround(DPSContext ctxt, int num);

APPKIT_EXTERN void DPScurrentwindow(DPSContext ctxt, int *num);

APPKIT_EXTERN void DPSflushgraphics(DPSContext ctxt);

APPKIT_EXTERN void DPSflushgraphicsrect(DPSContext ctxt, float x, float y, float w, float h);

APPKIT_EXTERN void DPSorderwindow(DPSContext ctxt, int op, int otherWin, int winNum);

APPKIT_EXTERN void DPSmovewindow(DPSContext ctxt, float x, float y, int num);

APPKIT_EXTERN void DPSplacewindow(DPSContext ctxt, float x, float y, float w, float h, int win);

APPKIT_EXTERN void DPSfrontwindow(DPSContext ctxt, int *num);

APPKIT_EXTERN void DPSfindwindow(DPSContext ctxt, float x, float y, int op, int otherWin, float *lx, float *ly, int *winFound, int *didFind);

APPKIT_EXTERN void DPScurrentwindowbounds(DPSContext ctxt, int num, float *x, float *y, float *w, float *h);

APPKIT_EXTERN void DPSseteventmask(DPSContext ctxt, int mask, int num);

APPKIT_EXTERN void DPScurrenteventmask(DPSContext ctxt, int num, int *mask);

APPKIT_EXTERN void DPSsetexposurecolor(DPSContext ctxt);

APPKIT_EXTERN void DPSsetsendexposed(DPSContext ctxt, int truth, int num);

APPKIT_EXTERN void DPSsetautofill(DPSContext ctxt, int truth, int num);

APPKIT_EXTERN void DPSsetwindowdict(DPSContext ctxt, int num);

APPKIT_EXTERN void DPScurrentwindowdict(DPSContext ctxt, int num);

APPKIT_EXTERN void DPScurrentwindowalpha(DPSContext ctxt, int win, int *alpha);

APPKIT_EXTERN void DPScountscreenlist(DPSContext ctxt, int context, int *count);

APPKIT_EXTERN void DPSscreenlist(DPSContext ctxt, int context, int count, int windows[]);

APPKIT_EXTERN void DPScurrentdeviceinfo(DPSContext ctxt, int win, int *minbps, int *maxbps, int *color);

APPKIT_EXTERN void DPSsetowner(DPSContext ctxt, int owner, int win);

APPKIT_EXTERN void DPScurrentowner(DPSContext ctxt, int win, int *owner);

APPKIT_EXTERN void DPSbasetoscreen(DPSContext ctxt, float x, float y, float *xp, float *yp);

APPKIT_EXTERN void DPSbasetocurrent(DPSContext ctxt, float x, float y, float *xp, float *yp);

APPKIT_EXTERN void DPSscreentocurrent(DPSContext ctxt, float x, float y, float *xp, float *yp);

APPKIT_EXTERN void DPSscreentobase(DPSContext ctxt, float x, float y, float *xp, float *yp);

APPKIT_EXTERN void DPScurrenttoscreen(DPSContext ctxt, float x, float y, float *xp, float *yp);

APPKIT_EXTERN void DPScurrenttobase(DPSContext ctxt, float x, float y, float *xp, float *yp);

APPKIT_EXTERN void DPSdumpwindow(DPSContext ctxt, int level, int win);

APPKIT_EXTERN void DPSdumpwindows(DPSContext ctxt, int level, int context);

APPKIT_EXTERN void DPSsetwindowtype(DPSContext ctxt, int type, int win);

APPKIT_EXTERN void DPSsetwindowlevel(DPSContext ctxt, int level, int win);

APPKIT_EXTERN void DPScurrentwindowlevel(DPSContext ctxt, int win, int *level);

APPKIT_EXTERN void DPScountwindowlist(DPSContext ctxt, int context, int *count);

APPKIT_EXTERN void DPSwindowlist(DPSContext ctxt, int context, int count, int windows[]);

APPKIT_EXTERN void DPSsetwindowdepthlimit(DPSContext ctxt, int limit, int win);

APPKIT_EXTERN void DPScurrentwindowdepthlimit(DPSContext ctxt, int win, int *limit);

APPKIT_EXTERN void DPScurrentwindowdepth(DPSContext ctxt, int win, int *depth);

APPKIT_EXTERN void DPSsetdefaultdepthlimit(DPSContext ctxt, int limit);

APPKIT_EXTERN void DPScurrentdefaultdepthlimit(DPSContext ctxt, int *limit);

APPKIT_EXTERN void DPSsetshowpageprocedure(DPSContext ctxt, int win);

APPKIT_EXTERN void DPScurrentshowpageprocedure(DPSContext ctxt);

#endif DPSWINDOW_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSgraphics.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/DPSgraphics.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSGRAPHICS_H
#define DPSGRAPHICS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSsettrackingrect(DPSContext ctxt, float x, float y, float w, float h, int leftreqd, int rightreqd, int in, int userData, int tNum, int gstateNum);

APPKIT_EXTERN void DPScleartrackingrect(DPSContext ctxt, int nrectnum, int gstateNum);

APPKIT_EXTERN void DPSnewinstance(DPSContext ctxt);

APPKIT_EXTERN void DPShideinstance(DPSContext ctxt, float x, float y, float w, float h);

APPKIT_EXTERN void DPSsetinstance(DPSContext ctxt, int truth);

APPKIT_EXTERN void DPSsizeimage(DPSContext ctxt, float x, float y, float w, float h, int *dw, int *dh, int *depth, float m[], int *multiproc, int *numColors);

APPKIT_EXTERN void DPSreadimage(DPSContext ctxt);

APPKIT_EXTERN void DPSalphaimage(DPSContext ctxt);

#endif DPSGRAPHICS_H
