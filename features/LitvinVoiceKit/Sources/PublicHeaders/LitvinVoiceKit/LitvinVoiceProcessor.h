#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Litvin voice changer for recorded voice/video messages.
/// Mono 16-bit PCM, processed in place. Settings are re-read about twice a
/// second, so changing the voice in Litvin settings applies immediately.
@interface LitvinVoiceProcessor : NSObject

- (instancetype)initWithSampleRate:(double)sampleRate;
- (void)processInt16Samples:(int16_t *)samples count:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
