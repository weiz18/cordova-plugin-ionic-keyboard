/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVIonicKeyboard.h"
#import <Cordova/CDVAvailability.h>
#import <Cordova/NSDictionary+CordovaPreferences.h>
#import <objc/runtime.h>

#ifndef __CORDOVA_3_2_0
#warning "The keyboard plugin is only supported in Cordova 3.2 or greater, it may not work properly in an older version. If you do use this plugin in an older version, make sure the HideKeyboardFormAccessoryBar and KeyboardShrinksView preference values are false."
#endif

@interface CDVIonicKeyboard () <UIScrollViewDelegate>

@property (nonatomic, readwrite, assign) BOOL keyboardIsVisible;
@property (nonatomic, readwrite) BOOL keyboardResizes;
@property (nonatomic, readwrite) BOOL isWK;
@property (nonatomic, readwrite) CGRect frame;

@end

@implementation CDVIonicKeyboard

- (id)settingForKey:(NSString *)key
{
    return [self.commandDelegate.settings objectForKey:[key lowercaseString]];
}

#pragma mark Initialize

- (void)pluginInitialize
{
    NSLog(@"CDVKeyboard: pluginInitialize");
    NSDictionary *settings = self.commandDelegate.settings;

    self.keyboardResizes = [settings cordovaBoolSettingForKey:@"KeyboardResizes" defaultValue:YES];
    self.hideFormAccessoryBar = [settings cordovaBoolSettingForKey:@"HideKeyboardFormAccessoryBar" defaultValue:YES];

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];

    [nc addObserver:self selector:@selector(onKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];

    // Prevent WKWebView to resize window
    BOOL isWK = self.isWK = [self.webView isKindOfClass:NSClassFromString(@"WKWebView")];
    if (!isWK) {
        NSLog(@"CDVKeyboard: WARNING!!: Keyboard plugin works better with WK");
    }
    BOOL isPre10_0_0 = !IsAtLeastiOSVersion(@"10.0");
    if (isWK && isPre10_0_0) {
        [nc removeObserver:self.webView name:UIKeyboardWillHideNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardWillShowNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardWillChangeFrameNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardDidChangeFrameNotification object:nil];
    }
}


#pragma mark Keyboard events

- (void)onKeyboardWillHide:(NSNotification *)sender
{
    NSLog(@"CDVKeyboard: onKeyboardWillHide");
    if (self.isWK) {
        [self setKeyboardHeight:0 delay:0.01];
    }
    [self.commandDelegate evalJs:@"Keyboard.fireOnHiding();"];
}

- (void)onKeyboardWillShow:(NSNotification *)note
{
    NSLog(@"CDVKeyboard: onKeyboardWillShow");
    if (self.isWK) {
        CGRect rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        double duration = [[note.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        double height = rect.size.height;
        [self setKeyboardHeight:height delay:duration/2.0];
        [[self.webView scrollView] setContentInset:UIEdgeInsetsZero];
    }
    [self.commandDelegate evalJs:@"Keyboard.fireOnShowing();"];
}

- (void)onKeyboardDidShow:(NSNotification *)sender
{
    NSLog(@"CDVKeyboard: onKeyboardDidShow");
    if (self.isWK) {
        [[self.webView scrollView] setContentInset:UIEdgeInsetsZero];
    }
    [self.commandDelegate evalJs:@"Keyboard.fireOnShow();"];
}

- (void)onKeyboardDidHide:(NSNotification *)sender
{
    NSLog(@"CDVKeyboard: onKeyboardDidHide");
    [self.commandDelegate evalJs:@"Keyboard.fireOnHide();"];
}

- (void)onKeyboardDidFrame:(NSNotification *)note
{
    CGRect rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double height = rect.size.height;
    [self.commandDelegate evalJs: [NSString stringWithFormat:@"Keyboard.fireOnFrameChange(%f);", height]];
}

- (void)setKeyboardHeight:(double)height delay:(NSTimeInterval)delay
{
    if(self.keyboardResizes) {
        CGRect f = [[UIScreen mainScreen] bounds];
        [self setWKFrame:CGRectMake(f.origin.x, f.origin.y, f.size.width, f.size.height - height) delay:delay];
    }
}

- (void)setWKFrame:(CGRect)frame delay:(NSTimeInterval)delay
{
    if(CGRectEqualToRect(self.frame, frame)) {
        return;
    }

    self.frame = frame;

    __weak CDVIonicKeyboard* weakSelf = self;
    SEL action = @selector(_updateFrame);
    [NSObject cancelPreviousPerformRequestsWithTarget:weakSelf selector:action object:nil];
    if (delay == 0) {
        [self _updateFrame];
    } else {
        [weakSelf performSelector:action withObject:nil afterDelay:delay];
    }
}

- (void)_updateFrame
{
    if(!CGRectEqualToRect(self.frame, self.webView.frame)) {
        NSLog(@"CDVKeyboard: updating WK frame");
        [self.webView setFrame:self.frame];
    }
}


#pragma mark HideFormAccessoryBar

static IMP UIOriginalImp;
static IMP WKOriginalImp;

- (void)setHideFormAccessoryBar:(BOOL)hideFormAccessoryBar
{
    if (hideFormAccessoryBar == _hideFormAccessoryBar) {
        return;
    }

    NSString* UIClassString = [@[@"UI", @"Web", @"Browser", @"View"] componentsJoinedByString:@""];
    NSString* WKClassString = [@[@"WK", @"Content", @"View"] componentsJoinedByString:@""];

    Method UIMethod = class_getInstanceMethod(NSClassFromString(UIClassString), @selector(inputAccessoryView));
    Method WKMethod = class_getInstanceMethod(NSClassFromString(WKClassString), @selector(inputAccessoryView));

    if (hideFormAccessoryBar) {
        UIOriginalImp = method_getImplementation(UIMethod);
        WKOriginalImp = method_getImplementation(WKMethod);

        IMP newImp = imp_implementationWithBlock(^(id _s) {
            return nil;
        });

        method_setImplementation(UIMethod, newImp);
        method_setImplementation(WKMethod, newImp);
    } else {
        method_setImplementation(UIMethod, UIOriginalImp);
        method_setImplementation(WKMethod, WKOriginalImp);
    }

    _hideFormAccessoryBar = hideFormAccessoryBar;
}


#pragma mark Plugin interface

- (void)hideFormAccessoryBar:(CDVInvokedUrlCommand *)command
{
    if (command.arguments.count > 0) {
        id value = [command.arguments objectAtIndex:0];
        if (!([value isKindOfClass:[NSNumber class]])) {
            value = [NSNumber numberWithBool:NO];
        }

        self.hideFormAccessoryBar = [value boolValue];
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:self.hideFormAccessoryBar]
                                callbackId:command.callbackId];
}

- (void)hide:(CDVInvokedUrlCommand *)command
{
    [self.webView endEditing:YES];
}

- (void)show:(CDVInvokedUrlCommand *)command
{
    NSLog(@"Showing keyboard not supported in iOS due to platform limitations.");
    NSLog(@"Instead, use input.focus(), and ensure that you have the following setting in your config.xml:");
    NSLog(@"    <preference name='KeyboardDisplayRequiresUserAction' value='false'/>");
}

#pragma mark dealloc

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
