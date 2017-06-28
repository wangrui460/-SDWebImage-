/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Jamie Pinkham
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <TargetConditionals.h>

// SDWebImage不支持垃圾回收机制，垃圾回收(Gargage-collection)是Objective-c提供的一种自动内存回收机制。
// 在iPad/iPhone环境中不支持垃圾回收功能。 当启动这个功能后，所有的retain,autorelease,release和dealloc方法都将被系统忽略。
#ifdef __OBJC_GC__
    #error SDWebImage does not support Objective-C Garbage Collection
#endif


// 该指令主要用于判断当前平台是不是MAC，单纯使用TARGET_OS_MAC是不靠谱的。这样判断的缺点是，当Apple出现新的平台时，判断条件要修改
#if !TARGET_OS_IPHONE && !TARGET_OS_IOS && !TARGET_OS_TV && !TARGET_OS_WATCH
    #define SD_MAC 1
#else
    #define SD_MAC 0
#endif

// iOS 和 tvOS 是非常相似的，UIKit在这两个平台中都存在，但是watchOS在使用UIKit时，是受限的。
// 因此我们定义SD_UIKIT为真的条件是iOS 和 tvOS这两个平台。至于为什么要定义SD_UIKIT后边会解释的。
#if TARGET_OS_IOS || TARGET_OS_TV
    #define SD_UIKIT 1
#else
    #define SD_UIKIT 0
#endif

// iOS
#if TARGET_OS_IOS
    #define SD_IOS 1
#else
    #define SD_IOS 0
#endif

// tvOS
#if TARGET_OS_TV
    #define SD_TV 1
#else
    #define SD_TV 0
#endif

// watchOS
#if TARGET_OS_WATCH
    #define SD_WATCH 1
#else
    #define SD_WATCH 0
#endif


#if SD_MAC
    #import <AppKit/AppKit.h>
    #ifndef UIImage
        #define UIImage NSImage
    #endif
    #ifndef UIImageView
        #define UIImageView NSImageView
    #endif
    #ifndef UIView
        #define UIView NSView
    #endif
#else
    // SDWebImage不支持5.0以下的iOS版本
    #if __IPHONE_OS_VERSION_MIN_REQUIRED != 20000 && __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_5_0
        #error SDWebImage doesn't support Deployment Target version < 5.0
    #endif

    // SD_UIKIT为真时，导入UIKit，SD_WATCH为真时，导入WatchKit
    #if SD_UIKIT
        #import <UIKit/UIKit.h>
    #endif
    #if SD_WATCH
        #import <WatchKit/WatchKit.h>
    #endif
#endif

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#ifndef NS_OPTIONS
#define NS_OPTIONS(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#if OS_OBJECT_USE_OBJC
    #undef SDDispatchQueueRelease
    #undef SDDispatchQueueSetterSementics
    #define SDDispatchQueueRelease(q)
    #define SDDispatchQueueSetterSementics strong
#else
    #undef SDDispatchQueueRelease
    #undef SDDispatchQueueSetterSementics
    #define SDDispatchQueueRelease(q) (dispatch_release(q))
    #define SDDispatchQueueSetterSementics assign
#endif

extern UIImage *SDScaledImageForKey(NSString *key, UIImage *image);

typedef void(^SDWebImageNoParamsBlock)();

extern NSString *const SDWebImageErrorDomain;

// dispatch_queue_get_label() 获取队列的名字，如果队列没有名字，返回NULL
// 如果当前是主进程，就直接执行block，否则把block放到主进程运行。为什么要判断是否是主进程？因为iOS上任何UI的操作都在主线程上执行，所以主进程还有一个名字，叫做“UI进程”。
#ifndef dispatch_main_async_safe
#define dispatch_main_async_safe(block)\
    if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {\
        block();\
    } else {\
        dispatch_async(dispatch_get_main_queue(), block);\
    }
#endif

static int64_t kAsyncTestTimeout = 5;
