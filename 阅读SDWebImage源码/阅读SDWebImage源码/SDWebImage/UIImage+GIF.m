/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Laurin Brandner
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIImage+GIF.h"
#import <ImageIO/ImageIO.h>
#import "objc/runtime.h"
#import "NSImage+WebCache.h"

@implementation UIImage (GIF)

+ (UIImage *)sd_animatedGIFWithData:(NSData *)data {
    if (!data) {
        return nil;
    }

    // 根据data获取图片资源
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);

    // 获取图片资源中的图片数量
    size_t count = CGImageSourceGetCount(source);

    UIImage *staticImage;

    if (count <= 1) {
        // 如果图片数量小于或者等于1，直接转换
        staticImage = [[UIImage alloc] initWithData:data];
    } else {
        // we will only retrieve the 1st frame. the full GIF support is available via the FLAnimatedImageView category.
        // this here is only code to allow drawing animated images as static ones
#if SD_WATCH
        CGFloat scale = 1;
        scale = [WKInterfaceDevice currentDevice].screenScale;
#elif SD_UIKIT
        CGFloat scale = 1;
        scale = [UIScreen mainScreen].scale;
#endif
        // 获取图片资源中第一帧的图片
        CGImageRef CGImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
#if SD_UIKIT || SD_WATCH
        // 将CGImage对象转换成UIImage对象
        UIImage *frameImage = [UIImage imageWithCGImage:CGImage scale:scale orientation:UIImageOrientationUp];
        // 转换成动图（感觉没必要啊）
        staticImage = [UIImage animatedImageWithImages:@[frameImage] duration:0.0f];
#elif SD_MAC
        staticImage = [[UIImage alloc] initWithCGImage:CGImage size:NSZeroSize];
#endif
        // 释放CG对象CGImage
        CGImageRelease(CGImage);
    }

    // CG对象需要我们自己来释放，使用CFRelease来释放
    CFRelease(source);

    return staticImage;
}

- (BOOL)isGIF {
    return (self.images != nil);
}

@end
