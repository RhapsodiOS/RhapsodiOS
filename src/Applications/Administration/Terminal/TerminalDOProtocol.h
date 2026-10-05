/*	TerminalDOProtocol.h
        Distributed objects services for Terminal.app
        Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

typedef enum {
	TSWindowNone = 0,
	TSWindowIdle = 2,
	TSWindowNew = 4,
	TSWindowDedicated = 8
	} TSWindowType;

typedef enum {
	TSShellNone = 1,
	TSShellBourne = 2,
	TSShellDefault = 4,
	TSShellFastC = 8
	} TSShellType;

typedef enum {
	TSCloseOnExit = 0,
	TSCloseUnlessError = 1,
	TSDontCloseOnExit = 2
	} TSExitAction;

@class NSData, NSDictionary, NSString;
@protocol TSTerminalDOServices

// indicates the version implemented
- (int)protocolVersion;

// run in a new window, using fast c shell
- (void)runCommand:(NSString *)cmdString
	windowTitle:(NSString *)winTitle;

// run command in a specified window
- (void)runCommand:(NSString *)cmdString
	windowType: (TSWindowType)winType
	windowHandle: (inout int *)myHandle
	shellType:(TSShellType)shellType
        windowTitle:(NSString *)winTitle
	returnCode:(out int *)retCode;

// run in background using fast c shell, return stdout
- (void)runCommand:(NSString *)cmdString
	inputData:(NSData *)inputData		// an NSData object for stdin
	outputData:(NSData **)outputData	// a pointer to an NSData object
	waitForReturn:(BOOL)shouldWait		// synchronous even if no output data?
	directory:(NSString *)workingDir	// where to cd before execution
	returnCode:(out int *)retCode;

// the full form, all others invoke this
- (void)runCommand:(NSString *)cmdString
	inputData:(NSData *)inputData
	outputData:(NSData **)outputData
	errorData:(NSData **)errorData
	waitForReturn:(BOOL)shouldWait		// synchronous even if no out data?
	windowType: (TSWindowType)winType
	windowHandle: (inout int *)myHandle
	exitAction: (TSExitAction)exitAction
	shellType:(TSShellType)shellType
	windowTitle:(NSString *)winTitle
	directory:(NSString *)workingDir
	environment:(NSDictionary *)environment
	returnCode:(out int *)retCode;

@end
