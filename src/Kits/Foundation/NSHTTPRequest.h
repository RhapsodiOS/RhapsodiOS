/*	NSHTTPRequest.h
	Private request object used by the PPC HTTP URL loader.
*/

#import <Foundation/NSObject.h>

@class NSData, NSMutableArray, NSMutableDictionary, NSString, NSURL;

#if defined(__ppc__) || defined(__POWERPC__)
@interface NSHTTPRequest : NSObject
{
    NSString *_req;
    NSURL *_url;
    NSMutableDictionary *_headers;
    NSMutableArray *_headerOrder;
    NSData *_data;
    id _client;
    int _condition;
}

- initWithMethod:(NSString *)method URL:(NSURL *)url;
- (void)addHeader:(NSString *)key value:(NSString *)value;
- (void)setData:(NSData *)data;
- (NSData *)serializedRequest;
- (NSString *)requestMethod;
- (NSURL *)URL;
- (id)_client;
- (void)_setClient:(id)client;
- (BOOL)fetchesURL:(NSURL *)url;
- (int)_condition;
- (void)_setCondition:(int)condition;

@end
#endif
