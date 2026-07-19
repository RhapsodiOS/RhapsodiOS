/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/pscolorops.h generated from pscolorops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSCOLOROPS_H
#define PSCOLOROPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PScolorimage( void );

APPKIT_EXTERN void PScurrentblackgeneration( void );

APPKIT_EXTERN void PScurrentcmykcolor(float *c, float *m, float *y, float *k);

APPKIT_EXTERN void PScurrentcolorscreen( void );

APPKIT_EXTERN void PScurrentcolortransfer( void );

APPKIT_EXTERN void PScurrentundercolorremoval( void );

APPKIT_EXTERN void PSsetblackgeneration( void );

APPKIT_EXTERN void PSsetcmykcolor(float c, float m, float y, float k);

APPKIT_EXTERN void PSsetcolorscreen( void );

APPKIT_EXTERN void PSsetcolortransfer( void );

APPKIT_EXTERN void PSsetundercolorremoval( void );

#endif PSCOLOROPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/pscontrolops.h generated from pscontrolops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSCONTROLOPS_H
#define PSCONTROLOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSeq( void );

APPKIT_EXTERN void PSexit( void );

APPKIT_EXTERN void PSfalse( void );

APPKIT_EXTERN void PSfor( void );

APPKIT_EXTERN void PSforall( void );

APPKIT_EXTERN void PSge( void );

APPKIT_EXTERN void PSgt( void );

APPKIT_EXTERN void PSif( void );

APPKIT_EXTERN void PSifelse( void );

APPKIT_EXTERN void PSle( void );

APPKIT_EXTERN void PSloop( void );

APPKIT_EXTERN void PSlt( void );

APPKIT_EXTERN void PSne( void );

APPKIT_EXTERN void PSnot( void );

APPKIT_EXTERN void PSor( void );

APPKIT_EXTERN void PSrepeat( void );

APPKIT_EXTERN void PSstop( void );

APPKIT_EXTERN void PSstopped( void );

APPKIT_EXTERN void PStrue( void );

#endif PSCONTROLOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psctxtops.h generated from psctxtops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSCTXTOPS_H
#define PSCTXTOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PScondition( void );

APPKIT_EXTERN void PScurrentcontext(int *cid);

APPKIT_EXTERN void PScurrentobjectformat(int *code);

APPKIT_EXTERN void PSdefineusername(int i, const char *username);

APPKIT_EXTERN void PSdefineuserobject( void );

APPKIT_EXTERN void PSdetach( void );

APPKIT_EXTERN void PSexecuserobject(int index);

APPKIT_EXTERN void PSfork( void );

APPKIT_EXTERN void PSjoin( void );

APPKIT_EXTERN void PSlock( void );

APPKIT_EXTERN void PSmonitor( void );

APPKIT_EXTERN void PSnotify( void );

APPKIT_EXTERN void PSsetobjectformat(int code);

APPKIT_EXTERN void PSsetvmthreshold(int i);

APPKIT_EXTERN void PSundefineuserobject(int index);

APPKIT_EXTERN void PSuserobject( void );

APPKIT_EXTERN void PSwait( void );

APPKIT_EXTERN void PSyield( void );

#endif PSCTXTOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psdataops.h generated from psdataops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSDATAOPS_H
#define PSDATAOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSaload( void );

APPKIT_EXTERN void PSanchorsearch(int *truth);

APPKIT_EXTERN void PSarray(int len);

APPKIT_EXTERN void PSastore( void );

APPKIT_EXTERN void PSbegin( void );

APPKIT_EXTERN void PSclear( void );

APPKIT_EXTERN void PScleartomark( void );

APPKIT_EXTERN void PScopy(int n);

APPKIT_EXTERN void PScount(int *n);

APPKIT_EXTERN void PScounttomark(int *n);

APPKIT_EXTERN void PScvi( void );

APPKIT_EXTERN void PScvlit( void );

APPKIT_EXTERN void PScvn( void );

APPKIT_EXTERN void PScvr( void );

APPKIT_EXTERN void PScvrs( void );

APPKIT_EXTERN void PScvs( void );

APPKIT_EXTERN void PScvx( void );

APPKIT_EXTERN void PSdef( void );

