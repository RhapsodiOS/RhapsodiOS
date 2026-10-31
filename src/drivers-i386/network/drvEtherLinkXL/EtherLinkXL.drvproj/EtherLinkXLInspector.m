/* EtherLinkXLInspector.m */

#import "EtherLinkXLInspector.h"

#define INSPECTOR_NIB "EtherLinkXLInspector"
#define NIB_TYPE "nib"

static const char *mediaTable[] = {
    "10Base-T", "AUI", "Auto", "10Base-2", "100Base-TX", "100Base-FX",
    "MII"
};

@implementation EtherLinkXLInspector

- init
{
    char path[MAXPATHLEN];

    myBundle = [NXBundle bundleForClass:[self class]];
    [super init];

    if (![myBundle getPath:path forResource:INSPECTOR_NIB ofType:NIB_TYPE] ||
        ![NXApp loadNibFile:path owner:self withNames:NO]) {
        [self free];
        return nil;
    }

    [titleBox setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Connector Type", NULL)];
    [connectorPanel setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Select Connector", NULL)];
    [selectButton setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Connector", NULL)];
    [connectorBox setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Network Interface", NULL)];
    [cancelButtonCell setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Cancel", NULL)];
    [okButtonCell setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "OK", NULL)];
    [fullDuplexSwitch setTitle:NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Full Duplex", NULL)];
    return self;
}

- (void)_setInitialConnector
{
    const char *value;
    int i;
    id cell;

    currentConnector = 2;
    value = [table valueForStringKey:"Network Interface"];
    if (value != NULL) {
        for (i = 0; i <= 6; i++) {
            if (strcmp(value, mediaTable[i]) == 0) {
                currentConnector = i;
                break;
            }
        }
    }
    [connectorMatrix selectCellWithTag:currentConnector];
    cell = [connectorMatrix selectedCell];
    [connectorTitleField setStringValue:[cell title]];
    [connectorButton setImage:[cell image]];
}

- (void)_setInitialDuplex
{
    const char *value;

    fullDuplex = NO;
    value = [table valueForStringKey:"Full Duplex"];
    if (value != NULL && (value[0] == 'y' || value[0] == 'Y'))
        fullDuplex = YES;

    if (currentConnector == 1 || currentConnector == 3) {
        [fullDuplexSwitch setEnabled:NO];
        fullDuplex = NO;
    } else {
        [fullDuplexSwitch setEnabled:YES];
    }
    [fullDuplexSwitch setState:fullDuplex];
    [fullDuplexTitleField setStringValue:fullDuplex ?
        NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Full Duplex", NULL) : ""];
}

- setTable:(NXStringTable *)instance
{
    const char *value;

    [super setTable:instance];
    value = [table valueForStringKey:"Network Interface"];
    if (value == NULL || strcmp(value, "Auto") != 0) {
        [self setAccessoryView:connectorBox];
        [self _setInitialConnector];
        [self _setInitialDuplex];
    }
    return self;
}

- selectConnector:sender
{
    int previousConnector;
    BOOL previousDuplex;
    int selected;
    id cell;

    previousConnector = currentConnector;
    previousDuplex = fullDuplex;
    [connectorMatrix selectCellWithTag:currentConnector];
    [connectorPanel center];
    [connectorPanel makeKeyAndOrderFront:self];
    selected = [NXApp runModalFor:connectorPanel];
    [connectorPanel orderOut:self];
    if (selected) {
        selected = [connectorMatrix selectedTag];
        if (selected != currentConnector) {
            currentConnector = selected;
            [connectorBox display];
            cell = [connectorMatrix selectedCell];
            [connectorTitleField setStringValue:[cell title]];
            [connectorButton setImage:[cell image]];
            [table insertKey:"Network Interface"
                       value:NXCopyStringBuffer(mediaTable[currentConnector])];
            [connectorBox display];
            [connectorBox update];
        }
        if (fullDuplex != previousDuplex) {
            [table insertKey:"Full Duplex" value:NXCopyStringBuffer(fullDuplex ? "Yes" : "No")];
            [fullDuplexTitleField setStringValue:fullDuplex ?
                NXLoadLocalStringFromTableInBundle(NULL, myBundle, "Full Duplex", NULL) : ""];
        }
    } else {
        [connectorMatrix selectCellWithTag:previousConnector];
        currentConnector = previousConnector;
        fullDuplex = previousDuplex;
        if (fullDuplex)
            [self enableDuplex:self];
        else
            [self disableDuplex:self];
    }
    [fullDuplexSwitch setState:fullDuplex];
    return self;
}

- selectFullDuplex:sender
{
    fullDuplex = [fullDuplexSwitch state];
    return self;
}

- disableDuplex:sender
{
    fullDuplex = NO;
    [fullDuplexSwitch setEnabled:NO];
    [fullDuplexSwitch setState:NO];
    return self;
}

- enableDuplex:sender
{
    [fullDuplexSwitch setEnabled:YES];
    fullDuplex = [fullDuplexSwitch state];
    return self;
}

- ok:sender
{
    [NXApp stopModal:1];
    return self;
}

- cancel:sender
{
    [NXApp stopModal:0];
    return self;
}

@end
