/*	NSHTTPRequest.m
	Private request object used by the PPC HTTP URL loader.
*/

#import <Foundation/NSHTTPRequest.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#if defined(__ppc__) || defined(__POWERPC__)

extern int _NSParseStringToGenericURLComponents(NSString *string,
    NSRange *scheme, NSRange *user, NSRange *password, NSRange *host,
    NSRange *port, NSRange *path, NSRange *parameters, NSRange *query,
    NSRange *fragment);

@implementation NSHTTPRequest

- initWithMethod:(NSString *)method URL:(NSURL *)url {
    if ((self = [super init]) != nil) {
        _req = [method copy];
        _url = [url copy];
        _headers = [[NSMutableDictionary alloc] init];
        _headerOrder = [[NSMutableArray alloc] init];
        _data = nil;
        _condition = -1;
    }
    return self;
}

- (void)dealloc {
    [_headers release];
    [_headerOrder release];
    [_data release];
    [_req release];
    [_url release];
    [_client release];
    [super dealloc];
}

- (void)addHeader:(NSString *)key value:(NSString *)value {
    if ([_headers objectForKey:key] == nil)
        [_headerOrder addObject:key];
    [_headers setObject:value forKey:key];
}

- (void)setData:(NSData *)data {
    [data retain];
    if (_data != nil)
        [_data release];
    _data = data;
}

- (NSData *)serializedRequest {
    NSString *absoluteString = [_url absoluteString];
    NSRange pathRange;
    NSString *path;
    NSMutableString *requestString;
    NSData *headerData;
    NSMutableData *requestData;
    unsigned index;
    unsigned count;

    (void)_NSParseStringToGenericURLComponents(absoluteString,
        NULL, NULL, NULL, NULL, NULL, &pathRange, NULL, NULL, NULL);
    if (pathRange.location == NSNotFound)
        path = @"/";
    else
        path = [absoluteString substringFromIndex:pathRange.location];

    requestString = [NSMutableString stringWithFormat:
        @"%@ %@ HTTP/1.0\r\n", _req, path];
    count = [_headerOrder count];
    for (index = 0; index < count; ++index) {
        NSString *key = [_headerOrder objectAtIndex:index];
        [requestString appendFormat:@"%@: %@\r\n", key,
            [_headers objectForKey:key]];
    }
    [requestString appendString:@"\r\n"];

    headerData = [requestString dataUsingEncoding:NSISOLatin1StringEncoding
        allowLossyConversion:YES];
    if (_data == nil)
        return headerData;

    requestData = [[NSMutableData alloc] initWithData:headerData];
    [requestData appendData:_data];
    return [requestData autorelease];
}

- (NSString *)requestMethod {
    return _req;
}

- (NSURL *)URL {
    return _url;
}

- (id)_client {
    return _client;
}

- (void)_setClient:(id)client {
    [client retain];
    [_client release];
    _client = client;
}

- (BOOL)fetchesURL:(NSURL *)url {
    if (![_req isEqualToString:@"GET"])
        return NO;
    return [url isEqual:_url];
}

- (int)_condition {
    return _condition;
}

- (void)_setCondition:(int)condition {
    _condition = condition;
}

@end

#endif
