/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageOperation.h"
#import "SDWebImageDownloader.h"
#import "SDImageCache.h"

typedef NS_OPTIONS(NSUInteger, SDWebImageOptions) {
    /**
     * 默认情况下,如果一个url在下载的时候失败了,那么这个url会被加入黑名单并且library不会尝试再次下载,这个flag会阻止library把失败的url加入黑名单(简单来说如果选择了这个flag,那么即使某个url下载失败了,sdwebimage还是会尝试再次下载他.)
     */
    SDWebImageRetryFailed = 1 << 0,

    /**
     * UI交互期间下载
     * 导致延迟下载在UIScrollView减速的时候，(也就是你滑动的时候scrollview不下载,你手从屏幕上移走,scrollview开始减速的时候才会开始下载图片)
     */
    SDWebImageLowPriority = 1 << 1,

    /**
     * 只进行内存缓存，不进行磁盘缓存
     */
    SDWebImageCacheMemoryOnly = 1 << 2,

    /**
     * 这个标志可以渐进式下载,显示的图像是逐步在下载(就像你用浏览器浏览网页的时候那种图片下载,一截一截的显示
     */
    SDWebImageProgressiveDownload = 1 << 3,

    /**
     * 这个选项帮助处理在同样的网络请求地址下图片的改变（处理图像地址没变，但是实际图片变了的情况）
     * 即使图像缓存，也要遵守HTTP响应缓存控制，如果需要，可以从远程位置刷新图像
     * 磁盘缓存将由NSURLCache而不是SDWebImage处理，导致轻微的性能降低。
     * 如果刷新缓存的图像，完成的block会在使用缓存图像的时候调用，还会在最后的图像被调用
     * 当你不能使你的URL静态与嵌入式缓存
     */
    SDWebImageRefreshCached = 1 << 4,

    /**
     * 在iOS4以上，如果app进入后台，也保持下载图像，这个需要取得用户权限
     * 如果后台任务过期，操作将被取消
     */
    SDWebImageContinueInBackground = 1 << 5,

    /**
     * 操作cookies存储在NSHTTPCookieStore通过设置NSMutableURLRequest.HTTPShouldHandleCookies = YES
     */
    SDWebImageHandleCookies = 1 << 6,

    /**
     * 允许使用无效的SSL证书
     * 用户测试，生成情况下小心使用
     */
    SDWebImageAllowInvalidSSLCertificates = 1 << 7,

    /**
     * 优先下载
     */
    SDWebImageHighPriority = 1 << 8,
    
    /**
     * 在加载图片时加载占位图。 此标志将延迟加载占位符图像，直到图像完成加载
     */
    SDWebImageDelayPlaceholder = 1 << 9,

    /**
     * 我们通常不调用transformDownloadedImage代理方法在动画图像上，大多数情况下会对图像进行耗损
     * 无论什么情况下都使用
     */
    SDWebImageTransformAnimatedImage = 1 << 10,
    
    /**
     * 图片在下载后被加载到imageView。但是在一些情况下，我们想要设置一下图片（引用一个滤镜或者加入透入动画）
     * 使用这个来手动的设置图片在下载图片成功后
     */
    SDWebImageAvoidAutoSetImage = 1 << 11,
    
    /**
     * 图像将根据其原始大小进行解码。 在iOS上，此标记会将图片缩小到与设备的受限内存兼容的大小。
     */
    SDWebImageScaleDownLargeImages = 1 << 12
};

typedef void(^SDExternalCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL);

typedef void(^SDInternalCompletionBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL);

typedef NSString * _Nullable (^SDWebImageCacheKeyFilterBlock)(NSURL * _Nullable url);


@class SDWebImageManager;

@protocol SDWebImageManagerDelegate <NSObject>

@optional

/**
 * Controls which image should be downloaded when the image is not found in the cache.
 *
 * @param imageManager The current `SDWebImageManager`
 * @param imageURL     The url of the image to be downloaded
 *
 * @return Return NO to prevent the downloading of the image on cache misses. If not implemented, YES is implied.
 */
- (BOOL)imageManager:(nonnull SDWebImageManager *)imageManager shouldDownloadImageForURL:(nullable NSURL *)imageURL;

/**
 * Allows to transform the image immediately after it has been downloaded and just before to cache it on disk and memory.
 * NOTE: This method is called from a global queue in order to not to block the main thread.
 *
 * @param imageManager The current `SDWebImageManager`
 * @param image        The image to transform
 * @param imageURL     The url of the image to transform
 *
 * @return The transformed image object.
 */
