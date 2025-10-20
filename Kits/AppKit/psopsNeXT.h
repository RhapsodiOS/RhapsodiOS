#import "psopsOpenStep.h"
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/PSmousekey.h generated from PSmousekey.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSMOUSEKEY_H
#define PSMOUSEKEY_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PShidecursor( void );

APPKIT_EXTERN void PSshowcursor( void );

APPKIT_EXTERN void PSobscurecursor( void );

APPKIT_EXTERN void PSrevealcursor( void );

APPKIT_EXTERN void PSsetcursor(float x, float y, float hotx, float hoty);

APPKIT_EXTERN void PSadjustcursor(float dx, float dy);

APPKIT_EXTERN void PScurrentmouse(int winNum, float *x, float *y);

APPKIT_EXTERN void PSsetmouse(float x, float y);

APPKIT_EXTERN void PSbuttondown(int *truth);

APPKIT_EXTERN void PSrightbuttondown(int *truth);

APPKIT_EXTERN void PSstilldown(int eNum, int *truth);

APPKIT_EXTERN void PSrightstilldown(int eNum, int *truth);

#endif PSMOUSEKEY_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/PSevent.h generated from PSevent.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSEVENT_H
#define PSEVENT_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSprinteventtimes( void );

APPKIT_EXTERN void PSiniteventtimes( void );

APPKIT_EXTERN void PSposteventbycontext(int type, float x, float y, int time, int flags, int win, int subtype, int data1, int data2, int context, int *success);

APPKIT_EXTERN void PSsetflushexposures(int flag);

APPKIT_EXTERN void PSsetwaitcursorenabled(int flag);

APPKIT_EXTERN void PScurrentwaitcursorenabled(int *flag);

APPKIT_EXTERN void PSsetactiveapp(int cntxt);

APPKIT_EXTERN void PScurrentactiveapp(int *cntxt);

#endif PSEVENT_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/PSmisc.h generated from PSmisc.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSMISC_H
#define PSMISC_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSosname(int size, char str[]);

APPKIT_EXTERN void PSostype(int *result);

APPKIT_EXTERN void PSnextrelease(int size, char result[]);

APPKIT_EXTERN void PScurrentrusage(float *now, float *uTime, float *sTime, int *msgSend, int *msgRcv, int *nSignals, int *nVCSw, int *nIvCSw);

APPKIT_EXTERN void PSplaysound(const char *name, int priority);

APPKIT_EXTERN void PScleardictstack( void );

APPKIT_EXTERN void PScurrentuser(int *uid, int *gid);

APPKIT_EXTERN void PSsetwriteblock(int flag);

APPKIT_EXTERN void PScurrentwriteblock(int *flag);

APPKIT_EXTERN void PSmachportdevice(int w, int h, const int bbox[], int bboxSize, const float matrix[], const char *host, const char *port, const char *pixelDict);

APPKIT_EXTERN void PScountframebuffers(int *count);

APPKIT_EXTERN void PSframebuffer(int index, int nameLen, char name[], int *slot, int *unit, int *ROMid, int *x, int *y, int *w, int *h, int *depth);

APPKIT_EXTERN void PSsetframebuffertransfer( void );

APPKIT_EXTERN void PScurrentframebuffertransfer( void );

#endif PSMISC_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/PSwindow.h generated from PSwindow.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSWINDOW_H
#define PSWINDOW_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSwindow(float x, float y, float w, float h, int type, int *num);

APPKIT_EXTERN void PStermwindow(int num);

APPKIT_EXTERN void PSwindowdevice(int num);

APPKIT_EXTERN void PSwindowdeviceround(int num);

APPKIT_EXTERN void PScurrentwindow(int *num);

APPKIT_EXTERN void PSflushgraphics( void );

APPKIT_EXTERN void PSflushgraphicsrect(float x, float y, float w, float h);

APPKIT_EXTERN void PSorderwindow(int op, int otherWin, int winNum);

APPKIT_EXTERN void PSmovewindow(float x, float y, int num);

