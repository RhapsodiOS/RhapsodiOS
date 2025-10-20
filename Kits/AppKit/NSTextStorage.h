/* 
	NSTextStorage.h
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.

NSTextStorage is a semi-abstract subclass of NSMutableAttributedString. It implements change management (beginEditing/endEditing), verification of attributes, delegate handling, and layout management notification. The one aspect it does not implement is the actual attributed string storage --- this is left up to the subclassers, which need to override the two NSMutableAttributedString primitives:

  - (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str;
  - (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range;

These primitives should perform the change then call edited:range:changeInLength: to get everything else to happen.
   
*/

#import <Foundation/Foundation.h>
#import <AppKit/NSAttributedString.h>

@class NSLayoutManager;

/* These values are or'ed together in notifications to indicate what got changed.
*/
enum {
    NSTextStorageEditedAttributes = 1,
    NSTextStorageEditedCharacters = 2
};

@interface NSTextStorage : NSMutableAttributedString {
    /*All instance variables are private*/
    NSRange _editedRange;
    int _editedDelta;
    struct {
	unsigned int editedMask:8;
        unsigned int :8;
        unsigned int disabled:16;
    } _flags;
    NSMutableArray *_layoutManagers;
    id _delegate;
}

/* These methods manage the list of layout managers.
*/   
- (void)addLayoutManager:(NSLayoutManager *)obj;     /* Retains & calls setTextStorage: on the item */
- (void)removeLayoutManager:(NSLayoutManager *)obj;
- (NSArray *)layoutManagers;

/* If there are no outstanding beginEditing calls, this method calls processEditing to cause post-editing stuff to happen. This method has to be called by the primitives after changes are made. The range argument to edited:... is the range in the original string (before the edit).
*/
- (void)edited:(unsigned)editedMask range:(NSRange)range changeInLength:(int)delta;

/* This is called from edited:range:changeInLength: or endEditing. This method sends out NSTextStorageWillProcessEditing, then fixes the attributes, then sends out NSTextStorageDidProcessEditing, and finally notifies the layout managers of change with the textStorage:edited:range:changeInLength:invalidatedRange: method.
*/
- (void)processEditing;

/* These methods return information about the editing status. Especially useful when there are outstanding beginEditing calls or during processEditing... editedRange.location will be NSNotFound if nothing has been edited.
*/       
- (unsigned)editedMask;
- (NSRange)editedRange;
- (int)changeInLength;

/* Set/get the delegate
*/
- (void)setDelegate:(id)delegate;
- (id)delegate;

@end


/****  NSTextStorage delegate methods ****/

@interface NSObject (NSTextStorageDelegate)

/* These methods are sent during processEditing:. The receiver can use the callback methods editedMask, editedRange, and changeInLength to see what has changed. Although these methods can change the contents of the text storage, it's best if only the delegate did this.
*/
- (void)textStorageWillProcessEditing:(NSNotification *)notification;	/* Delegate can change the characters or attributes */
- (void)textStorageDidProcessEditing:(NSNotification *)notification;	/* Delegate can change the attributes */

@end

/**** Notifications ****/

APPKIT_EXTERN NSString *NSTextStorageWillProcessEditingNotification;
APPKIT_EXTERN NSString *NSTextStorageDidProcessEditingNotification;
