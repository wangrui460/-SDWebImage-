/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

@interface SDImageCacheConfig : NSObject

/** 是否解压缩图片，默认为YES */
@property (assign, nonatomic) BOOL shouldDecompressImages;

/** 是否禁用iCloud备份， 默认为YES */
@property (assign, nonatomic) BOOL shouldDisableiCloud;

/** 是否缓存到内存中，默认为YES */
@property (assign, nonatomic) BOOL shouldCacheImagesInMemory;

/** 最大的缓存不过期时间， 单位为秒，默认为一周的时间 */
@property (assign, nonatomic) NSInteger maxCacheAge;

/** 最大的缓存尺寸，单位为字节 */
@property (assign, nonatomic) NSUInteger maxCacheSize;

@end
