#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Objective-C `@try/@catch` semantics to Swift. AVAudioEngine's
/// `connect(_:to:format:)`, `installTap`, `scheduleBuffer`, etc. raise
/// `NSException` when a device is in a bad state (e.g. a Bluetooth headset
/// that's claimed by another process or mid-codec-switch). Swift's
/// `do/try/catch` cannot catch those — the process crashes. Wrap the risky
/// call in this helper to convert the exception into a Swift-throwable error.
@interface ExceptionCatcher : NSObject

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block
           error:(NSError * _Nullable __autoreleasing * _Nullable)error
    NS_SWIFT_NAME(perform(_:));

@end

NS_ASSUME_NONNULL_END
