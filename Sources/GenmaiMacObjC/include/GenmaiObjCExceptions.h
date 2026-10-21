// Objective-C helpers for the macOS IME that Swift cannot express.
//
// GenmaiImkInputController.mm wraps some IMKTextInput calls (attributesForCharacterIndex:lineHeightRectangle:)
// in @try/@catch because some host applications throw. Swift cannot catch Objective-C exceptions, so this
// helper runs a block and returns the exception, if any.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`; returns the NSException it raised, or nil.
NSException *_Nullable GenmaiTryObjC(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
