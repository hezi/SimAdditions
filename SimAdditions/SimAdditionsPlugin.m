//
//  SimAdditionsPlugin.m
//  SimAdditions
//
//  Created by Hezi Cohen on 1/23/14.
//  Copyright (c) 2014 Hezi Cohen. All rights reserved.
//

#import "SimAdditionsPlugin.h"

static NSNumber* g_operationUUID;

@implementation SimAdditionsPlugin
+ (void)load
{
    [[self sharedInstance] buildMenu];
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver:[self sharedInstance]
                                                        selector:@selector(didGetNotification:)
                                                            name:nil
                                                          object:nil];
}

+ (instancetype)sharedInstance
{
    static SimAdditionsPlugin* theInstance = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        theInstance = [[self alloc] init];
    });
    return theInstance;
}

- (id)indigoSessionController
{
    return [[NSClassFromString(@"GuiController") sharedInstance] performSelector:@selector(indigoSessionController)];
}

- (void)buildMenu
{
    NSMenuItem* menuItem = [[NSApp mainMenu] itemWithTitle:@"Debug"];
    if (menuItem) {
        [[menuItem submenu] addItem:[NSMenuItem separatorItem]];
        NSMenuItem* actionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Simulate Background Fetch"
                                                                action:@selector(backgroundFetchAction)
                                                         keyEquivalent:@""];
        [actionMenuItem setTarget:self];
        [[menuItem submenu] addItem:actionMenuItem];
    }
}

- (void)backgroundFetchAction
{
    id indigo = [self indigoSessionController];
    
    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[indigo methodSignatureForSelector:@selector(grandchildPid)]];
    [invocation setSelector:@selector(grandchildPid)];
    [invocation setTarget:indigo];
    
    [invocation invoke];
    
    NSUInteger length = [[invocation methodSignature] methodReturnLength];
    
    // If method is non-void:
    if (length > 0) {
        void* buffer = (void*)malloc(length);
        [invocation getReturnValue:buffer];
        int* result = buffer;
        int grandchildPid = *result;
        
        id appEvent = [NSNotification notificationWithName:@"com.apple.iphonesimulator.sendApplicationEvent"
                                                    object:Nil
                                                  userInfo:@{
                                                             @"applicationEventType" : @"applicationEventBackgroundFetch",
                                                             @"applicationPID" : @(grandchildPid),
                                                             @"operationUUID" : @(grandchildPid)
                                                             }];
        
        g_operationUUID = @(grandchildPid);
        
        [indigo performSelector:@selector(sendApplicationEvent:)
                     withObject:appEvent];
        
        free(result);
    }
}

- (void)didGetNotification:(NSNotification*)note
{
    NSString* name = [note name];
    NSDictionary* userInfo = [note userInfo];
    
    if (![name hasPrefix:@"com.apple.iphonesimulator."])
        return;
    
    if ([name isEqualToString:@"com.apple.iphonesimulator.operationResult"]) {
        if ([userInfo[@"operationUUID"] isEqualTo:g_operationUUID]) {
            if ([userInfo[@"error"] intValue] == -2) {
                NSAlert* alert = [NSAlert alertWithMessageText:@"Select to simulate fetch on:"
                                                 defaultButton:@"OK"
                                               alternateButton:@"Cancel"
                                                   otherButton:nil
                                     informativeTextWithFormat:@""];
                
                NSPopUpButton* comboBox = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
                
                NSArray *runningApps = [self runningSimulatorApps];
                for (NSDictionary *appData in runningApps) {
                    [comboBox addItemWithTitle:appData[@"name"]];
                }
                
                [alert setAccessoryView:comboBox];
                NSInteger button = [alert runModal];
                if (button == NSAlertDefaultReturn) {
                    int grandchildPid = [runningApps[[comboBox indexOfSelectedItem]][@"pid"] intValue];
                    
                    id appEvent = [NSNotification notificationWithName:@"com.apple.iphonesimulator.sendApplicationEvent"
                                                                object:Nil
                                                              userInfo:@{
                                                                         @"applicationEventType" : @"applicationEventBackgroundFetch",
                                                                         @"applicationPID" : @(grandchildPid),
                                                                         @"operationUUID" : @(grandchildPid)
                                                                         }];
                    
                    [[self indigoSessionController] performSelector:@selector(sendApplicationEvent:)
                                                         withObject:appEvent];
                    
                } else if (button == NSAlertAlternateReturn) {
                } else {
                }
            }
        }
    }
    
    NSString* object = [note object];
    NSLog(@"<%p>%s: object: %@ name: %@ userInfo: %@", self, __PRETTY_FUNCTION__, object, name, userInfo);
}

- (NSArray*)runningSimulatorApps
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/ps"];
    [task setArguments:@[@"ax"]];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data;
    data = [file readDataToEndOfFile];
    
    NSString *psString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+).*/iPhone Simulator/(.+)/Applications/(.+).app/(.+)"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    
    NSMutableArray *runningApps = [NSMutableArray array];
    [regex enumerateMatchesInString:psString options:0 range:NSMakeRange(0, psString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop)
     {
         NSRange range = [result rangeAtIndex:1];
         NSString *pid = [psString substringWithRange:range];

         range = [result rangeAtIndex:4];
         NSString *name = [psString substringWithRange:range];
         
         [runningApps addObject:@{@"pid":pid, @"name":name}];
     }];

    return runningApps;
}

@end
