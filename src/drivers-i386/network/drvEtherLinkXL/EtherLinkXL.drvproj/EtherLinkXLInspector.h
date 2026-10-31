/* EtherLinkXLInspector.h */

#import <appkit/appkit.h>
#import <driverkit/IODeviceInspector.h>

@interface EtherLinkXLInspector:IODeviceInspector
{
    id boundingBox;
    id cancelButtonCell;
    id connectorBox;
    id connectorButton;
    id connectorMatrix;
    id connectorPanel;
    id connectorPanelTitle;
    id connectorTitleField;
    id fullDuplexSwitch;
    id fullDuplexTitleField;
    id inspectorBox;
    id okButtonCell;
    id selectButton;
    id titleBox;
    NXBundle *myBundle;
    int currentConnector;
    BOOL fullDuplex;
}

- init;
- (void)_setInitialConnector;
- (void)_setInitialDuplex;
- setTable:(NXStringTable *)instance;
- selectConnector:sender;
- selectFullDuplex:sender;
- disableDuplex:sender;
- enableDuplex:sender;
- ok:sender;
- cancel:sender;
@end
