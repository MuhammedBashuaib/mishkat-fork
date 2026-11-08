#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A serial-queue-owned wrapper around the bundled Sherpa NeMo CTC engine.
/// Initialization and decoding must run off the main thread.
@interface MishkatOfflineRecognizer : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                               tokensPath:(NSString *)tokensPath
                                    error:(NSError *_Nullable *_Nullable)error
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Accepts at most 15 seconds of mono, 16 kHz, signed little-endian PCM16.
- (nullable NSString *)transcribePCM16:(NSData *)pcm
                               error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
