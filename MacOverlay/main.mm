#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Carbon/Carbon.h>
#import <CoreText/CoreText.h>
#import <Vision/Vision.h>


@interface OverlayWindow : NSWindow
@end

@implementation OverlayWindow
- (BOOL)canBecomeKeyWindow { return NO; }
@end

OverlayWindow *window = nil;
CATextLayer *textLayer = nil; // Text layer reference
NSScrollView *scrollView = nil;
NSTextView *textView = nil;

// Function to update overlay text
void updateOverlayText(NSString *newText) {
    dispatch_async(dispatch_get_main_queue(), ^{
        textView.string = newText;
        NSPoint topPoint = NSMakePoint(0, [[textView textStorage] size].height);
        [textView scrollPoint:topPoint]; // Scroll to top automatically
    });
}

// Toggle overlay visibility
void toggleOverlay() {
    if (window.isVisible) {
        [window orderOut:nil];
    } else {
        [window orderFront:nil];
    }
}



NSString* extractTextFromScreenshot() {
    NSString *filePath = [NSString stringWithFormat:@"%@/Desktop/screenshot.png", NSHomeDirectory()];
    NSURL *imageURL = [NSURL fileURLWithPath:filePath];

    CIImage *ciImage = [CIImage imageWithContentsOfURL:imageURL];
    if (!ciImage) {
        NSLog(@"[ERROR] Could not load screenshot.");
        return nil;
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:ciImage options:@{}];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;

    NSError *error;
    [handler performRequests:@[request] error:&error];

    if (error) {
        NSLog(@"[ERROR] OCR failed: %@", error.localizedDescription);
        return nil;
    }

    NSMutableString *extractedText = [NSMutableString string];

    for (VNRecognizedTextObservation *observation in request.results) {
        if ([observation respondsToSelector:@selector(topCandidates:)]) {  //  Ensure method exists
            NSArray<VNRecognizedText *> *candidates = [observation topCandidates:1]; // Correct way
            if (candidates.count > 0) {
                [extractedText appendFormat:@"%@\n", candidates.firstObject.string];
            }
        } else {
            NSLog(@"[ERROR] topCandidates: method not available.");
        }
    }

    NSLog(@"[EXTRACTED TEXT]\n%@", extractedText);
    return extractedText;
}



void solveCodeFromScreenshot() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        updateOverlayText(@"Processing screenshot...");

        NSString *scriptPath = @"/Users/harshvardhangaur/Desktop/gemini_solver.py";
        NSString *extractedText = extractTextFromScreenshot();

        if (!extractedText || [extractedText length] == 0) {
            NSLog(@"[ERROR] No text extracted from screenshot.");
            dispatch_async(dispatch_get_main_queue(), ^{
                updateOverlayText(@"ERROR: No text extracted from screenshot.");
            });
            return;
        }

        // Instruction for Gemini
        NSString *instruction = @"Extract a problem statement/error code from this text and ignore all other useless information. "
                                "Give the solution in Java. Just give code, nothing else.\n\n";
        NSString *finalPrompt = [instruction stringByAppendingString:extractedText];

        dispatch_async(dispatch_get_main_queue(), ^{
            updateOverlayText([NSString stringWithFormat:@"Extracted text:\n%@\n\nSending to solver...", extractedText]);
        });

        // No file writing - Pass input via pipe
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/local/opt/python@3.12/bin/python3";
        task.arguments = @[scriptPath];

        NSPipe *inputPipe = [NSPipe pipe];
        NSPipe *outputPipe = [NSPipe pipe];

        task.standardInput = inputPipe;
        task.standardOutput = outputPipe;
        task.standardError = outputPipe;

        NSFileHandle *inputHandle = [inputPipe fileHandleForWriting];
        NSFileHandle *outputHandle = [outputPipe fileHandleForReading];

        @try {
            [task launch];

            // Send prompt text via pipe
            [inputHandle writeData:[finalPrompt dataUsingEncoding:NSUTF8StringEncoding]];
            [inputHandle closeFile];

            NSData *data = [outputHandle readDataToEndOfFile];
            NSString *solution = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            NSLog(@"[DEBUG] Solution Output:\n%@", solution);

            if (!solution || [solution length] == 0) {
                NSLog(@"[ERROR] No solution received.");
                dispatch_async(dispatch_get_main_queue(), ^{
                    updateOverlayText(@"ERROR: No solution received from Python script.");
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                updateOverlayText([NSString stringWithFormat:@"SOLUTION:\n\n%@", solution]);
            });
        } @catch (NSException *exception) {
            NSLog(@"[ERROR] Exception while running Python script: %@", exception.reason);
            dispatch_async(dispatch_get_main_queue(), ^{
                updateOverlayText([NSString stringWithFormat:@"ERROR: Failed to run Python script.\n%@", exception.reason]);
            });
        }
    });
}


