#pragma once

#import <UIKit/UIKit.h>

// On-screen N64 controller drawn over the game, in the house style of the other ports
// (carried over from sote-ios's touch_controls.mm):
//  - a floating stick in the lower left (hidden until a thumb lands); drag anywhere else
//    to look (CBFD-Recompiled's mouse camera and aiming);
//  - A, B and the C buttons on the right, Z under L, L and R at the top;
//  - START at the bottom: a tap presses Start, a 0.45 s hold (its border fills) opens the
//    tray: GYRO, SENS, OPACITY, D-PAD;
//  - a tap on the open screen skips the playing cutscene.
// It shows while the game runs and hides in RecompFrontend's menus, whose taps reach SDL.
// Settings are kept in NSUserDefaults under iosTouch* keys.
@interface ConkerTouchControlsView : UIView
@end

// Adds the controls over SDL's window once it exists (call from the main thread).
void conker_touch_controls_install(void);
