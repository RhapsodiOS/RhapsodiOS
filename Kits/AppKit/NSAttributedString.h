/*	
	NSAttributedString.h
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.

	This file defines Application Kit extensions to NSAttributedString and NSMutableAttributedString.
*/

#import <Foundation/Foundation.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSText.h>
#import <AppKit/AppKitDefines.h>
@class NSFileWrapper, NSURL;

/* Predefined character attributes for text. If the key is not in the dictionary, then use the default values as described below.
*/
APPKIT_EXTERN NSString *NSFontAttributeName;             /* NSFont, default Helvetica 12 */
APPKIT_EXTERN NSString *NSParagraphStyleAttributeName;   /* NSParagraphStyle, default defaultParagraphStyle */
APPKIT_EXTERN NSString *NSForegroundColorAttributeName;  /* NSColor, default blackColor */
APPKIT_EXTERN NSString *NSUnderlineStyleAttributeName;   /* int, default 0: no underline */
APPKIT_EXTERN NSString *NSSuperscriptAttributeName;      /* int, default 0 */
APPKIT_EXTERN NSString *NSBackgroundColorAttributeName;  /* NSColor, default nil: no background */
APPKIT_EXTERN NSString *NSAttachmentAttributeName;       /* NSTextAttachment, default nil */
APPKIT_EXTERN NSString *NSLigatureAttributeName;         /* int, default 1: default ligatures, 0: no ligatures, 2: all ligatures */
APPKIT_EXTERN NSString *NSBaselineOffsetAttributeName;   /* float, in points; offset from baseline, default 0 */
APPKIT_EXTERN NSString *NSKernAttributeName;             /* float, amount to modify default kerning, if 0, kerning off */
APPKIT_EXTERN NSString *NSLinkAttributeName;		 /* ??? id <NSTextLink>; link */

/* This defines currently supported values for NSUnderlineStyleAttributeName
*/
enum {
    NSNoUnderlineStyle = 0,
    NSSingleUnderlineStyle
};

// Combine these with the desired underline style to create the given effect.  In other words, to get strikethrough, set NSUnderlineStyleAttribute to (NSNoUnderlineStyle|NSUnderlineStrikethroughMask).  To get both strikethrough and an underline, skipping intermediate whitespace, use (NSSingleUnderlineStyle|NSUnderlineByWordMask|NSUnderlineStrikethroughMask).
APPKIT_EXTERN unsigned NSUnderlineByWordMask; 
APPKIT_EXTERN unsigned NSUnderlineStrikethroughMask;

@interface NSAttributedString (NSAttributedStringKitAdditions)

- (NSDictionary *)fontAttributesInRange:(NSRange)range; /* Attributes which should be copied/pasted with "copy font" */
- (NSDictionary *)rulerAttributesInRange:(NSRange)range; /* Attributes which should be copied/pasted with "copy ruler" */

- (BOOL)containsAttachments;

/* Returns NSNotFound if no line break location found in the specified range; otherwise returns the index of the first character that should go on the NEXT line.
*/
- (unsigned)lineBreakBeforeIndex:(unsigned)location withinRange:(NSRange)aRange;
- (NSRange)doubleClickAtIndex:(unsigned)location;
- (unsigned)nextWordFromIndex:(unsigned)location forward:(BOOL)isForward;

/* RTF/RTFD methods. If dict is not NULL, the init methods return a dictionary with various document-wide attributes. Similarly the RTF creation methods take an optional dictionary to allow writing out document-wide attributes. Currently supported attributes are @"PaperSize", @"LeftMargin", @"RightMargin", @"TopMargin", @"BottomMargin", and @"HyphenationFactor". The first one is an NSSize (in an NSValue), and the rest are all floats (in NSNumbers).
*/
- (id)initWithRTF:(NSData *)data documentAttributes:(NSDictionary **)dict;
- (id)initWithRTFD:(NSData *)data documentAttributes:(NSDictionary **)dict;
- (id)initWithPath:(NSString *)path documentAttributes:(NSDictionary **)dict;
- (id)initWithURL:(NSURL *)url documentAttributes:(NSDictionary **)dict;
- (id)initWithRTFDFileWrapper:(NSFileWrapper *)wrapper documentAttributes:(NSDictionary **)dict;
- (id)initWithHTML:(NSData *)data documentAttributes:(NSDictionary **)dict;
- (id)initWithHTML:(NSData *)data baseURL:(NSURL *)base documentAttributes:(NSDictionary **)dict;

- (NSData *)RTFFromRange:(NSRange)range documentAttributes:(NSDictionary *)dict;
- (NSData *)RTFDFromRange:(NSRange)range documentAttributes:(NSDictionary *)dict;
- (NSFileWrapper *)RTFDFileWrapperFromRange:(NSRange)range documentAttributes:(NSDictionary *)dict;

@end


@interface NSMutableAttributedString (NSMutableAttributedStringKitAdditions)

- (void)superscriptRange:(NSRange)range; /* Increment superscript, make font smaller */
- (void)subscriptRange:(NSRange)range; /* Decrement superscript, make font smaller  */
- (void)unscriptRange:(NSRange)range; /* Undo any superscripting, removing effect of any prior super- or sub-scripting of the range */
- (void)applyFontTraits:(NSFontTraitMask)traitMask range:(NSRange)range; /* Multiple trait changes OK */
- (void)setAlignment:(NSTextAlignment)alignment range:(NSRange)range;

/* Methods to "fix" attributes after changes. In the abstract class these are not called automatically. The range arguments are the ranges in the final string.
*/
- (void)fixAttributesInRange:(NSRange)range; /* Calls below fix... methods */
- (void)fixFontAttributeInRange:(NSRange)range; /* Make sure the font attribute covers the characters */
- (void)fixParagraphStyleAttributeInRange:(NSRange)range; /* Make sure the paragraph style is valid. Might touch beyond range! */
- (void)fixAttachmentAttributeInRange:(NSRange)range; /* Make sure there are no attachments on non-attachment characters */

@end
