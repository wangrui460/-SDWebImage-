/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Laurin Brandner
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"

@interface UIImage (GIF)


// 通过NSData获取图片，但是获取的是第一帧图像
+ (UIImage *)sd_animatedGIFWithData:(NSData *)data;

// 判断当前图片是不是gif图片
- (BOOL)isGIF;

@end