APPKIT_EXTERN void PSdict(int len);

APPKIT_EXTERN void PSdictstack( void );

APPKIT_EXTERN void PSdup( void );

APPKIT_EXTERN void PSend( void );

APPKIT_EXTERN void PSexch( void );

APPKIT_EXTERN void PSexecstack( void );

APPKIT_EXTERN void PSexecuteonly( void );

APPKIT_EXTERN void PSget( void );

APPKIT_EXTERN void PSgetinterval( void );

APPKIT_EXTERN void PSindex(int i);

APPKIT_EXTERN void PSknown(int *b);

APPKIT_EXTERN void PSlength(int *len);

APPKIT_EXTERN void PSload( void );

APPKIT_EXTERN void PSmark( void );

APPKIT_EXTERN void PSmatrix( void );

APPKIT_EXTERN void PSmaxlength(int *len);

APPKIT_EXTERN void PSnoaccess( void );

APPKIT_EXTERN void PSnull( void );

APPKIT_EXTERN void PSpackedarray( void );

APPKIT_EXTERN void PSpop( void );

APPKIT_EXTERN void PSput( void );

APPKIT_EXTERN void PSputinterval( void );

APPKIT_EXTERN void PSrcheck(int *b);

APPKIT_EXTERN void PSreadonly( void );

APPKIT_EXTERN void PSroll(int n, int j);

APPKIT_EXTERN void PSscheck(int *b);

APPKIT_EXTERN void PSsearch(int *b);

APPKIT_EXTERN void PSshareddict( void );

APPKIT_EXTERN void PSstatusdict( void );

APPKIT_EXTERN void PSstore( void );

APPKIT_EXTERN void PSstring(int len);

APPKIT_EXTERN void PSstringwidth(const char *s, float *xp, float *yp);

APPKIT_EXTERN void PSsystemdict( void );

APPKIT_EXTERN void PSuserdict( void );

APPKIT_EXTERN void PSwcheck(int *b);

APPKIT_EXTERN void PSwhere(int *b);

APPKIT_EXTERN void PSxcheck(int *b);

#endif PSDATAOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psfontops.h generated from psfontops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSFONTOPS_H
#define PSFONTOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSFontDirectory( void );

APPKIT_EXTERN void PSISOLatin1Encoding( void );

APPKIT_EXTERN void PSSharedFontDirectory( void );

APPKIT_EXTERN void PSStandardEncoding( void );

APPKIT_EXTERN void PScachestatus(int *bsize, int *bmax, int *msize);

APPKIT_EXTERN void PScurrentcacheparams( void );

APPKIT_EXTERN void PScurrentfont( void );

APPKIT_EXTERN void PSdefinefont( void );

APPKIT_EXTERN void PSfindfont(const char *name);

APPKIT_EXTERN void PSmakefont( void );

APPKIT_EXTERN void PSscalefont(float size);

APPKIT_EXTERN void PSselectfont(const char *name, float scale);

APPKIT_EXTERN void PSsetcachedevice(float wx, float wy, float llx, float lly, float urx, float ury);

APPKIT_EXTERN void PSsetcachelimit(float n);

APPKIT_EXTERN void PSsetcacheparams( void );

APPKIT_EXTERN void PSsetcharwidth(float wx, float wy);

APPKIT_EXTERN void PSsetfont(int f);

APPKIT_EXTERN void PSundefinefont(const char *name);

#endif PSFONTOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psgstateops.h generated from psgstateops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSGSTATEOPS_H
#define PSGSTATEOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSconcat(const float m[]);

APPKIT_EXTERN void PScurrentdash( void );

APPKIT_EXTERN void PScurrentflat(float *flatness);

APPKIT_EXTERN void PScurrentgray(float *gray);

APPKIT_EXTERN void PScurrentgstate(int gst);

APPKIT_EXTERN void PScurrenthalftone( void );

APPKIT_EXTERN void PScurrenthalftonephase(int *x, int *y);

APPKIT_EXTERN void PScurrenthsbcolor(float *h, float *s, float *b);

APPKIT_EXTERN void PScurrentlinecap(int *linecap);

APPKIT_EXTERN void PScurrentlinejoin(int *linejoin);

