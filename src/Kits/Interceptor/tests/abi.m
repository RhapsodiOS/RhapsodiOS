#import <Foundation/NSObject.h>
#import <stddef.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import "../Interceptor_types.h"
#import "../NSFramebuffer.h"
#import "../../../objc-1/objc-runtime.h"
#import "../../../objc-1/objc-class.h"
#import "test_support.h"

typedef struct {
    const char *name;
    const char *type;
    int offset;
} ExpectedIvar;

typedef struct {
    const char *name;
    long instanceSize;
    const ExpectedIvar *ivars;
    int ivarCount;
} ExpectedClass;

typedef struct {
    const char *className;
    const char *selector;
    const char *ppcType;
    const char *i386Type;
    int isClassMethod;
} ExpectedMethod;

#define IVAR(n, t, o) { n, t, o }
static const ExpectedIvar paletteIvars[] = { IVAR("_private", "^v", 4) };
static const ExpectedIvar screenIvars[] = { IVAR("_private", "^v", 4) };
static const ExpectedIvar shapeIvars[] = {
    IVAR("zone", "^{?}", 4), IVAR("_impl", "^v", 8)
};
static const ExpectedIvar simpleBitmapIvars[] = {
    IVAR("isPlanar", "c", 4), IVAR("hasAlpha", "c", 5),
    IVAR("bitsPerSample", "i", 8), IVAR("samplesPerPixel", "i", 12),
    IVAR("bitsPerPixel", "i", 16), IVAR("bytesPerRow", "i", 20),
    IVAR("bytesPerPlane", "i", 24), IVAR("numPlanes", "i", 28),
    IVAR("pixelsWide", "i", 32), IVAR("pixelsHigh", "i", 36),
    IVAR("colorSpace", "@\"NSString\"", 40), IVAR("colorSpaceCode", "i", 44),
    IVAR("data", "[5^v]", 48), IVAR("_bm_padding", "[8I]", 68),
    IVAR("_bm_private", "^v", 100)
};
static const ExpectedIvar framebufferIvars[] = {
    IVAR("interceptorClient", "@", 104), IVAR("screenNumber", "i", 108),
    IVAR("bounds", "{?=\"origin\"{?=\"x\"f\"y\"f}\"size\"{?=\"width\"f\"height\"f}}", 112),
    IVAR("pixelEncoding", "[64c]", 128), IVAR("publicPixelEncoding", "@\"NSString\"", 192),
    IVAR("driver", "[80c]", 196), IVAR("publicDriver", "@\"NSString\"", 276),
    IVAR("deviceSlot", "i", 280), IVAR("deviceUnit", "i", 284),
    IVAR("conversionTable", "^v", 288), IVAR("inverseConversionTable", "^v", 292),
    IVAR("isMapped", "c", 296), IVAR("_fb_padding1", "I", 300),
    IVAR("_palette", "^{?}", 304), IVAR("_paletteSize", "i", 308),
    IVAR("_fb_padding", "[5I]", 312), IVAR("_fb_private", "^v", 332)
};
static const ExpectedIvar interceptedRectIvars[] = {
    IVAR("rect", "{?=\"origin\"{?=\"x\"f\"y\"f}\"size\"{?=\"width\"f\"height\"f}}", 4),
    IVAR("screenRect", "{?=\"origin\"{?=\"x\"f\"y\"f}\"size\"{?=\"width\"f\"height\"f}}", 20),
    IVAR("windowNumber", "i", 36), IVAR("screen", "@", 40), IVAR("uniqueID", "I", 44),
    IVAR("target", "@", 48), IVAR("flags", "I", 52), IVAR("rectLock", "@\"NSConditionLock\"", 56),
    IVAR("isTotallyVisible", "c", 60), IVAR("isTotallyObscured", "c", 61),
    IVAR("moveInProgress", "c", 62), IVAR("isLocked", "c", 63),
    IVAR("tmpBitmap", "@\"NSSimpleBitmap\"", 64),
    IVAR("interceptorClient", "@\"NSInterceptorClient\"", 68),
    IVAR("screenRectShape", "@\"NSShape\"", 72), IVAR("_ir_padding", "[7I]", 76),
    IVAR("_ir_private", "^v", 104)
};
static const ExpectedIvar clientIvars[] = {
    IVAR("context", "^{?}", 4), IVAR("interceptedRects", "@\"NSMutableArray\"", 8),
    IVAR("listLock", "@\"NSConditionLock\"", 12), IVAR("portLock", "@\"NSLock\"", 16),
    IVAR("handlingThread", "@\"NSThread\"", 20), IVAR("_reserved0", "c", 24),
    IVAR("_notifyPort", "@\"NSPort\"", 28), IVAR("_padding", "[8I]", 32),
    IVAR("_private", "^v", 64)
};
static const ExpectedIvar enumeratorIvars[] = {
    IVAR("xloc", "^s", 4), IVAR("yloc", "^s", 8),
    IVAR("r", "{?=\"origin\"{?=\"x\"f\"y\"f}\"size\"{?=\"width\"f\"height\"f}}", 12)
};
static const ExpectedIvar directBitmapIvars[] = {
    IVAR("isBuffered", "c", 104), IVAR("isDirectMapped", "c", 105),
    IVAR("isUnobscured", "c", 106), IVAR("isLocked", "c", 107),
    IVAR("depthMismatch", "c", 108), IVAR("drawToBuffer", "c", 109),
    IVAR("updateNeeded", "c", 110), IVAR("framebuffer", "@", 112),
    IVAR("currentScreen", "i", 116), IVAR("newScreen", "i", 120),
    IVAR("interceptRect", "@", 124), IVAR("interceptClient", "@", 128),
    IVAR("copyFunc", "^?", 132), IVAR("window", "@", 136), IVAR("gWinNum", "i", 140),
    IVAR("rect", "{?=\"origin\"{?=\"x\"f\"y\"f}\"size\"{?=\"width\"f\"height\"f}}", 144),
    IVAR("_flushOnExposure", "i", 160), IVAR("_delegate", "@", 164),
    IVAR("_viewClip", "@", 168), IVAR("processingDelegate", "i", 172),
    IVAR("fbMode", "i", 176), IVAR("_naughtyFlags", "i", 180),
    IVAR("_screenIsDirty", "c", 184), IVAR("_dbm_pad2", "c", 185),
    IVAR("_dbm_pad3", "c", 186), IVAR("_dbm_pad4", "c", 187),
    IVAR("_dbm_padding", "[2I]", 188), IVAR("_dbm_private", "^v", 196)
};
static const ExpectedClass classes[] = {
    { "NSDirectBitmap", 200, directBitmapIvars, sizeof(directBitmapIvars)/sizeof(directBitmapIvars[0]) },
    { "NSDirectPalette", 8, paletteIvars, 1 },
    { "NSDirectScreen", 8, screenIvars, 1 },
    { "NSFramebuffer", 336, framebufferIvars, sizeof(framebufferIvars)/sizeof(framebufferIvars[0]) },
    { "NSInterceptedRect", 108, interceptedRectIvars, sizeof(interceptedRectIvars)/sizeof(interceptedRectIvars[0]) },
    { "NSInterceptorClient", 68, clientIvars, sizeof(clientIvars)/sizeof(clientIvars[0]) },
    { "_NSShapeEnumerator", 28, enumeratorIvars, 3 },
    { "NSShape", 12, shapeIvars, 2 },
    { "NSSimpleBitmap", 104, simpleBitmapIvars, sizeof(simpleBitmapIvars)/sizeof(simpleBitmapIvars[0]) },
    { "NSFramework_Interceptor", 0, 0, 0 }
};
static const ExpectedMethod methods[] = {
    { "NSShape", "intersectWithShape:", "v8@4:8@12", "v12@8:12@16", 0 },
    { "NSShape", "initFromRect:", "@20@4:8{?={?=ff}{?=ff}}12", "@24@8:12{?={?=ff}{?=ff}}16", 0 },
    { "NSFramebuffer", "addressForPoint:", "^v12@4:8{?=ff}12", "^v16@8:12{?=ff}16", 0 },
    { "NSDirectPalette", "setColor:atIndex:", "v12@4:8@12i16", "v16@8:12@16i20", 0 },
    { "NSSimpleBitmap", "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:",
      "@48@4:8^*12i16i20i24i28c32c43@44i48i52", "@48@8:12^*16i20i24i28i32c36c40@44i48i52", 0 },
    { "NSDirectPalette", "defaultColorPalette", "@4@4:8", "@4@8:12", 1 }
};