APPKIT_EXTERN void PSplacewindow(float x, float y, float w, float h, int win);

APPKIT_EXTERN void PSfrontwindow(int *num);

APPKIT_EXTERN void PSfindwindow(float x, float y, int op, int otherWin, float *lx, float *ly, int *winFound, int *didFind);

APPKIT_EXTERN void PScurrentwindowbounds(int num, float *x, float *y, float *w, float *h);

APPKIT_EXTERN void PSseteventmask(int mask, int num);

APPKIT_EXTERN void PScurrenteventmask(int num, int *mask);

APPKIT_EXTERN void PSsetexposurecolor( void );

APPKIT_EXTERN void PSsetsendexposed(int truth, int num);

APPKIT_EXTERN void PSsetautofill(int truth, int num);

APPKIT_EXTERN void PSsetwindowdict(int num);

APPKIT_EXTERN void PScurrentwindowdict(int num);

APPKIT_EXTERN void PScurrentwindowalpha(int win, int *alpha);

APPKIT_EXTERN void PScountscreenlist(int context, int *count);

APPKIT_EXTERN void PSscreenlist(int context, int count, int windows[]);

APPKIT_EXTERN void PScurrentdeviceinfo(int win, int *minbps, int *maxbps, int *color);

APPKIT_EXTERN void PSsetowner(int owner, int win);

APPKIT_EXTERN void PScurrentowner(int win, int *owner);

APPKIT_EXTERN void PSbasetoscreen(float x, float y, float *xp, float *yp);

APPKIT_EXTERN void PSbasetocurrent(float x, float y, float *xp, float *yp);

APPKIT_EXTERN void PSscreentocurrent(float x, float y, float *xp, float *yp);

APPKIT_EXTERN void PSscreentobase(float x, float y, float *xp, float *yp);

APPKIT_EXTERN void PScurrenttoscreen(float x, float y, float *xp, float *yp);

APPKIT_EXTERN void PScurrenttobase(float x, float y, float *xp, float *yp);

APPKIT_EXTERN void PSdumpwindow(int level, int win);

APPKIT_EXTERN void PSdumpwindows(int level, int context);

APPKIT_EXTERN void PSsetwindowtype(int type, int win);

APPKIT_EXTERN void PSsetwindowlevel(int level, int win);

APPKIT_EXTERN void PScurrentwindowlevel(int win, int *level);

APPKIT_EXTERN void PScountwindowlist(int context, int *count);

APPKIT_EXTERN void PSwindowlist(int context, int count, int windows[]);

APPKIT_EXTERN void PSsetwindowdepthlimit(int limit, int win);

APPKIT_EXTERN void PScurrentwindowdepthlimit(int win, int *limit);

APPKIT_EXTERN void PScurrentwindowdepth(int win, int *depth);

APPKIT_EXTERN void PSsetdefaultdepthlimit(int limit);

APPKIT_EXTERN void PScurrentdefaultdepthlimit(int *limit);

APPKIT_EXTERN void PSsetshowpageprocedure(int win);

APPKIT_EXTERN void PScurrentshowpageprocedure( void );

#endif PSWINDOW_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/PSgraphics.h generated from PSgraphics.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSGRAPHICS_H
#define PSGRAPHICS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSsettrackingrect(float x, float y, float w, float h, int leftreqd, int rightreqd, int in, int userData, int tNum, int gstateNum);

APPKIT_EXTERN void PScleartrackingrect(int nrectnum, int gstateNum);

APPKIT_EXTERN void PSnewinstance( void );

APPKIT_EXTERN void PShideinstance(float x, float y, float w, float h);

APPKIT_EXTERN void PSsetinstance(int truth);

APPKIT_EXTERN void PSsizeimage(float x, float y, float w, float h, int *dw, int *dh, int *depth, float m[], int *multiproc, int *numColors);

APPKIT_EXTERN void PSreadimage( void );

APPKIT_EXTERN void PSalphaimage( void );

#endif PSGRAPHICS_H