APPKIT_EXTERN void PScurrentlinewidth(float *width);

APPKIT_EXTERN void PScurrentmatrix( void );

APPKIT_EXTERN void PScurrentmiterlimit(float *limit);

APPKIT_EXTERN void PScurrentpoint(float *x, float *y);

APPKIT_EXTERN void PScurrentrgbcolor(float *r, float *g, float *b);

APPKIT_EXTERN void PScurrentscreen( void );

APPKIT_EXTERN void PScurrentstrokeadjust(int *b);

APPKIT_EXTERN void PScurrenttransfer( void );

APPKIT_EXTERN void PSdefaultmatrix( void );

APPKIT_EXTERN void PSgrestore( void );

APPKIT_EXTERN void PSgrestoreall( void );

APPKIT_EXTERN void PSgsave( void );

APPKIT_EXTERN void PSgstate( void );

APPKIT_EXTERN void PSinitgraphics( void );

APPKIT_EXTERN void PSinitmatrix( void );

APPKIT_EXTERN void PSrotate(float angle);

APPKIT_EXTERN void PSscale(float x, float y);

APPKIT_EXTERN void PSsetdash(const float pat[], int size, float offset);

APPKIT_EXTERN void PSsetflat(float flatness);

APPKIT_EXTERN void PSsetgray(float gray);

APPKIT_EXTERN void PSsetgstate(int gst);

APPKIT_EXTERN void PSsethalftone( void );

APPKIT_EXTERN void PSsethalftonephase(int x, int y);

APPKIT_EXTERN void PSsethsbcolor(float h, float s, float b);

APPKIT_EXTERN void PSsetlinecap(int linecap);

APPKIT_EXTERN void PSsetlinejoin(int linejoin);

APPKIT_EXTERN void PSsetlinewidth(float width);

APPKIT_EXTERN void PSsetmatrix( void );

APPKIT_EXTERN void PSsetmiterlimit(float limit);

APPKIT_EXTERN void PSsetrgbcolor(float r, float g, float b);

APPKIT_EXTERN void PSsetscreen( void );

APPKIT_EXTERN void PSsetstrokeadjust(int b);

APPKIT_EXTERN void PSsettransfer( void );

APPKIT_EXTERN void PStranslate(float x, float y);

#endif PSGSTATEOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psioops.h generated from psioops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSIOOPS_H
#define PSIOOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSequals( void );

APPKIT_EXTERN void PSequalsequals( void );

APPKIT_EXTERN void PSbytesavailable(int *n);

APPKIT_EXTERN void PSclosefile( void );

APPKIT_EXTERN void PScurrentfile( void );

APPKIT_EXTERN void PSdeletefile(const char *filename);

APPKIT_EXTERN void PSecho(int b);

APPKIT_EXTERN void PSfile(const char *name, const char *access);

APPKIT_EXTERN void PSfilenameforall( void );

APPKIT_EXTERN void PSfileposition(int *pos);

APPKIT_EXTERN void PSflush( void );

APPKIT_EXTERN void PSflushfile( void );

APPKIT_EXTERN void PSprint( void );

APPKIT_EXTERN void PSprintobject(int tag);

APPKIT_EXTERN void PSpstack( void );

APPKIT_EXTERN void PSread(int *b);

APPKIT_EXTERN void PSreadhexstring(int *b);

APPKIT_EXTERN void PSreadline(int *b);

APPKIT_EXTERN void PSreadstring(int *b);

APPKIT_EXTERN void PSrenamefile(const char *oldfile, const char *newfile);

APPKIT_EXTERN void PSresetfile( void );

APPKIT_EXTERN void PSsetfileposition(int pos);

APPKIT_EXTERN void PSstack( void );

APPKIT_EXTERN void PSstatus(int *b);

APPKIT_EXTERN void PStoken(int *b);

APPKIT_EXTERN void PSwrite( void );

APPKIT_EXTERN void PSwritehexstring( void );

APPKIT_EXTERN void PSwriteobject(int tag);

APPKIT_EXTERN void PSwritestring( void );

#endif PSIOOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psmathops.h generated from psmathops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSMATHOPS_H
#define PSMATHOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSabs( void );

APPKIT_EXTERN void PSadd( void );