// Function to capture a screenshot
void captureScreenshot() {
    updateOverlayText(@"Taking screenshot...");
    NSString *filePath = [NSString stringWithFormat:@"%@/Desktop/screenshot.png", NSHomeDirectory()];

    NSLog(@"[DEBUG] Attempting to save screenshot to: %@", filePath);

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/screencapture"];
//    [task setArguments:@[@"-i", filePath]];
    [task setArguments:@[@"-x", filePath]];

    @try {
        [task launch];
        [task waitUntilExit];

        if ([task terminationStatus] == 0) {
            NSLog(@"[SUCCESS] Screenshot saved to: %@", filePath);
            updateOverlayText(@"Screenshot captured successfully. Extracting text...");
            
            // Call directly from here to ensure the flow continues
            solveCodeFromScreenshot();
        } else {
            NSLog(@"[ERROR] Screenshot failed. Status: %d", [task terminationStatus]);
            updateOverlayText([NSString stringWithFormat:@"ERROR: Screenshot failed with status: %d", [task terminationStatus]]);
        }
    } @catch (NSException *exception) {
        NSLog(@"[CRASH] Screenshot error: %@", exception.reason);
        updateOverlayText([NSString stringWithFormat:@"ERROR: Screenshot failed: %@", exception.reason]);
    }
}

// Hotkey event handler
OSStatus hotkeyCallback(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotkeyID;
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotkeyID), NULL, &hotkeyID);

    if (hotkeyID.id == 1) {
        toggleOverlay();
    } else if (hotkeyID.id == 2) {
        captureScreenshot();
    } else if (hotkeyID.id == 3) {
        NSLog(@"[INFO] Exit hotkey pressed. Closing app.");
        exit(0);
    }

    return noErr;
}

// Register global hotkeys
void registerGlobalHotkeys() {
    EventHotKeyRef hotkeyRef1, hotkeyRef2, hotkeyRef3;
    EventHotKeyID hotkeyID1 = {'htk1', 1};
    EventHotKeyID hotkeyID2 = {'htk2', 2};
    EventHotKeyID hotkeyID3 = {'htk3', 3};

    RegisterEventHotKey(31, cmdKey | shiftKey, hotkeyID1, GetApplicationEventTarget(), 0, &hotkeyRef1); // Cmd + Shift + O
    RegisterEventHotKey(1, cmdKey | shiftKey, hotkeyID2, GetApplicationEventTarget(), 0, &hotkeyRef2);  // Cmd + Shift + S
    RegisterEventHotKey(7, cmdKey | shiftKey, hotkeyID3, GetApplicationEventTarget(), 0, &hotkeyRef3);  // Cmd + Shift + X (Exit)

    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    InstallApplicationEventHandler(&hotkeyCallback, 1, &eventType, NULL, NULL);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];

        NSScreen *mainScreen = [NSScreen mainScreen];
        NSRect screenFrame = [mainScreen frame];

        CGFloat overlayWidth = screenFrame.size.width * 0.40;
        CGFloat overlayHeight = screenFrame.size.height * 0.75;
        NSRect overlayFrame = NSMakeRect(50, (screenFrame.size.height - overlayHeight) / 2, overlayWidth, overlayHeight);

        // Create the overlay window
        window = [[OverlayWindow alloc] initWithContentRect:overlayFrame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

//        [window setLevel:NSScreenSaverWindowLevel];
        [window setLevel:NSFloatingWindowLevel];
        [window setOpaque:NO];
        [window setBackgroundColor:[[NSColor blackColor] colorWithAlphaComponent:0.5]];
        [window setIgnoresMouseEvents:YES];
        [window setSharingType:NSWindowSharingNone];

        // Scrollable text area
        NSRect scrollFrame = NSMakeRect(10, 10, overlayWidth - 20, overlayHeight - 20);
        scrollView = [[NSScrollView alloc] initWithFrame:scrollFrame];
        [scrollView setHasVerticalScroller:YES];
        [scrollView setDrawsBackground:NO];

        textView = [[NSTextView alloc] initWithFrame:scrollFrame];
        textView.editable = NO;
        textView.selectable = YES;
        textView.textColor = [NSColor whiteColor];
//        textView.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.0];
        textView.backgroundColor = [NSColor clearColor];
        textView.font = [NSFont fontWithName:@"JetBrains Mono" size:16];

        [scrollView setDocumentView:textView];
        [window.contentView addSubview:scrollView];

        [window orderFront:nil];

        registerGlobalHotkeys();
        
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * (NSEvent *event) {
            if ((event.modifierFlags & NSEventModifierFlagCommand) &&
                (event.modifierFlags & NSEventModifierFlagShift) &&
                event.keyCode == 1) { // "S" Key

                solveCodeFromScreenshot();
                return nil; // Prevents further key propagation
            }
            return event;
        }];
        
        updateOverlayText(@"Overlay initialized and ready.\nUse Cmd+Shift+S to capture and process a screenshot.");
        [window makeKeyAndOrderFront:nil]; // Make sure window is visible

        [app run];
    }
    return 0;
}
