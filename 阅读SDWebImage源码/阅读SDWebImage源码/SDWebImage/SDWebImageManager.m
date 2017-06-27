/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import <objc/message.h>
#import "NSImage+WebCache.h"

// 实现了 SDWebImageOperation 协议的一个简单对象(该协议中只有一个cancel方法)
// SDWebImageCombinedOperation的作用就是关联缓存和下载的对象，每当有新的图片地址需要下载的时候，就会产生一个新的SDWebImageCombinedOperation实例
@interface SDWebImageCombinedOperation : NSObject <SDWebImageOperation>

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (copy, nonatomic, nullable) SDWebImageNoParamsBlock cancelBlock;
@property (strong, nonatomic, nullable) NSOperation *cacheOperation;

@end

@interface SDWebImageManager ()

// 负责图片缓存相关操作
@property (strong, nonatomic, readwrite, nonnull) SDImageCache *imageCache;

// 负责图片现在相关操作
@property (strong, nonatomic, readwrite, nonnull) SDWebImageDownloader *imageDownloader;

// 用来存放下载失败的URL地址的数组
@property (strong, nonatomic, nonnull) NSMutableSet<NSURL *> *failedURLs;

// runningOperations是专门用来存放这些对图片的操作的SDWebImageCombinedOperation对象
@property (strong, nonatomic, nonnull) NSMutableArray<SDWebImageCombinedOperation *> *runningOperations;

@end

@implementation SDWebImageManager

+ (nonnull instancetype)sharedManager {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (nonnull instancetype)init {
    SDImageCache *cache = [SDImageCache sharedImageCache];
    SDWebImageDownloader *downloader = [SDWebImageDownloader sharedDownloader];
    return [self initWithCache:cache downloader:downloader];
}

- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader {
    if ((self = [super init])) {
        _imageCache = cache;
        _imageDownloader = downloader;
        _failedURLs = [NSMutableSet new];
        _runningOperations = [NSMutableArray new];
    }
    return self;
}

// 利用Image的URL生成一个缓存时需要的key.
// 这里有两种情况,第一种是如果检测到cacheKeyFilter不为空时,利用cacheKeyFilter来处理URL生成一个key.
- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url {
    if (!url) {
        return @"";
    }

    // 如果设置了缓存key的过滤器，过滤一下url
    if (self.cacheKeyFilter) {
        return self.cacheKeyFilter(url);
    } else {
        // 否则直接使用url
        return url.absoluteString;
    }
}

- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    BOOL isInMemoryCache = ([self.imageCache imageFromMemoryCacheForKey:key] != nil);
    
    if (isInMemoryCache) {
        // making sure we call the completion block on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(YES);
            }
        });
        return;
    }
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}

- (void)diskImageExistsForURL:(nullable NSURL *)url
                   completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}

