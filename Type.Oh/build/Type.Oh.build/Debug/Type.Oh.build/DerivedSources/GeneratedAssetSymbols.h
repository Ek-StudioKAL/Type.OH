#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"noob-noob420.Type-Oh";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "Claude" asset catalog image resource.
static NSString * const ACImageNameClaude AC_SWIFT_PRIVATE = @"Claude";

/// The "GPT" asset catalog image resource.
static NSString * const ACImageNameGPT AC_SWIFT_PRIVATE = @"GPT";

/// The "Gemini" asset catalog image resource.
static NSString * const ACImageNameGemini AC_SWIFT_PRIVATE = @"Gemini";

/// The "TyphOH.symbol" asset catalog image resource.
static NSString * const ACImageNameTyphOHSymbol AC_SWIFT_PRIVATE = @"TyphOH.symbol";

#undef AC_SWIFT_PRIVATE
