#import <AppKit/AppKit.h>

#ifdef PROCESSVIEWER_TEST
static NSRect PVInspectorInitialTabContainerFrame(NSRect tabFrame,
                                                   NSRect splitBounds)
{
    tabFrame.origin.x = 0.0;
    tabFrame.origin.y = 0.0;
    tabFrame.size.width = splitBounds.size.width;
    return tabFrame;
}

static void PVInspectorResizeSubviewHeights(float *mainHeight, float *tabHeight,
                                             float splitHeight, float divider,
                                             float minMainHeight,
                                             float minTabHeight)
{
    float targetHeight = *mainHeight + *tabHeight + divider;
    float adjustedHeight = *mainHeight + splitHeight - targetHeight;

    if (adjustedHeight >= minMainHeight) {
        *mainHeight = adjustedHeight;
        targetHeight = splitHeight;
    } else {
        targetHeight -= *mainHeight - minMainHeight;
        *mainHeight = minMainHeight;
    }

    adjustedHeight = *tabHeight + splitHeight - targetHeight;
    *tabHeight = adjustedHeight >= minTabHeight ? adjustedHeight : minTabHeight;
}
#else
#define PVInspectorInitialTabContainerFrame(tabFrame, splitBounds) NSMakeRect(0.0, 0.0, (splitBounds).size.width, (tabFrame).size.height)
#define PVInspectorResizeSubviewHeights(mainHeightPointer, tabHeightPointer, splitHeightValue, dividerValue, minMainHeightValue, minTabHeightValue) do { float pvTargetHeight = *(mainHeightPointer) + *(tabHeightPointer) + (dividerValue); float pvAdjustedHeight = *(mainHeightPointer) + (splitHeightValue) - pvTargetHeight; if (pvAdjustedHeight >= (minMainHeightValue)) { *(mainHeightPointer) = pvAdjustedHeight; pvTargetHeight = (splitHeightValue); } else { pvTargetHeight -= *(mainHeightPointer) - (minMainHeightValue); *(mainHeightPointer) = (minMainHeightValue); } pvAdjustedHeight = *(tabHeightPointer) + (splitHeightValue) - pvTargetHeight; *(tabHeightPointer) = pvAdjustedHeight >= (minTabHeightValue) ? pvAdjustedHeight : (minTabHeightValue); } while (0)
#endif