static int CheckClass(const struct objc_class *cls, const ExpectedClass *expected)
{
    int i;
    if (!cls || cls->instance_size != expected->instanceSize) return 0;
    if (expected->ivarCount &&
        (!cls->ivars || cls->ivars->ivar_count != expected->ivarCount)) return 0;
    if (!expected->ivarCount && cls->ivars && cls->ivars->ivar_count != 0) return 0;
    for (i = 0; i < expected->ivarCount; i++) {
        int j;
        int found = 0;
        for (j = 0; j < cls->ivars->ivar_count; j++) {
            struct objc_ivar *actual = &cls->ivars->ivar_list[j];
            if (!strcmp(actual->ivar_name, expected->ivars[i].name)) {
                found = actual->ivar_offset == expected->ivars[i].offset &&
                    !strcmp(actual->ivar_type, expected->ivars[i].type);
                break;
            }
        }
        if (!found) return 0;
    }
    return 1;
}

static int CheckMethodType(const char *actual, const char *expected)
{
    return actual && expected && strcmp(actual, expected) == 0;
}

static int HasMethodType(struct objc_class *cls, const char *selector,
                         const char *expected, int isClassMethod)
{
    struct objc_method_list *list;
    if (!cls) return 0;
    if (isClassMethod) cls = cls->isa;
    for (list = cls ? cls->methods : 0; list; list = list->method_next) {
        int i;
        for (i = 0; i < list->method_count; i++) {
            struct objc_method *method = &list->method_list[i];
            const char *name = sel_getName(method->method_name);
            if (name && !strcmp(name, selector))
                return CheckMethodType(method->method_types, expected);
        }
    }
    return 0;
}