- (nullable UIImage *)imageManager:(nonnull SDWebImageManager *)imageManager transformDownloadedImage:(nullable UIImage *)image withURL:(nullable NSURL *)imageURL;

@end

/**
 * The SDWebImageManager is the class behind the UIImageView+WebCache category and likes.
 * It ties the asynchronous downloader (SDWebImageDownloader) with the image cache store (SDImageCache).
 * You can use this class directly to benefit from web image downloading with caching in another context than
 * a UIView.
 *
 * Here is a simple example of how to use SDWebImageManager:
 *
 * @code

SDWebImageManager *manager = [SDWebImageManager sharedManager];
[manager loadImageWithURL:imageURL
                  options:0
                 progress:nil
                completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                    if (image) {
                        // do something with image
                    }
                }];

 * @endcode
 */
@interface SDWebImageManager : NSObject

@property (weak, nonatomic, nullable) id <SDWebImageManagerDelegate> delegate;

// 包含下面两个单例对象
@property (strong, nonatomic, readonly, nullable) SDImageCache *imageCache;                 // 负责缓存相关的操作
@property (strong, nonatomic, readonly, nullable) SDWebImageDownloader *imageDownloader;    // 负责下载相关的操作

/**
 * The cache filter is a block used each time SDWebImageManager need to convert an URL into a cache key. This can
 * be used to remove dynamic part of an image URL.
 *
 * The following example sets a filter in the application delegate that will remove any query-string from the
 * URL before to use it as a cache key:
 *
 * @code

[[SDWebImageManager sharedManager] setCacheKeyFilter:^(NSURL *url) {
    url = [[NSURL alloc] initWithScheme:url.scheme host:url.host path:url.path];
    return [url absoluteString];
}];

 * @endcode
 */
@property (nonatomic, copy, nullable) SDWebImageCacheKeyFilterBlock cacheKeyFilter;

/**
 * Returns global SDWebImageManager instance.
 *
 * @return SDWebImageManager shared instance
 */
+ (nonnull instancetype)sharedManager;

/**
 * Allows to specify instance of cache and image downloader used with image manager.
 * @return new instance of `SDWebImageManager` with specified cache and downloader.
 */
- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader NS_DESIGNATED_INITIALIZER;

/**
 * 如果不存在于缓存中，就下载给定URL的图像，否则返回缓存的版本。
 *
 * @param url            The URL to the image
 * @param options        A mask to specify options to use for this request
 * @param progressBlock  当图像下载中时调用的block，这个进程的回调是在一个后台队列执行
 * @param completedBlock 当操作完成的回调，这个参数是必须的
 *
 *   This parameter is required.
 * 
 *   This block has no return value and takes the requested UIImage as first parameter and the NSData representation as second parameter.
 *   In case of error the image parameter is nil and the third parameter may contain an NSError.
 *
 *   The forth parameter is an `SDImageCacheType` enum indicating if the image was retrieved from the local cache
 *   or from the memory cache or from the network.
 *
 *   The fith parameter is set to NO when the SDWebImageProgressiveDownload option is used and the image is
 *   downloading. This block is thus called repeatedly with a partial image. When image is fully downloaded, the
 *   block is called a last time with the full image and the last parameter set to YES.
 *
 *   The last parameter is the original image URL
 *
 * @return 返回一个遵循SDWebImageOperation的对象，应该是一个SDWebImageDownloaderOperation对象的实例
 */
- (nullable id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                              options:(SDWebImageOptions)options
                                             progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                            completed:(nullable SDInternalCompletionBlock)completedBlock;

/**
 * Saves image to cache for given URL
 *
 * @param image The image to cache
 * @param url   The URL to the image
 *
 */

- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url;

/**
 * Cancel all current operations
 */
- (void)cancelAll;

/**
 * Check one or more operations running
 */
- (BOOL)isRunning;

/**
 *  Async check if image has already been cached
 *
 *  @param url              image url
 *  @param completionBlock  the block to be executed when the check is finished
 *  
 *  @note the completion block is always executed on the main queue
 */
- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;

/**
 *  Async check if image has already been cached on disk only
 *
 *  @param url              image url
 *  @param completionBlock  the block to be executed when the check is finished
 *
 *  @note the completion block is always executed on the main queue
 */
- (void)diskImageExistsForURL:(nullable NSURL *)url
                   completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;


/**
 *Return the cache key for a given URL
 */
- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url;

@end
