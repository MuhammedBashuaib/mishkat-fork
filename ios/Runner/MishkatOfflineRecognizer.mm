#import "MishkatOfflineRecognizer.h"

#include <SherpaOnnxC/sherpa-onnx/c-api/c-api.h>
#include <algorithm>
#include <cstdint>
#include <exception>
#include <memory>
#include <vector>

namespace {
constexpr NSUInteger kModelBytes = 131652502;
constexpr NSUInteger kMaximumPCMBytes = 16000 * 2 * 15;

void SetError(NSError **error, NSInteger code, NSString *message) {
  if (error) {
    *error = [NSError errorWithDomain:@"MishkatOfflineRecognizer"
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey : message}];
  }
}
}  // namespace

@implementation MishkatOfflineRecognizer {
  const SherpaOnnxOfflineRecognizer *_recognizer;
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                               tokensPath:(NSString *)tokensPath
                                    error:(NSError **)error {
  self = [super init];
  if (!self) return nil;

  NSFileManager *files = NSFileManager.defaultManager;
  NSDictionary<NSFileAttributeKey, id> *modelAttributes =
      [files attributesOfItemAtPath:modelPath error:nil];
  NSDictionary<NSFileAttributeKey, id> *tokenAttributes =
      [files attributesOfItemAtPath:tokensPath error:nil];
  if (![files isReadableFileAtPath:modelPath] ||
      [modelAttributes[NSFileSize] unsignedLongLongValue] != kModelBytes ||
      ![files isReadableFileAtPath:tokensPath] ||
      [tokenAttributes[NSFileSize] unsignedLongLongValue] == 0) {
    SetError(error, 1, @"Bundled recitation model is missing or incomplete");
    return nil;
  }

  try {
    // Sherpa copies these configuration strings during creation. Their backing
    // NSStrings stay alive throughout the call; no temporary Swift C pointers.
    SherpaOnnxOfflineRecognizerConfig config = {};
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.nemo_ctc.model = modelPath.UTF8String;
    config.model_config.tokens = tokensPath.UTF8String;
    config.model_config.model_type = "nemo_ctc";
    config.model_config.provider = "cpu";
    config.model_config.num_threads = static_cast<int32_t>(std::max<NSInteger>(
        1, std::min<NSInteger>(4, NSProcessInfo.processInfo.activeProcessorCount / 2)));
    config.model_config.debug = 0;
    config.decoding_method = "greedy_search";
    _recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
    if (!_recognizer) {
      SetError(error, 2, @"Cannot initialize the bundled recitation model");
      return nil;
    }
  } catch (const std::exception &exception) {
    // Do not expose model internals or any recognized text through diagnostics.
    (void)exception;
    SetError(error, 2, @"Cannot initialize the bundled recitation model");
    return nil;
  } catch (...) {
    SetError(error, 2, @"Cannot initialize the bundled recitation model");
    return nil;
  }
  return self;
}

- (nullable NSString *)transcribePCM16:(NSData *)pcm error:(NSError **)error {
  if (pcm.length == 0 || pcm.length > kMaximumPCMBytes || pcm.length % 2 != 0) {
    SetError(error, 3, @"Expected nonempty mono PCM16 audio of at most 15 seconds");
    return nil;
  }
  if (!_recognizer) {
    SetError(error, 4, @"The recitation model has not been initialized");
    return nil;
  }

  // A disconnected/zeroed microphone buffer contains no acoustic evidence.
  // Avoid arbitrary CTC output for exact digital silence without introducing
  // an amplitude threshold or suppressing any nonzero speech sample.
  const auto *bytes = static_cast<const uint8_t *>(pcm.bytes);
  if (std::all_of(bytes, bytes + pcm.length, [](uint8_t value) { return value == 0; })) {
    return @"";
  }

  try {
    // Explicit byte assembly avoids alignment assumptions and host endianness.
    std::vector<float> samples(pcm.length / 2);
    for (NSUInteger index = 0; index < samples.size(); ++index) {
      const uint16_t bits = static_cast<uint16_t>(bytes[index * 2]) |
                            (static_cast<uint16_t>(bytes[index * 2 + 1]) << 8);
      samples[index] = static_cast<int16_t>(bits) / 32768.0f;
    }
    using Stream = std::unique_ptr<const SherpaOnnxOfflineStream,
                                   decltype(&SherpaOnnxDestroyOfflineStream)>;
    Stream stream(SherpaOnnxCreateOfflineStream(_recognizer),
                  &SherpaOnnxDestroyOfflineStream);
    if (!stream) {
      SetError(error, 4, @"Cannot create a recitation decoder stream");
      return nil;
    }
    SherpaOnnxAcceptWaveformOffline(stream.get(), 16000, samples.data(),
                                   static_cast<int32_t>(samples.size()));
    SherpaOnnxDecodeOfflineStream(_recognizer, stream.get());
    using Result = std::unique_ptr<const SherpaOnnxOfflineRecognizerResult,
                                   decltype(&SherpaOnnxDestroyOfflineRecognizerResult)>;
    Result result(SherpaOnnxGetOfflineStreamResult(stream.get()),
                  &SherpaOnnxDestroyOfflineRecognizerResult);
    if (!result || !result->text) {
      SetError(error, 4, @"The recitation decoder did not return a result");
      return nil;
    }
    NSString *text = [NSString stringWithUTF8String:result->text];
    if (!text) SetError(error, 4, @"The recitation decoder returned invalid text");
    return text;
  } catch (...) {
    SetError(error, 4, @"Cannot decode the recitation audio");
    return nil;
  }
}

- (void)dealloc {
  if (_recognizer) SherpaOnnxDestroyOfflineRecognizer(_recognizer);
}

@end
