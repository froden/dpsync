//
//  AppDelegate.m
//  DPSync
//
//  Created by Frode Nerbråten on 22.04.14.
//  Copyright (c) 2014 Nerbraten. All rights reserved.
//

#import "AppDelegate.h"
#import "HsCocoa_stub.h"
#import "Digipostarkiv-Swift.h"

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    syncInProgress = false;
    runNumber = 0L;
    
    [self startSyncTimer];
}


- (IBAction)logout:(id)sender {
    [self stopSyncTimer];
    hsLogout();
}


- (void)handleURLEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *authCode = [self parseCode:url];
    int result = hsAccessToken("state", (char*)[authCode UTF8String]);
    
    if (result == 0) {
        [self startSyncTimer];
        [self.window close];
        [self.webView setMainFrameURL:@"about:blank"];
    } else {
        NSLog(@"Error from hs_accessToken: %i", result);
    }
}

- (NSString*)parseCode:(NSURL*)url {
    NSString* authCode;
    NSArray* urlComponents = [[url query] componentsSeparatedByString:@"&"];
    for (NSString *keyValuePair in urlComponents) {
        NSArray *pairComponents = [keyValuePair componentsSeparatedByString:@"="];
        if ([pairComponents count] == 2) {
            NSString *key = [pairComponents objectAtIndex:0];
            NSString *value = [pairComponents objectAtIndex:1];
            
            if ([key isEqualToString:@"code"]) {
                authCode = value;
            }
        }
    }

    return authCode;
}


- (IBAction)manualSync:(id)sender {
    if (hsLoggedIn()) {
        [self performSelectorInBackground:@selector(fullSync) withObject:false];
    } else {
        [self stopSyncTimer];
        [self performSelectorOnMainThread:@selector(login:) withObject:false waitUntilDone:false];
    }
}

- (void)sync {
    if (hsLoggedIn()) {
        [self performSelectorInBackground:@selector(detectChangeAndSync:) withObject:false];
    } else {
        [self stopSyncTimer];
        [self performSelectorOnMainThread:@selector(login:) withObject:false waitUntilDone:false];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    BOOL loggedIn = hsLoggedIn();
    SEL action = [item action];
    if (action == @selector(login:)) {
        [item setHidden:loggedIn];
        return !loggedIn;
    } else if (action == @selector(logout:)) {
        [item setHidden:!loggedIn];
        return loggedIn;
    } else {
        return YES;
    }
}

- (void)startSyncTimer {
    if (syncTimer == nil || ![syncTimer isValid]) {
        syncTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                    target:self
                                                    selector:@selector(sync)
                                                    userInfo:nil
                                                    repeats:true];
    }
    [syncTimer fire];
}

- (void)stopSyncTimer {
    if (syncTimer != nil && [syncTimer isValid]) {
        [syncTimer invalidate];
        syncTimer = nil;
    }
}


- (void)detectChangeAndSync:(NSTimer*)timer {
    if (syncInProgress) {
        return;
    }
    syncInProgress = true;
    BOOL checkRemote = runNumber++ % 6 == 0;
    int remoteSync = -1;
    if (checkRemote) {
        remoteSync = hsRemoteChanges();
    }
    if (remoteSync == 0) {
        NSLog(@"remote change detected");
    } else if (remoteSync == 1) {
        [self performSelectorOnMainThread:@selector(login:) withObject:false waitUntilDone:false];
    } else if (remoteSync == 99) {
        NSLog(@"Unhandled syncresult from hsRemoteChange");
    }
    BOOL localSync = !checkRemote && hsLocalChanges();
    if (localSync) {
        NSLog(@"local change detected");
    }
    if (localSync || remoteSync == 0) {
        [self fullSync];
    }
    syncInProgress = false;
}

- (void)fullSync {
    [statusItem setImage:statusImageActive];
    int result = hsSync();
    if (result != 0) {
        if (result == 1) {
            [self performSelectorOnMainThread:@selector(login:) withObject:false waitUntilDone:false];
        } else {
            //TODO: give up after n failures?
            NSLog(@"Unhandled syncresult: %i", result);
        }
    }
    [statusItem setImage:statusImage];
}

@end
