#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block
           error:(NSError * _Nullable __autoreleasing * _Nullable)error {
	@try {
		block();
		return YES;
	} @catch (NSException *exception) {
		if (error) {
			NSString *reason = exception.reason ?: exception.name ?: @"Unknown Objective-C exception";
			*error = [NSError errorWithDomain:@"dev.idleberg.io.ExceptionCatcher"
			                             code:-1
			                         userInfo:@{
			                             NSLocalizedDescriptionKey: reason,
			                             @"ExceptionName": exception.name ?: @"Unknown"
			                         }];
		}
		return NO;
	}
}

@end