int main(void)
{
    unsigned int i;
    TestCheck(TestLoadSelectedFramework() != 0,
              "loads the explicitly selected framework or thin dylib");
    TestCheck(InterceptorSuccess == 0 && InterceptorUnsupportedOperation == 6,
        "InterceptorReturn enum values");
    TestCheck(sizeof(InterceptedRectangle) == 36 && offsetof(InterceptedRectangle, flags) == 32,
        "InterceptedRectangle layout");
    TestCheck(sizeof(IntRect) == 16 && offsetof(IntRect, h) == 12, "IntRect layout");
    TestCheck(sizeof(InterceptorClientContext) == 12 &&
              offsetof(InterceptorClientContext, notifyPort) == 8,
              "InterceptorClientContext layout");
    TestCheck(sizeof(InterceptorNotification) == 108 &&
              offsetof(InterceptorNotification, args) == 44,
              "InterceptorNotification layout");
    TestCheck(sizeof(InterceptorReply) == 40 &&
              offsetof(InterceptorReply, replyCode) == 36,
              "InterceptorReply layout");
    TestCheck(sizeof(NSPaletteEntry) == 6 && offsetof(NSPaletteEntry, blue) == 4,
              "NSPaletteEntry layout");
    TestCheck(sizeof(NSRect) == 16, "NSRect layout");
    TestCheck(sizeof(pixel_encoding_t) == MAX_PIXEL_DESC_BITS, "pixel encoding width");
    for (i = 0; i < sizeof(classes)/sizeof(classes[0]); i++) {
        struct objc_class *cls = (struct objc_class *)objc_getClass(classes[i].name);
        TestCheck(CheckClass(cls, &classes[i]), classes[i].name);
    }
#if defined(__i386__)
    for (i = 0; i < sizeof(methods)/sizeof(methods[0]); i++) {
        struct objc_class *cls = (struct objc_class *)objc_getClass(methods[i].className);
        TestCheck(HasMethodType(cls, methods[i].selector, methods[i].i386Type,
                                methods[i].isClassMethod), methods[i].selector);
    }
#elif defined(__ppc__)
    for (i = 0; i < sizeof(methods)/sizeof(methods[0]); i++) {
        struct objc_class *cls = (struct objc_class *)objc_getClass(methods[i].className);
        TestCheck(HasMethodType(cls, methods[i].selector, methods[i].ppcType,
                                methods[i].isClassMethod), methods[i].selector);
    }
#else
    TestCheck(0, "ABI test must be compiled for ppc or i386");
#endif
    TestCheck(!CheckMethodType("v8@4:8@12", "v12@4:8@12"),
              "rejects an altered selector type encoding");
    {
        struct objc_class altered;
        ExpectedClass expected = { "altered fixture", 12, 0, 0 };
        memset(&altered, 0, sizeof(altered));
        altered.instance_size = 16;
        TestCheck(!CheckClass(&altered, &expected), "rejects an altered class-size fixture");
    }
    return TestFinish();
}