#pragma mark - 如果不存在于缓存中，请下载给定URL的图像，否则返回缓存的版本。
- (id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                     options:(SDWebImageOptions)options
                                    progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                   completed:(nullable SDInternalCompletionBlock)completedBlock
{
    // 如果调用这个方法，却没有设置completedBlock，是没有意义的
    NSAssert(completedBlock != nil, @"If you mean to prefetch the image, use -[SDWebImagePrefetcher prefetchURLs] instead");

    // 有时候xcode不会警告这个类型错误（将NSSTring当做NSURL），所以这里做一下容错
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }

    // 防止app由于类型错误的奔溃，比如传入NSNull代替NSURL
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }

    // SDWebImageCombinedOperation：实现了SDWebImageOperation协议的一个简单对象
    // 用__block修饰栈变量，让其可在block中进行修改
    __block SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
    // 将其变成弱引用
    __weak SDWebImageCombinedOperation *weakOperation = operation;

    // 判断这个url在不在失败的url列表中
    BOOL isFailedUrl = NO;
    if (url) {
        // 创建一个互斥锁防止现在有别的线程修改failedURLs.
        // 判断这个url是否是fail过的.如果url failed过的那么isFailedUrl就是true
        @synchronized (self.failedURLs) {
            isFailedUrl = [self.failedURLs containsObject:url];
        }
    }

    // 如果url的长度为0，或者url在失败的url列表中且下载的策略不为SDWebImageRetryFailed，那么就抛出错误，并return。
    if (url.absoluteString.length == 0 || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
        // 这里做的就是抛出错误,文件不存在(NSURLErrorFileDoesNotExist)
        [self callCompletionBlockForOperation:operation completion:completedBlock error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil] url:url];
        return operation;
    }

    // 当然如果不存在上面的这些错误，就将对应的SDWebImageCombinedOperation对象加入到SDWebImageManager的runningOperations数组中。
    // 创建一个互斥锁防止现在有别的线程修改runningOperations.
    @synchronized (self.runningOperations) {
        [self.runningOperations addObject:operation];
    }
    
    // 通过url来获取到对应的cacheKey
    NSString *key = [self cacheKeyForURL:url];

    // 通过SDWebImageManager的SDImageCache实例调用 queryCacheOperationForKey: done: 方法来返回所需要的这个NSOperation实例。
    operation.cacheOperation = [self.imageCache queryCacheOperationForKey:key done:^(UIImage *cachedImage, NSData *cachedData, SDImageCacheType cacheType) {
        // 如果对当前operation进行了取消标记，在SDWebImageManager的runningOperations移除operation
        if (operation.isCancelled) {
            [self safelyRemoveOperationFromRunning:operation];
            return;
        }
        
        // 以下四个方法会通过if条件判断中
        // 1. 如果现在下载的图片没有缓存，且没有实现代理方法（这个代理方法是我们自己来实现的）
        // 2. 如果现在下载的图片没有缓存，我们实现了代理方法，但是代理方法返回的是YES
        // 3. 如果下载的方法的options为SDWebImageRefreshCached，且没有实现代理方法（这个代理方法是我们自己来实现的）
        // 4. 如果下载的方法的options为SDWebImageRefreshCached，且我们实现了代理方法，代理方法返回的是YES
        if ((!cachedImage || options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url]))
        {
            if (cachedImage && options & SDWebImageRefreshCached) {
                // 如果可以找到缓存，且options为SDWebImageRefreshCached，那么就先把缓存的图像数据传递出去
                [self callCompletionBlockForOperation:weakOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            }

            // 首先downloaderOptions初始值为0，如果这里的options设定了哪些，就给downloaderOptions加上哪些
            SDWebImageDownloaderOptions downloaderOptions = 0;
            // A |= B A与B按位或操作后把值赋给A
            // ~ 按位取反运算符
            // A &= B A与B按位与操作后把值赋给A
            if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
            if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
            if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
            if (options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
            if (options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
            if (options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
            if (options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
            if (options & SDWebImageScaleDownLargeImages) downloaderOptions |= SDWebImageDownloaderScaleDownLargeImages;
            
            // 如果可以找到缓存，且options为SDWebImageRefreshCached
            if (cachedImage && options & SDWebImageRefreshCached) {
                // 不让 downloaderOptions 包含 SDWebImageDownloaderProgressiveDownload(渐进式下载)
                downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
                // 让 downloaderOptions 里必须包含 SDWebImageDownloaderIgnoreCachedResponse(忽略缓存)
                downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
            }
            
            SDWebImageDownloadToken *subOperationToken = [self.imageDownloader downloadImageWithURL:url options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *downloadedData, NSError *error, BOOL finished)
            {
                // block中的__strong 关键字--->防止对象提前释放
                __strong __typeof(weakOperation) strongOperation = weakOperation;
                if (!strongOperation || strongOperation.isCancelled) {
                    // Do nothing if the operation was cancelled
                    // See #699 for more details
                    // if we would call the completedBlock, there could be a race condition between this block and another completedBlock for the same object, so if this one is called second, we will overwrite the new data
                } else if (error) {
                    // 如果发生了错误，就把错误传入对应的回调来处理error
                    [self callCompletionBlockForOperation:strongOperation completion:completedBlock error:error url:url];

                    // 检查错误类型，确认不是客户端或者服务器端的网络问题，就认为这个url本身问题了。并把这个url放到failedURLs中
                    if (   error.code != NSURLErrorNotConnectedToInternet
                        && error.code != NSURLErrorCancelled
                        && error.code != NSURLErrorTimedOut
                        && error.code != NSURLErrorInternationalRoamingOff
                        && error.code != NSURLErrorDataNotAllowed
                        && error.code != NSURLErrorCannotFindHost
                        && error.code != NSURLErrorCannotConnectToHost
                        && error.code != NSURLErrorNetworkConnectionLost) {
                        @synchronized (self.failedURLs) {
                            [self.failedURLs addObject:url];
                        }
                    }
                }
                else {
                    // 如果使用了SDWebImageRetryFailed选项，那么即使该url是failedURLs，也要从failedURLs移除，并继续执行download
                    if ((options & SDWebImageRetryFailed)) {
                        @synchronized (self.failedURLs) {
                            [self.failedURLs removeObject:url];
                        }
                    }
                    
                    // 如果不设定options里包含SDWebImageCacheMemoryOnly，那么cacheOnDisk为YES，表示会把图片缓存到磁盘
                    BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);

                    if (options & SDWebImageRefreshCached && cachedImage && !downloadedImage) {
                        // 如果options包含SDWebImageRefreshCached，cachedImage有值，但是下载图像downloadedImage为nil，不调用完成的回调completion block
                        // 这里的意思就是虽然现在有缓存图片，但是要强制刷新图片，但是没有下载到图片，那么现在就什么都不做，还是使用原来的缓存图片
                    }
                    else if (downloadedImage && (!downloadedImage.images || (options & SDWebImageTransformAnimatedImage)) && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                        /*
                         1.图片下载成功了，不是gif图像，且代理实现了imageManager:transformDownloadedImage:withURL:
                         2.图片下载成功了，options中包含SDWebImageTransformAnimatedImage，且代理实现了imageManager:transformDownloadedImage:withURL:
                         这里做的主要操作是在一个新开的异步队列中对图片做一个转换的操作，例如需要改变原始图片的灰度值等情况
                         */
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            // 如果获得了新的transformedImage,不管transform后是否改变了图片.都要存储到缓存中
                            UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];

                            if (transformedImage && finished) {
                                BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                                // 如果图像被转换，则给imageData传入nil，因此我们可以从图像重新计算数据
                                [self.imageCache storeImage:transformedImage imageData:(imageWasTransformed ? nil : downloadedData) forKey:key toDisk:cacheOnDisk completion:nil];
                            }
                            
                            // 将对应转换后的图片通过block传出去
                            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:transformedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                        });
                    }
                    else {
                        // 下载好了图片且完成了，存到内存和磁盘，将对应的图片通过block传出去
                        if (downloadedImage && finished) {
                            [self.imageCache storeImage:downloadedImage imageData:downloadedData forKey:key toDisk:cacheOnDisk completion:nil];
                        }
                        [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:downloadedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                    }
                }
                
                // 下载结束后移除对应operation
                if (finished) {
                    [self safelyRemoveOperationFromRunning:strongOperation];
                }
            }];
            operation.cancelBlock = ^{
                [self.imageDownloader cancel:subOperationToken];
                __strong __typeof(weakOperation) strongOperation = weakOperation;
                [self safelyRemoveOperationFromRunning:strongOperation];
            };
        }
        else if (cachedImage) {
            // 如果有缓存图片，调用完成回调并返回缓存图片
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            [self safelyRemoveOperationFromRunning:operation];
        }
        else {
            // 不在缓存中，不被代理允许下载
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:nil data:nil error:nil cacheType:SDImageCacheTypeNone finished:YES url:url];
            [self safelyRemoveOperationFromRunning:operation];
        }
    }];

    return operation;
}

- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url {
    if (image && url) {
        NSString *key = [self cacheKeyForURL:url];
        [self.imageCache storeImage:image forKey:key toDisk:YES completion:nil];
    }
}

- (void)cancelAll {
    @synchronized (self.runningOperations) {
        NSArray<SDWebImageCombinedOperation *> *copiedOperations = [self.runningOperations copy];
        [copiedOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeObjectsInArray:copiedOperations];
    }
}

- (BOOL)isRunning {
    BOOL isRunning = NO;
    @synchronized (self.runningOperations) {
        isRunning = (self.runningOperations.count > 0);
    }
    return isRunning;
}

- (void)safelyRemoveOperationFromRunning:(nullable SDWebImageCombinedOperation*)operation {
    // 创建一个互斥锁防止现在有别的线程修改 runningOperations
    @synchronized (self.runningOperations) {
        if (operation) {
            [self.runningOperations removeObject:operation];
        }
    }
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  error:(nullable NSError *)error
                                    url:(nullable NSURL *)url {
    [self callCompletionBlockForOperation:operation completion:completionBlock image:nil data:nil error:error cacheType:SDImageCacheTypeNone finished:YES url:url];
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  image:(nullable UIImage *)image
                                   data:(nullable NSData *)data
                                  error:(nullable NSError *)error
                              cacheType:(SDImageCacheType)cacheType
                               finished:(BOOL)finished
                                    url:(nullable NSURL *)url {
    // 主线程直接调用完成的回调
    dispatch_main_async_safe(^{
        if (operation && !operation.isCancelled && completionBlock) {
            completionBlock(image, data, error, cacheType, finished, url);
        }
    });
}

@end


@implementation SDWebImageCombinedOperation

- (void)setCancelBlock:(nullable SDWebImageNoParamsBlock)cancelBlock {
    // 如果该operation已经取消了，我们只是调用回调block
    if (self.isCancelled) {
        if (cancelBlock) {
            cancelBlock();
        }
        // 不要忘了设置cacelBlock为nil，否则可能会奔溃
        _cancelBlock = nil;
    }
    else {
        _cancelBlock = [cancelBlock copy];
    }
}

// SDWebImageCombinedOperation遵循SDWebImageOperation协议
- (void)cancel {
    self.cancelled = YES;
    if (self.cacheOperation) {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    if (self.cancelBlock) {
        self.cancelBlock();
        
        // TODO: this is a temporary fix to #809.
        // Until we can figure the exact cause of the crash, going with the ivar instead of the setter
//        self.cancelBlock = nil;
        _cancelBlock = nil;
    }
}

@end