APPKIT_EXTERN void PSand( void );

APPKIT_EXTERN void PSatan( void );

APPKIT_EXTERN void PSbitshift(int shift);

APPKIT_EXTERN void PSceiling( void );

APPKIT_EXTERN void PScos( void );

APPKIT_EXTERN void PSdiv( void );

APPKIT_EXTERN void PSexp( void );

APPKIT_EXTERN void PSfloor( void );

APPKIT_EXTERN void PSidiv( void );

APPKIT_EXTERN void PSln( void );

APPKIT_EXTERN void PSlog( void );

APPKIT_EXTERN void PSmod( void );

APPKIT_EXTERN void PSmul( void );

APPKIT_EXTERN void PSneg( void );

APPKIT_EXTERN void PSround( void );

APPKIT_EXTERN void PSsin( void );

APPKIT_EXTERN void PSsqrt( void );

APPKIT_EXTERN void PSsub( void );

APPKIT_EXTERN void PStruncate( void );

APPKIT_EXTERN void PSxor( void );

#endif PSMATHOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psmatrixops.h generated from psmatrixops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSMATRIXOPS_H
#define PSMATRIXOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSconcatmatrix( void );

APPKIT_EXTERN void PSdtransform(float x1, float y1, float *x2, float *y2);

APPKIT_EXTERN void PSidentmatrix( void );

APPKIT_EXTERN void PSidtransform(float x1, float y1, float *x2, float *y2);

APPKIT_EXTERN void PSinvertmatrix( void );

APPKIT_EXTERN void PSitransform(float x1, float y1, float *x2, float *y2);

APPKIT_EXTERN void PStransform(float x1, float y1, float *x2, float *y2);

#endif PSMATRIXOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psmiscops.h generated from psmiscops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSMISCOPS_H
#define PSMISCOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSbanddevice( void );

APPKIT_EXTERN void PSframedevice( void );

APPKIT_EXTERN void PSnulldevice( void );

APPKIT_EXTERN void PSrenderbands( void );

#endif PSMISCOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psopstack.h generated from psopstack.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSOPSTACK_H
#define PSOPSTACK_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSgetboolean(int *it);

APPKIT_EXTERN void PSgetchararray(int size, char s[]);

APPKIT_EXTERN void PSgetfloat(float *it);

APPKIT_EXTERN void PSgetfloatarray(int size, float a[]);

APPKIT_EXTERN void PSgetint(int *it);

APPKIT_EXTERN void PSgetintarray(int size, int a[]);

APPKIT_EXTERN void PSgetstring(char *s);

APPKIT_EXTERN void PSsendboolean(int it);

APPKIT_EXTERN void PSsendchararray(const char s[], int size);

APPKIT_EXTERN void PSsendfloat(float it);

APPKIT_EXTERN void PSsendfloatarray(const float a[], int size);

APPKIT_EXTERN void PSsendint(int it);

APPKIT_EXTERN void PSsendintarray(const int a[], int size);

APPKIT_EXTERN void PSsendstring(const char *s);

#endif PSOPSTACK_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/pspaintops.h generated from pspaintops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSPAINTOPS_H
#define PSPAINTOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSashow(float x, float y, const char *s);

APPKIT_EXTERN void PSawidthshow(float cx, float cy, int c, float ax, float ay, const char *s);

APPKIT_EXTERN void PScopypage( void );

APPKIT_EXTERN void PSeofill( void );

APPKIT_EXTERN void PSerasepage( void );

APPKIT_EXTERN void PSfill( void );

APPKIT_EXTERN void PSimage( void );

APPKIT_EXTERN void PSimagemask( void );

APPKIT_EXTERN void PSkshow(const char *s);

APPKIT_EXTERN void PSrectfill(float x, float y, float w, float h);

APPKIT_EXTERN void PSrectstroke(float x, float y, float w, float h);

APPKIT_EXTERN void PSshow(const char *s);

APPKIT_EXTERN void PSshowpage( void );

APPKIT_EXTERN void PSstroke( void );

APPKIT_EXTERN void PSstrokepath( void );

