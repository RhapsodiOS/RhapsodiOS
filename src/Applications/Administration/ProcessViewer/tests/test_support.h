#import <Foundation/Foundation.h>
#import <AppKit/NSTableHeaderView.h>
#include <sys/types.h>

void PVCheck(BOOL condition, const char *expression, const char *file, int line);
void PVCheckObjectsEqual(id actual, id expected, const char *expression,
                         const char *file, int line);
int PVFinish(void);
void PVTestControllerReset(NSString *userName);
void PVTestControllerQueueAlertResponse(int response);
unsigned int PVTestControllerAlertCount(void);
id PVTestControllerAlertAtIndex(unsigned int index);
unsigned int PVTestControllerSignalCount(void);
pid_t PVTestControllerSignalPidAtIndex(unsigned int index);
int PVTestControllerSignalAtIndex(unsigned int index);
NSString *PVTestCurrentUserName(void);
int PVTestRunAlertPanel(NSString *title, NSString *message,
                        NSString *defaultButton, NSString *alternateButton,
                        NSString *otherButton, id argument1, id argument2);
int PVTestSendSignal(pid_t pid, int signalNumber);
void PVTestControllerSetSavePanel(id panel);
id PVTestControllerSavePanel(void);
void PVTestBeep(void);
unsigned int PVTestBeepCount(void);
void PVTestShowSystemInfoPanel(NSDictionary *options, SEL command, id sender);
NSDictionary *PVTestSystemInfoPanelOptions(void);
SEL PVTestSystemInfoPanelCommand(void);
id PVTestSystemInfoPanelSender(void);
void PVTestRegisterDefaults(NSDictionary *defaults);
NSDictionary *PVTestRegisteredDefaults(void);
void PVTestInstallProcessTableHeaderViewClass(NSTableHeaderView *headerView);
void PVTestRunPrintOperationWithView(id view);
id PVTestPrintOperationView(void);

#define PV_CHECK(expression) \
    PVCheck((expression), #expression, __FILE__, __LINE__)
#define PV_CHECK_OBJECTS_EQUAL(actual, expected) \
    PVCheckObjectsEqual((actual), (expected), #actual " == " #expected, __FILE__, __LINE__)
