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
/**
 在常用的tableView中cell上有图片是再常见不过的了,在我们使用SDWebImage给上面的cell中的imageview设置网络图片的时候，图片的下载是异步的，那么如果现在给当前cell设置的为cell.imageview为a.png，随着tableView的滑动，这个cell会被复用，复用后现在cell.imageview为b.png，这里的a.png和b.png都是从网络上异步下载的，不是本地的资源图片。一开始cell的index为1，image为a，复用以后cell的index为6，image为b，按道理来说图片应该先为a，然后为b，但是a很大，b很小，b都已经下载好了，a还没有下载好，当滑动到显示index为6的cell的时候，cell的图片先显示的b，因为b已经下载好了，过了一会，a也下载好了。那么神奇的事情发生了，index为6的cell中的图片a把b覆盖了，应该显示b的变成显示a了
 */
- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key;

// 直接删除（比上面的方法少一个取消的操作）
- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key;

@end

#endif
