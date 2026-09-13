#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
NSArray<NSObject *> *KRAXChildren(NSObject *node);
NSArray<NSObject *> *KRAXOrderedChildren(NSObject *node);
BOOL KRAXFocusable(NSObject *node);
NSString * _Nullable KRAXIdentifier(NSObject *node);
NSString * _Nullable KRAXLabel(NSObject *node);
NSString * _Nullable KRAXValue(NSObject *node);
NSString * _Nullable KRAXRole(NSObject *node);
NSRect KRAXFrame(NSObject *node);
BOOL KRAXPress(NSObject *node);
BOOL KRAXFocused(NSObject *node);
BOOL KRAXEnabled(NSObject *node);
BOOL KRAXFocus(NSObject *node);
NS_ASSUME_NONNULL_END
