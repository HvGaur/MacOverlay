#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Carbon/Carbon.h> // ✅ Import Carbon for global hotkeys

@interface OverlayWindow : NSWindow
@end

@implementation OverlayWindow
- (BOOL)canBecomeKeyWindow { return NO; }
@end

OverlayWindow *window = nil;

// Toggle overlay visibility
void toggleOverlay() {
    if (window.isVisible) {
        [window orderOut:nil]; // Hide overlay
    } else {
        [window orderFront:nil]; // Show overlay
    }
}

// Hotkey event handler
OSStatus hotkeyCallback(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    toggleOverlay();
    return noErr;
}

// Register global hotkey (Cmd + Shift + O)
void registerGlobalHotkey() {
    EventHotKeyRef hotkeyRef;
    EventHotKeyID hotkeyID;
    hotkeyID.signature = 'htk1';
    hotkeyID.id = 1;

    // Cmd + Shift + O (31 = "O" key)
    RegisterEventHotKey(31, cmdKey | shiftKey, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef);

    // Set up event handler
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    InstallApplicationEventHandler(&hotkeyCallback, 1, &eventType, NULL, NULL);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];

        // Create overlay window
        NSRect screenFrame = [[NSScreen mainScreen] frame];
        window = [[OverlayWindow alloc] initWithContentRect:screenFrame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

        [window setLevel:NSScreenSaverWindowLevel]; // Always on top
        [window setOpaque:NO];
//        [window setBackgroundColor:[NSColor clearColor]];
        [window setBackgroundColor:[[NSColor redColor] colorWithAlphaComponent:0.3]];
        [window setIgnoresMouseEvents:YES];
        [window setSharingType:NSWindowSharingNone];

        // Metal Layer Setup
        CAMetalLayer *metalLayer = [CAMetalLayer layer];
        NSView *contentView = [[NSView alloc] initWithFrame:screenFrame];
        [contentView setLayer:metalLayer];
        [contentView setWantsLayer:YES];
        [window setContentView:contentView];

        [window orderFront:nil]; // Show overlay initially

        // ✅ Register global hotkey (Cmd + Shift + O)
        registerGlobalHotkey();

        [app run];
    }
    return 0;
}
