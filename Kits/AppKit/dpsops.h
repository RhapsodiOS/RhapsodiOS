/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpscolorops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpscolorops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSCOLOROPS_H
#define DPSCOLOROPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPScolorimage(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentblackgeneration(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentcmykcolor(DPSContext ctxt, float *c, float *m, float *y, float *k);

APPKIT_EXTERN void DPScurrentcolorscreen(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentcolortransfer(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentundercolorremoval(DPSContext ctxt);

APPKIT_EXTERN void DPSsetblackgeneration(DPSContext ctxt);

APPKIT_EXTERN void DPSsetcmykcolor(DPSContext ctxt, float c, float m, float y, float k);

APPKIT_EXTERN void DPSsetcolorscreen(DPSContext ctxt);

APPKIT_EXTERN void DPSsetcolortransfer(DPSContext ctxt);

APPKIT_EXTERN void DPSsetundercolorremoval(DPSContext ctxt);

#endif DPSCOLOROPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpscontrolops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpscontrolops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSCONTROLOPS_H
#define DPSCONTROLOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSeq(DPSContext ctxt);

APPKIT_EXTERN void DPSexit(DPSContext ctxt);

APPKIT_EXTERN void DPSfalse(DPSContext ctxt);

APPKIT_EXTERN void DPSfor(DPSContext ctxt);

APPKIT_EXTERN void DPSforall(DPSContext ctxt);

APPKIT_EXTERN void DPSge(DPSContext ctxt);

APPKIT_EXTERN void DPSgt(DPSContext ctxt);

APPKIT_EXTERN void DPSif(DPSContext ctxt);

APPKIT_EXTERN void DPSifelse(DPSContext ctxt);

APPKIT_EXTERN void DPSle(DPSContext ctxt);

APPKIT_EXTERN void DPSloop(DPSContext ctxt);

APPKIT_EXTERN void DPSlt(DPSContext ctxt);

APPKIT_EXTERN void DPSne(DPSContext ctxt);

APPKIT_EXTERN void DPSnot(DPSContext ctxt);

APPKIT_EXTERN void DPSor(DPSContext ctxt);

APPKIT_EXTERN void DPSrepeat(DPSContext ctxt);

APPKIT_EXTERN void DPSstop(DPSContext ctxt);

APPKIT_EXTERN void DPSstopped(DPSContext ctxt);

APPKIT_EXTERN void DPStrue(DPSContext ctxt);

#endif DPSCONTROLOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsctxtops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsctxtops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSCTXTOPS_H
#define DPSCTXTOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPScondition(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentcontext(DPSContext ctxt, int *cid);

APPKIT_EXTERN void DPScurrentobjectformat(DPSContext ctxt, int *code);

APPKIT_EXTERN void DPSdefineusername(DPSContext ctxt, int i, const char *username);

APPKIT_EXTERN void DPSdefineuserobject(DPSContext ctxt);

APPKIT_EXTERN void DPSdetach(DPSContext ctxt);

APPKIT_EXTERN void DPSexecuserobject(DPSContext ctxt, int index);

APPKIT_EXTERN void DPSfork(DPSContext ctxt);

APPKIT_EXTERN void DPSjoin(DPSContext ctxt);

APPKIT_EXTERN void DPSlock(DPSContext ctxt);

APPKIT_EXTERN void DPSmonitor(DPSContext ctxt);

APPKIT_EXTERN void DPSnotify(DPSContext ctxt);

APPKIT_EXTERN void DPSsetobjectformat(DPSContext ctxt, int code);

APPKIT_EXTERN void DPSsetvmthreshold(DPSContext ctxt, int i);

APPKIT_EXTERN void DPSundefineuserobject(DPSContext ctxt, int index);

APPKIT_EXTERN void DPSuserobject(DPSContext ctxt);

APPKIT_EXTERN void DPSwait(DPSContext ctxt);

APPKIT_EXTERN void DPSyield(DPSContext ctxt);

#endif DPSCTXTOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsdataops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsdataops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSDATAOPS_H
#define DPSDATAOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSaload(DPSContext ctxt);

APPKIT_EXTERN void DPSanchorsearch(DPSContext ctxt, int *truth);

APPKIT_EXTERN void DPSarray(DPSContext ctxt, int len);

APPKIT_EXTERN void DPSastore(DPSContext ctxt);

APPKIT_EXTERN void DPSbegin(DPSContext ctxt);

APPKIT_EXTERN void DPSclear(DPSContext ctxt);

APPKIT_EXTERN void DPScleartomark(DPSContext ctxt);

APPKIT_EXTERN void DPScopy(DPSContext ctxt, int n);

APPKIT_EXTERN void DPScount(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPScounttomark(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPScvi(DPSContext ctxt);

APPKIT_EXTERN void DPScvlit(DPSContext ctxt);

APPKIT_EXTERN void DPScvn(DPSContext ctxt);

APPKIT_EXTERN void DPScvr(DPSContext ctxt);

APPKIT_EXTERN void DPScvrs(DPSContext ctxt);

APPKIT_EXTERN void DPScvs(DPSContext ctxt);

APPKIT_EXTERN void DPScvx(DPSContext ctxt);

APPKIT_EXTERN void DPSdef(DPSContext ctxt);

APPKIT_EXTERN void DPSdict(DPSContext ctxt, int len);

APPKIT_EXTERN void DPSdictstack(DPSContext ctxt);

APPKIT_EXTERN void DPSdup(DPSContext ctxt);

APPKIT_EXTERN void DPSend(DPSContext ctxt);

APPKIT_EXTERN void DPSexch(DPSContext ctxt);

APPKIT_EXTERN void DPSexecstack(DPSContext ctxt);

APPKIT_EXTERN void DPSexecuteonly(DPSContext ctxt);

APPKIT_EXTERN void DPSget(DPSContext ctxt);

APPKIT_EXTERN void DPSgetinterval(DPSContext ctxt);

APPKIT_EXTERN void DPSindex(DPSContext ctxt, int i);

APPKIT_EXTERN void DPSknown(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSlength(DPSContext ctxt, int *len);

APPKIT_EXTERN void DPSload(DPSContext ctxt);

APPKIT_EXTERN void DPSmark(DPSContext ctxt);

APPKIT_EXTERN void DPSmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSmaxlength(DPSContext ctxt, int *len);

APPKIT_EXTERN void DPSnoaccess(DPSContext ctxt);

APPKIT_EXTERN void DPSnull(DPSContext ctxt);

APPKIT_EXTERN void DPSpackedarray(DPSContext ctxt);

APPKIT_EXTERN void DPSpop(DPSContext ctxt);

APPKIT_EXTERN void DPSput(DPSContext ctxt);

APPKIT_EXTERN void DPSputinterval(DPSContext ctxt);

APPKIT_EXTERN void DPSrcheck(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSreadonly(DPSContext ctxt);

APPKIT_EXTERN void DPSroll(DPSContext ctxt, int n, int j);

APPKIT_EXTERN void DPSscheck(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSsearch(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSshareddict(DPSContext ctxt);

APPKIT_EXTERN void DPSstatusdict(DPSContext ctxt);

APPKIT_EXTERN void DPSstore(DPSContext ctxt);

APPKIT_EXTERN void DPSstring(DPSContext ctxt, int len);

APPKIT_EXTERN void DPSstringwidth(DPSContext ctxt, const char *s, float *xp, float *yp);

APPKIT_EXTERN void DPSsystemdict(DPSContext ctxt);

APPKIT_EXTERN void DPSuserdict(DPSContext ctxt);

APPKIT_EXTERN void DPSwcheck(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSwhere(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSxcheck(DPSContext ctxt, int *b);

#endif DPSDATAOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsfontops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsfontops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSFONTOPS_H
#define DPSFONTOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSFontDirectory(DPSContext ctxt);

APPKIT_EXTERN void DPSISOLatin1Encoding(DPSContext ctxt);

APPKIT_EXTERN void DPSSharedFontDirectory(DPSContext ctxt);

APPKIT_EXTERN void DPSStandardEncoding(DPSContext ctxt);

APPKIT_EXTERN void DPScachestatus(DPSContext ctxt, int *bsize, int *bmax, int *msize);

APPKIT_EXTERN void DPScurrentcacheparams(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentfont(DPSContext ctxt);

APPKIT_EXTERN void DPSdefinefont(DPSContext ctxt);

APPKIT_EXTERN void DPSfindfont(DPSContext ctxt, const char *name);

APPKIT_EXTERN void DPSmakefont(DPSContext ctxt);

APPKIT_EXTERN void DPSscalefont(DPSContext ctxt, float size);

APPKIT_EXTERN void DPSselectfont(DPSContext ctxt, const char *name, float scale);

APPKIT_EXTERN void DPSsetcachedevice(DPSContext ctxt, float wx, float wy, float llx, float lly, float urx, float ury);

APPKIT_EXTERN void DPSsetcachelimit(DPSContext ctxt, float n);

APPKIT_EXTERN void DPSsetcacheparams(DPSContext ctxt);

APPKIT_EXTERN void DPSsetcharwidth(DPSContext ctxt, float wx, float wy);

APPKIT_EXTERN void DPSsetfont(DPSContext ctxt, int f);

APPKIT_EXTERN void DPSundefinefont(DPSContext ctxt, const char *name);

#endif DPSFONTOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsgstateops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsgstateops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSGSTATEOPS_H
#define DPSGSTATEOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSconcat(DPSContext ctxt, const float m[]);

APPKIT_EXTERN void DPScurrentdash(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentflat(DPSContext ctxt, float *flatness);

APPKIT_EXTERN void DPScurrentgray(DPSContext ctxt, float *gray);

APPKIT_EXTERN void DPScurrentgstate(DPSContext ctxt, int gst);

APPKIT_EXTERN void DPScurrenthalftone(DPSContext ctxt);

APPKIT_EXTERN void DPScurrenthalftonephase(DPSContext ctxt, int *x, int *y);

APPKIT_EXTERN void DPScurrenthsbcolor(DPSContext ctxt, float *h, float *s, float *b);

APPKIT_EXTERN void DPScurrentlinecap(DPSContext ctxt, int *linecap);

APPKIT_EXTERN void DPScurrentlinejoin(DPSContext ctxt, int *linejoin);

APPKIT_EXTERN void DPScurrentlinewidth(DPSContext ctxt, float *width);

APPKIT_EXTERN void DPScurrentmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentmiterlimit(DPSContext ctxt, float *limit);

APPKIT_EXTERN void DPScurrentpoint(DPSContext ctxt, float *x, float *y);

APPKIT_EXTERN void DPScurrentrgbcolor(DPSContext ctxt, float *r, float *g, float *b);

APPKIT_EXTERN void DPScurrentscreen(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentstrokeadjust(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPScurrenttransfer(DPSContext ctxt);

APPKIT_EXTERN void DPSdefaultmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSgrestore(DPSContext ctxt);

APPKIT_EXTERN void DPSgrestoreall(DPSContext ctxt);

APPKIT_EXTERN void DPSgsave(DPSContext ctxt);

APPKIT_EXTERN void DPSgstate(DPSContext ctxt);

APPKIT_EXTERN void DPSinitgraphics(DPSContext ctxt);

APPKIT_EXTERN void DPSinitmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSrotate(DPSContext ctxt, float angle);

APPKIT_EXTERN void DPSscale(DPSContext ctxt, float x, float y);

APPKIT_EXTERN void DPSsetdash(DPSContext ctxt, const float pat[], int size, float offset);

APPKIT_EXTERN void DPSsetflat(DPSContext ctxt, float flatness);

APPKIT_EXTERN void DPSsetgray(DPSContext ctxt, float gray);

APPKIT_EXTERN void DPSsetgstate(DPSContext ctxt, int gst);

APPKIT_EXTERN void DPSsethalftone(DPSContext ctxt);

APPKIT_EXTERN void DPSsethalftonephase(DPSContext ctxt, int x, int y);

APPKIT_EXTERN void DPSsethsbcolor(DPSContext ctxt, float h, float s, float b);

APPKIT_EXTERN void DPSsetlinecap(DPSContext ctxt, int linecap);

APPKIT_EXTERN void DPSsetlinejoin(DPSContext ctxt, int linejoin);

APPKIT_EXTERN void DPSsetlinewidth(DPSContext ctxt, float width);

APPKIT_EXTERN void DPSsetmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSsetmiterlimit(DPSContext ctxt, float limit);

APPKIT_EXTERN void DPSsetrgbcolor(DPSContext ctxt, float r, float g, float b);

APPKIT_EXTERN void DPSsetscreen(DPSContext ctxt);

APPKIT_EXTERN void DPSsetstrokeadjust(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSsettransfer(DPSContext ctxt);

APPKIT_EXTERN void DPStranslate(DPSContext ctxt, float x, float y);

#endif DPSGSTATEOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsioops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsioops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSIOOPS_H
#define DPSIOOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSequals(DPSContext ctxt);

APPKIT_EXTERN void DPSequalsequals(DPSContext ctxt);

APPKIT_EXTERN void DPSbytesavailable(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPSclosefile(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentfile(DPSContext ctxt);

APPKIT_EXTERN void DPSdeletefile(DPSContext ctxt, const char *filename);

APPKIT_EXTERN void DPSecho(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSfile(DPSContext ctxt, const char *name, const char *access);

APPKIT_EXTERN void DPSfilenameforall(DPSContext ctxt);

APPKIT_EXTERN void DPSfileposition(DPSContext ctxt, int *pos);

APPKIT_EXTERN void DPSflush(DPSContext ctxt);

APPKIT_EXTERN void DPSflushfile(DPSContext ctxt);

APPKIT_EXTERN void DPSprint(DPSContext ctxt);

APPKIT_EXTERN void DPSprintobject(DPSContext ctxt, int tag);

APPKIT_EXTERN void DPSpstack(DPSContext ctxt);

APPKIT_EXTERN void DPSread(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSreadhexstring(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSreadline(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSreadstring(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSrenamefile(DPSContext ctxt, const char *oldfile, const char *newfile);

APPKIT_EXTERN void DPSresetfile(DPSContext ctxt);

APPKIT_EXTERN void DPSsetfileposition(DPSContext ctxt, int pos);

APPKIT_EXTERN void DPSstack(DPSContext ctxt);

APPKIT_EXTERN void DPSstatus(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPStoken(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSwrite(DPSContext ctxt);

APPKIT_EXTERN void DPSwritehexstring(DPSContext ctxt);

APPKIT_EXTERN void DPSwriteobject(DPSContext ctxt, int tag);

APPKIT_EXTERN void DPSwritestring(DPSContext ctxt);

#endif DPSIOOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsmathops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsmathops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSMATHOPS_H
#define DPSMATHOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSabs(DPSContext ctxt);

APPKIT_EXTERN void DPSadd(DPSContext ctxt);

APPKIT_EXTERN void DPSand(DPSContext ctxt);

APPKIT_EXTERN void DPSatan(DPSContext ctxt);

APPKIT_EXTERN void DPSbitshift(DPSContext ctxt, int shift);

APPKIT_EXTERN void DPSceiling(DPSContext ctxt);

APPKIT_EXTERN void DPScos(DPSContext ctxt);

APPKIT_EXTERN void DPSdiv(DPSContext ctxt);

APPKIT_EXTERN void DPSexp(DPSContext ctxt);

APPKIT_EXTERN void DPSfloor(DPSContext ctxt);

APPKIT_EXTERN void DPSidiv(DPSContext ctxt);

APPKIT_EXTERN void DPSln(DPSContext ctxt);

APPKIT_EXTERN void DPSlog(DPSContext ctxt);

APPKIT_EXTERN void DPSmod(DPSContext ctxt);

APPKIT_EXTERN void DPSmul(DPSContext ctxt);

APPKIT_EXTERN void DPSneg(DPSContext ctxt);

APPKIT_EXTERN void DPSround(DPSContext ctxt);

APPKIT_EXTERN void DPSsin(DPSContext ctxt);

APPKIT_EXTERN void DPSsqrt(DPSContext ctxt);

APPKIT_EXTERN void DPSsub(DPSContext ctxt);

APPKIT_EXTERN void DPStruncate(DPSContext ctxt);

APPKIT_EXTERN void DPSxor(DPSContext ctxt);

#endif DPSMATHOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsmatrixops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsmatrixops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSMATRIXOPS_H
#define DPSMATRIXOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSconcatmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSdtransform(DPSContext ctxt, float x1, float y1, float *x2, float *y2);

APPKIT_EXTERN void DPSidentmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSidtransform(DPSContext ctxt, float x1, float y1, float *x2, float *y2);

APPKIT_EXTERN void DPSinvertmatrix(DPSContext ctxt);

APPKIT_EXTERN void DPSitransform(DPSContext ctxt, float x1, float y1, float *x2, float *y2);

APPKIT_EXTERN void DPStransform(DPSContext ctxt, float x1, float y1, float *x2, float *y2);

#endif DPSMATRIXOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsmiscops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsmiscops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSMISCOPS_H
#define DPSMISCOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSbanddevice(DPSContext ctxt);

APPKIT_EXTERN void DPSframedevice(DPSContext ctxt);

APPKIT_EXTERN void DPSnulldevice(DPSContext ctxt);

APPKIT_EXTERN void DPSrenderbands(DPSContext ctxt);

#endif DPSMISCOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsopstack.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsopstack.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSOPSTACK_H
#define DPSOPSTACK_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSgetboolean(DPSContext ctxt, int *it);

APPKIT_EXTERN void DPSgetchararray(DPSContext ctxt, int size, char s[]);

APPKIT_EXTERN void DPSgetfloat(DPSContext ctxt, float *it);

APPKIT_EXTERN void DPSgetfloatarray(DPSContext ctxt, int size, float a[]);

APPKIT_EXTERN void DPSgetint(DPSContext ctxt, int *it);

APPKIT_EXTERN void DPSgetintarray(DPSContext ctxt, int size, int a[]);

APPKIT_EXTERN void DPSgetstring(DPSContext ctxt, char *s);

APPKIT_EXTERN void DPSsendboolean(DPSContext ctxt, int it);

APPKIT_EXTERN void DPSsendchararray(DPSContext ctxt, const char s[], int size);

APPKIT_EXTERN void DPSsendfloat(DPSContext ctxt, float it);

APPKIT_EXTERN void DPSsendfloatarray(DPSContext ctxt, const float a[], int size);

APPKIT_EXTERN void DPSsendint(DPSContext ctxt, int it);

APPKIT_EXTERN void DPSsendintarray(DPSContext ctxt, const int a[], int size);

APPKIT_EXTERN void DPSsendstring(DPSContext ctxt, const char *s);

#endif DPSOPSTACK_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpspaintops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpspaintops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSPAINTOPS_H
#define DPSPAINTOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSashow(DPSContext ctxt, float x, float y, const char *s);

APPKIT_EXTERN void DPSawidthshow(DPSContext ctxt, float cx, float cy, int c, float ax, float ay, const char *s);

APPKIT_EXTERN void DPScopypage(DPSContext ctxt);

APPKIT_EXTERN void DPSeofill(DPSContext ctxt);

APPKIT_EXTERN void DPSerasepage(DPSContext ctxt);

APPKIT_EXTERN void DPSfill(DPSContext ctxt);

APPKIT_EXTERN void DPSimage(DPSContext ctxt);

APPKIT_EXTERN void DPSimagemask(DPSContext ctxt);

APPKIT_EXTERN void DPSkshow(DPSContext ctxt, const char *s);

APPKIT_EXTERN void DPSrectfill(DPSContext ctxt, float x, float y, float w, float h);

APPKIT_EXTERN void DPSrectstroke(DPSContext ctxt, float x, float y, float w, float h);

APPKIT_EXTERN void DPSshow(DPSContext ctxt, const char *s);

APPKIT_EXTERN void DPSshowpage(DPSContext ctxt);

APPKIT_EXTERN void DPSstroke(DPSContext ctxt);

APPKIT_EXTERN void DPSstrokepath(DPSContext ctxt);

APPKIT_EXTERN void DPSueofill(DPSContext ctxt, const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void DPSufill(DPSContext ctxt, const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void DPSustroke(DPSContext ctxt, const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void DPSustrokepath(DPSContext ctxt, const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void DPSwidthshow(DPSContext ctxt, float x, float y, int c, const char *s);

APPKIT_EXTERN void DPSxshow(DPSContext ctxt, const char *s, const float numarray[], int size);

APPKIT_EXTERN void DPSxyshow(DPSContext ctxt, const char *s, const float numarray[], int size);

APPKIT_EXTERN void DPSyshow(DPSContext ctxt, const char *s, const float numarray[], int size);

#endif DPSPAINTOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpspathops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpspathops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSPATHOPS_H
#define DPSPATHOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSarc(DPSContext ctxt, float x, float y, float r, float angle1, float angle2);

APPKIT_EXTERN void DPSarcn(DPSContext ctxt, float x, float y, float r, float angle1, float angle2);

APPKIT_EXTERN void DPSarct(DPSContext ctxt, float x1, float y1, float x2, float y2, float r);

APPKIT_EXTERN void DPSarcto(DPSContext ctxt, float x1, float y1, float x2, float y2, float r, float *xt1, float *yt1, float *xt2, float *yt2);

APPKIT_EXTERN void DPScharpath(DPSContext ctxt, const char *s, int b);

APPKIT_EXTERN void DPSclip(DPSContext ctxt);

APPKIT_EXTERN void DPSclippath(DPSContext ctxt);

APPKIT_EXTERN void DPSclosepath(DPSContext ctxt);

APPKIT_EXTERN void DPScurveto(DPSContext ctxt, float x1, float y1, float x2, float y2, float x3, float y3);

APPKIT_EXTERN void DPSeoclip(DPSContext ctxt);

APPKIT_EXTERN void DPSeoviewclip(DPSContext ctxt);

APPKIT_EXTERN void DPSflattenpath(DPSContext ctxt);

APPKIT_EXTERN void DPSinitclip(DPSContext ctxt);

APPKIT_EXTERN void DPSinitviewclip(DPSContext ctxt);

APPKIT_EXTERN void DPSlineto(DPSContext ctxt, float x, float y);

APPKIT_EXTERN void DPSmoveto(DPSContext ctxt, float x, float y);

APPKIT_EXTERN void DPSnewpath(DPSContext ctxt);

APPKIT_EXTERN void DPSpathbbox(DPSContext ctxt, float *llx, float *lly, float *urx, float *ury);

APPKIT_EXTERN void DPSpathforall(DPSContext ctxt);

APPKIT_EXTERN void DPSrcurveto(DPSContext ctxt, float x1, float y1, float x2, float y2, float x3, float y3);

APPKIT_EXTERN void DPSrectclip(DPSContext ctxt, float x, float y, float w, float h);

APPKIT_EXTERN void DPSrectviewclip(DPSContext ctxt, float x, float y, float w, float h);

APPKIT_EXTERN void DPSreversepath(DPSContext ctxt);

APPKIT_EXTERN void DPSrlineto(DPSContext ctxt, float x, float y);

APPKIT_EXTERN void DPSrmoveto(DPSContext ctxt, float x, float y);

APPKIT_EXTERN void DPSsetbbox(DPSContext ctxt, float llx, float lly, float urx, float ury);

APPKIT_EXTERN void DPSsetucacheparams(DPSContext ctxt);

APPKIT_EXTERN void DPSuappend(DPSContext ctxt, const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void DPSucache(DPSContext ctxt);

APPKIT_EXTERN void DPSucachestatus(DPSContext ctxt);

APPKIT_EXTERN void DPSupath(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSviewclip(DPSContext ctxt);

APPKIT_EXTERN void DPSviewclippath(DPSContext ctxt);

#endif DPSPATHOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpssysops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpssysops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSSYSOPS_H
#define DPSSYSOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSbind(DPSContext ctxt);

APPKIT_EXTERN void DPScountdictstack(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPScountexecstack(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPScurrentdict(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentpacking(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPScurrentshared(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSdeviceinfo(DPSContext ctxt);

APPKIT_EXTERN void DPSerrordict(DPSContext ctxt);

APPKIT_EXTERN void DPSexec(DPSContext ctxt);

APPKIT_EXTERN void DPSprompt(DPSContext ctxt);

APPKIT_EXTERN void DPSquit(DPSContext ctxt);

APPKIT_EXTERN void DPSrand(DPSContext ctxt);

APPKIT_EXTERN void DPSrealtime(DPSContext ctxt, int *i);

APPKIT_EXTERN void DPSrestore(DPSContext ctxt);

APPKIT_EXTERN void DPSrrand(DPSContext ctxt);

APPKIT_EXTERN void DPSrun(DPSContext ctxt, const char *filename);

APPKIT_EXTERN void DPSsave(DPSContext ctxt);

APPKIT_EXTERN void DPSsetpacking(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSsetshared(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSsrand(DPSContext ctxt);

APPKIT_EXTERN void DPSstart(DPSContext ctxt);

APPKIT_EXTERN void DPStype(DPSContext ctxt);

APPKIT_EXTERN void DPSundef(DPSContext ctxt, const char *name);

APPKIT_EXTERN void DPSusertime(DPSContext ctxt, int *milliseconds);

APPKIT_EXTERN void DPSversion(DPSContext ctxt, int bufsize, char buf[]);

APPKIT_EXTERN void DPSvmreclaim(DPSContext ctxt, int code);

APPKIT_EXTERN void DPSvmstatus(DPSContext ctxt, int *level, int *used, int *maximum);

#endif DPSSYSOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpswinops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpswinops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSWINOPS_H
#define DPSWINOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSineofill(DPSContext ctxt, float x, float y, int *b);

APPKIT_EXTERN void DPSinfill(DPSContext ctxt, float x, float y, int *b);

APPKIT_EXTERN void DPSinstroke(DPSContext ctxt, float x, float y, int *b);

APPKIT_EXTERN void DPSinueofill(DPSContext ctxt, float x, float y, const char nums[], int n, const char ops[], int l, int *b);

APPKIT_EXTERN void DPSinufill(DPSContext ctxt, float x, float y, const char nums[], int n, const char ops[], int l, int *b);

APPKIT_EXTERN void DPSinustroke(DPSContext ctxt, float x, float y, const char nums[], int n, const char ops[], int l, int *b);

APPKIT_EXTERN void DPSwtranslation(DPSContext ctxt, float *x, float *y);

#endif DPSWINOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsl2ops.h generated from /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/ContextWraps.subproj/dpsl2ops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef DPSL2OPS_H
#define DPSL2OPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void DPSleftbracket(DPSContext ctxt);

APPKIT_EXTERN void DPSrightbracket(DPSContext ctxt);

APPKIT_EXTERN void DPSleftleft(DPSContext ctxt);

APPKIT_EXTERN void DPSrightright(DPSContext ctxt);

APPKIT_EXTERN void DPScshow(DPSContext ctxt, const char *s);

APPKIT_EXTERN void DPScurrentcolor(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentcolorrendering(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentcolorspace(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentdevparams(DPSContext ctxt, const char *dev);

APPKIT_EXTERN void DPScurrentglobal(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPScurrentoverprint(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPScurrentpagedevice(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentsystemparams(DPSContext ctxt);

APPKIT_EXTERN void DPScurrentuserparams(DPSContext ctxt);

APPKIT_EXTERN void DPSdefineresource(DPSContext ctxt, const char *category);

APPKIT_EXTERN void DPSexecform(DPSContext ctxt);

APPKIT_EXTERN void DPSfilter(DPSContext ctxt);

APPKIT_EXTERN void DPSfindencoding(DPSContext ctxt, const char *key);

APPKIT_EXTERN void DPSfindresource(DPSContext ctxt, const char *key, const char *category);

APPKIT_EXTERN void DPSgcheck(DPSContext ctxt, int *b);

APPKIT_EXTERN void DPSglobaldict(DPSContext ctxt);

APPKIT_EXTERN void DPSGlobalFontDirectory(DPSContext ctxt);

APPKIT_EXTERN void DPSglyphshow(DPSContext ctxt, const char *name);

APPKIT_EXTERN void DPSlanguagelevel(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPSmakepattern(DPSContext ctxt);

APPKIT_EXTERN void DPSproduct(DPSContext ctxt);

APPKIT_EXTERN void DPSresourceforall(DPSContext ctxt, const char *category);

APPKIT_EXTERN void DPSresourcestatus(DPSContext ctxt, const char *key, const char *category, int *b);

APPKIT_EXTERN void DPSrevision(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPSrootfont(DPSContext ctxt);

APPKIT_EXTERN void DPSserialnumber(DPSContext ctxt, int *n);

APPKIT_EXTERN void DPSsetcolor(DPSContext ctxt);

APPKIT_EXTERN void DPSsetcolorrendering(DPSContext ctxt);

APPKIT_EXTERN void DPSsetcolorspace(DPSContext ctxt);

APPKIT_EXTERN void DPSsetdevparams(DPSContext ctxt);

APPKIT_EXTERN void DPSsetglobal(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSsetoverprint(DPSContext ctxt, int b);

APPKIT_EXTERN void DPSsetpagedevice(DPSContext ctxt);

APPKIT_EXTERN void DPSsetpattern(DPSContext ctxt, int patternDict);

APPKIT_EXTERN void DPSsetsystemparams(DPSContext ctxt);

APPKIT_EXTERN void DPSsetuserparams(DPSContext ctxt);

APPKIT_EXTERN void DPSstartjob(DPSContext ctxt, int b, const char *password);

APPKIT_EXTERN void DPSundefineresource(DPSContext ctxt, const char *key, const char *category);

#endif DPSL2OPS_H
