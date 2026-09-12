#import "AXBridge.h"

// SwiftUI AX nodes implement public selectors without declaring the full protocol.
NSArray<NSObject *> *KRAXChildren(NSObject *node) {
    if (![node respondsToSelector:@selector(accessibilityChildren)]) return @[];
    return [(id<NSAccessibility>)node accessibilityChildren] ?: @[];
}
NSString *KRAXIdentifier(NSObject *node) {
    if (![node respondsToSelector:@selector(accessibilityIdentifier)]) return nil;
    return [(id<NSAccessibility>)node accessibilityIdentifier];
}
NSString *KRAXLabel(NSObject *node) {
    id<NSAccessibility> element = (id<NSAccessibility>)node;
    if ([node respondsToSelector:@selector(accessibilityLabel)] && element.accessibilityLabel.length)
        return element.accessibilityLabel;
    if ([node respondsToSelector:@selector(accessibilityTitle)] && element.accessibilityTitle.length)
        return element.accessibilityTitle;
    return KRAXValue(node);
}
NSString *KRAXValue(NSObject *node) {
    if (![node respondsToSelector:@selector(accessibilityValue)]) return nil;
    id value = [(id<NSAccessibility>)node accessibilityValue];
    return [value isKindOfClass:NSString.class] ? value : nil;
}
NSString *KRAXRole(NSObject *node) {
    if (![node respondsToSelector:@selector(accessibilityRole)]) return nil;
    return [(id<NSAccessibility>)node accessibilityRole];
}
NSRect KRAXFrame(NSObject *node) {
    if (![node respondsToSelector:@selector(accessibilityFrame)]) return NSZeroRect;
    return [(id<NSAccessibility>)node accessibilityFrame];
}
BOOL KRAXPress(NSObject *node) {
    if (![node respondsToSelector:@selector(accessibilityPerformPress)]) return NO;
    return [(id<NSAccessibility>)node accessibilityPerformPress];
}
BOOL KRAXFocused(NSObject *node) {
    if (![node respondsToSelector:@selector(isAccessibilityFocused)]) return NO;
    return [(id<NSAccessibility>)node isAccessibilityFocused];
}
BOOL KRAXEnabled(NSObject *node) {
    if (![node respondsToSelector:@selector(isAccessibilityEnabled)]) return NO;
    return [(id<NSAccessibility>)node isAccessibilityEnabled];
}
BOOL KRAXFocus(NSObject *node) {
    if (![node respondsToSelector:@selector(setAccessibilityFocused:)]) return NO;
    [(id<NSAccessibility>)node setAccessibilityFocused:YES];
    return KRAXFocused(node);
}
