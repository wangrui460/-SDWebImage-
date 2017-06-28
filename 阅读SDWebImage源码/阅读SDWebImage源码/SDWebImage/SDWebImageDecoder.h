/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) james <https://github.com/mystcolor>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

@interface UIImage (ForceDecode)

/**
 * 方法由来：当显示或者绘制的时候，UIKit 只做了额外的延迟初始化和解码(解码消耗很高)
 * 方法作用：decodeImageWithImage 这个方法用于在后台线程对图片进行解压缩并且缓存起来，从而让系统不必做额外的转换，然后在主线程上显示，以保证tableviews/collectionviews 交互更加流畅
 * ⚠️注意：但是如果是加载高分辨率图片的话，会适得其反，有可能造成上G的内存消耗。所以，对于高分辨率的图片，应该禁止解压缩操作:
    [[SDImageCache sharedImageCache] setShouldDecompressImages:NO];
    [[SDWebImageDownloader sharedDownloader] setShouldDecompressImages:NO];
 */
+ (nullable UIImage *)decodedImageWithImage:(nullable UIImage *)image;

+ (nullable UIImage *)decodedAndScaledDownImageWithImage:(nullable UIImage *)image;

@end