APPKIT_EXTERN void PSueofill(const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void PSufill(const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void PSustroke(const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void PSustrokepath(const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void PSwidthshow(float x, float y, int c, const char *s);

APPKIT_EXTERN void PSxshow(const char *s, const float numarray[], int size);

APPKIT_EXTERN void PSxyshow(const char *s, const float numarray[], int size);

APPKIT_EXTERN void PSyshow(const char *s, const float numarray[], int size);

#endif PSPAINTOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/pspathops.h generated from pspathops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSPATHOPS_H
#define PSPATHOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSarc(float x, float y, float r, float angle1, float angle2);

APPKIT_EXTERN void PSarcn(float x, float y, float r, float angle1, float angle2);

APPKIT_EXTERN void PSarct(float x1, float y1, float x2, float y2, float r);

APPKIT_EXTERN void PSarcto(float x1, float y1, float x2, float y2, float r, float *xt1, float *yt1, float *xt2, float *yt2);

APPKIT_EXTERN void PScharpath(const char *s, int b);

APPKIT_EXTERN void PSclip( void );

APPKIT_EXTERN void PSclippath( void );

APPKIT_EXTERN void PSclosepath( void );

APPKIT_EXTERN void PScurveto(float x1, float y1, float x2, float y2, float x3, float y3);

APPKIT_EXTERN void PSeoclip( void );

APPKIT_EXTERN void PSeoviewclip( void );

APPKIT_EXTERN void PSflattenpath( void );

APPKIT_EXTERN void PSinitclip( void );

APPKIT_EXTERN void PSinitviewclip( void );

APPKIT_EXTERN void PSlineto(float x, float y);

APPKIT_EXTERN void PSmoveto(float x, float y);

APPKIT_EXTERN void PSnewpath( void );

APPKIT_EXTERN void PSpathbbox(float *llx, float *lly, float *urx, float *ury);

APPKIT_EXTERN void PSpathforall( void );

APPKIT_EXTERN void PSrcurveto(float x1, float y1, float x2, float y2, float x3, float y3);

APPKIT_EXTERN void PSrectclip(float x, float y, float w, float h);

APPKIT_EXTERN void PSrectviewclip(float x, float y, float w, float h);

APPKIT_EXTERN void PSreversepath( void );

APPKIT_EXTERN void PSrlineto(float x, float y);

APPKIT_EXTERN void PSrmoveto(float x, float y);

APPKIT_EXTERN void PSsetbbox(float llx, float lly, float urx, float ury);

APPKIT_EXTERN void PSsetucacheparams( void );

APPKIT_EXTERN void PSuappend(const char nums[], int n, const char ops[], int l);

APPKIT_EXTERN void PSucache( void );

APPKIT_EXTERN void PSucachestatus( void );

APPKIT_EXTERN void PSupath(int b);

APPKIT_EXTERN void PSviewclip( void );

APPKIT_EXTERN void PSviewclippath( void );

#endif PSPATHOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/pssysops.h generated from pssysops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSSYSOPS_H
#define PSSYSOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSbind( void );

APPKIT_EXTERN void PScountdictstack(int *n);

APPKIT_EXTERN void PScountexecstack(int *n);

APPKIT_EXTERN void PScurrentdict( void );

APPKIT_EXTERN void PScurrentpacking(int *b);

APPKIT_EXTERN void PScurrentshared(int *b);

APPKIT_EXTERN void PSdeviceinfo( void );

APPKIT_EXTERN void PSerrordict( void );

APPKIT_EXTERN void PSexec( void );

APPKIT_EXTERN void PSprompt( void );

APPKIT_EXTERN void PSquit( void );

APPKIT_EXTERN void PSrand( void );

APPKIT_EXTERN void PSrealtime(int *i);

APPKIT_EXTERN void PSrestore( void );

APPKIT_EXTERN void PSrrand( void );

APPKIT_EXTERN void PSrun(const char *filename);

APPKIT_EXTERN void PSsave( void );

APPKIT_EXTERN void PSsetpacking(int b);

APPKIT_EXTERN void PSsetshared(int b);

APPKIT_EXTERN void PSsrand( void );

APPKIT_EXTERN void PSstart( void );

APPKIT_EXTERN void PStype( void );

APPKIT_EXTERN void PSundef(const char *name);

APPKIT_EXTERN void PSusertime(int *milliseconds);

APPKIT_EXTERN void PSversion(int bufsize, char buf[]);

APPKIT_EXTERN void PSvmreclaim(int code);

APPKIT_EXTERN void PSvmstatus(int *level, int *used, int *maximum);

#endif PSSYSOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/pswinops.h generated from pswinops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSWINOPS_H
#define PSWINOPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSineofill(float x, float y, int *b);

APPKIT_EXTERN void PSinfill(float x, float y, int *b);

APPKIT_EXTERN void PSinstroke(float x, float y, int *b);

APPKIT_EXTERN void PSinueofill(float x, float y, const char nums[], int n, const char ops[], int l, int *b);

APPKIT_EXTERN void PSinufill(float x, float y, const char nums[], int n, const char ops[], int l, int *b);

APPKIT_EXTERN void PSinustroke(float x, float y, const char nums[], int n, const char ops[], int l, int *b);

APPKIT_EXTERN void PSwtranslation(float *x, float *y);

#endif PSWINOPS_H
/* /BinCache/AppKit/Symbols/AppKit-380.3.sym~4/AppKit.build/derived_src/DPSClient.subproj/psl2ops.h generated from psl2ops.psw
   by unix pswrap V1.009  Wed Apr 19 17:50:24 PDT 1989
 */

#ifndef PSL2OPS_H
#define PSL2OPS_H
#include <AppKit/AppKitDefines.h>

APPKIT_EXTERN void PSleftbracket( void );

APPKIT_EXTERN void PSrightbracket( void );

APPKIT_EXTERN void PSleftleft( void );

APPKIT_EXTERN void PSrightright( void );

APPKIT_EXTERN void PScshow(const char *s);

APPKIT_EXTERN void PScurrentcolor( void );

APPKIT_EXTERN void PScurrentcolorrendering( void );

APPKIT_EXTERN void PScurrentcolorspace( void );

APPKIT_EXTERN void PScurrentdevparams(const char *dev);

APPKIT_EXTERN void PScurrentglobal(int *b);

APPKIT_EXTERN void PScurrentoverprint(int *b);

APPKIT_EXTERN void PScurrentpagedevice( void );

APPKIT_EXTERN void PScurrentsystemparams( void );

APPKIT_EXTERN void PScurrentuserparams( void );

APPKIT_EXTERN void PSdefineresource(const char *category);

APPKIT_EXTERN void PSexecform( void );

APPKIT_EXTERN void PSfilter( void );

APPKIT_EXTERN void PSfindencoding(const char *key);

APPKIT_EXTERN void PSfindresource(const char *key, const char *category);

APPKIT_EXTERN void PSgcheck(int *b);

APPKIT_EXTERN void PSglobaldict( void );

APPKIT_EXTERN void PSGlobalFontDirectory( void );

APPKIT_EXTERN void PSglyphshow(const char *name);

APPKIT_EXTERN void PSlanguagelevel(int *n);

APPKIT_EXTERN void PSmakepattern( void );

APPKIT_EXTERN void PSproduct( void );

APPKIT_EXTERN void PSresourceforall(const char *category);

APPKIT_EXTERN void PSresourcestatus(const char *key, const char *category, int *b);

APPKIT_EXTERN void PSrevision(int *n);

APPKIT_EXTERN void PSrootfont( void );

APPKIT_EXTERN void PSserialnumber(int *n);

APPKIT_EXTERN void PSsetcolor( void );

APPKIT_EXTERN void PSsetcolorrendering( void );

APPKIT_EXTERN void PSsetcolorspace( void );

APPKIT_EXTERN void PSsetdevparams( void );

APPKIT_EXTERN void PSsetglobal(int b);

APPKIT_EXTERN void PSsetoverprint(int b);

APPKIT_EXTERN void PSsetpagedevice( void );

APPKIT_EXTERN void PSsetpattern(int patternDict);

APPKIT_EXTERN void PSsetsystemparams( void );

APPKIT_EXTERN void PSsetuserparams( void );

APPKIT_EXTERN void PSstartjob(int b, const char *password);

APPKIT_EXTERN void PSundefineresource(const char *key, const char *category);

#endif PSL2OPS_H
