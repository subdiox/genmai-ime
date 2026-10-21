#import "GenmaiObjCExceptions.h"

NSException *_Nullable GenmaiTryObjC(NS_NOESCAPE void (^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return exception;
  }
  return nil;
}
