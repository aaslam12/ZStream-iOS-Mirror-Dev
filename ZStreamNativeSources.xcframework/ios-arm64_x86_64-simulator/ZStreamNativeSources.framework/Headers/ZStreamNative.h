#ifndef ZSTREAM_NATIVE_H
#define ZSTREAM_NATIVE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZStreamNative : NSObject

// Aspera
+ (NSString *)asperaResolve:(NSString *)tmdb type:(NSString *)type season:(NSString *)season episode:(NSString *)ep;

// Aphrodite
+ (NSString *)aphroditeResolve:(NSString *)tmdb type:(NSString *)type season:(NSString *)season episode:(NSString *)ep;

// Stellar
+ (NSString *)stellarResolve:(NSString *)tmdb type:(NSString *)type season:(NSString *)season episode:(NSString *)ep;

// Fontaine - Native (Artemis)
+ (NSString *)nativeResolve:(NSString *)tmdb shelf:(NSString *)shelf slot:(NSString *)slot type:(NSString *)type;

// Fontaine - Aurora
+ (NSString *)auroraResolve:(NSString *)tmdb shelf:(NSString *)shelf slot:(NSString *)slot type:(NSString *)type
                      title:(NSString *)title year:(NSString *)year token:(NSString *)token variant:(NSString *)variant;

// Magnolia
+ (NSString *)magnoliaResolve:(NSString *)tmdb type:(NSString *)type season:(NSString *)season episode:(NSString *)ep;

// Nesterov
+ (NSString *)nesterovResolve:(NSString *)tmdb type:(NSString *)type season:(NSString *)season episode:(NSString *)ep;

// Tokyo
+ (NSString *)tokyoResolve:(NSString *)tmdb type:(NSString *)type season:(NSString *)season episode:(NSString *)ep;

// Crypto utilities
+ (NSData *)sha256:(NSData *)data;
+ (NSData *)hmacSha256:(NSData *)data withKey:(NSData *)key;
+ (NSData *)aesGcmEncrypt:(NSData *)plaintext withKey:(NSData *)key aad:(NSData *)aad;
+ (NSData *)aesGcmDecrypt:(NSData *)ciphertext withKey:(NSData *)key aad:(NSData *)aad;
+ (NSData *)randomBytes:(NSUInteger)length;

@end

NS_ASSUME_NONNULL_END

#endif
