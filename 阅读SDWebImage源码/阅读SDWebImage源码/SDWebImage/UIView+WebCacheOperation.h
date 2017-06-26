/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"

#if SD_UIKIT || SD_MAC

#import "SDWebImageManager.h"

@interface UIView (WebCacheOperation)

// 为当前view添加op对象，以key键
- (void)sd_setImageLoadOperation:(nullable id)operation forKey:(nullable NSString *)key;

// 先取消当前view中对应key的所有op对象，再将其删除
- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key;

// 直接删除（比上面的方法少一个取消的操作）
- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key;

@end

#endif
