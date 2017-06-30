/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"
#import "SDImageCacheConfig.h"

typedef NS_ENUM(NSInteger, SDImageCacheType) {
    /**
     * The image wasn't available the SDWebImage caches, but was downloaded from the web.
     */
    SDImageCacheTypeNone,
    /**
     * The image was obtained from the disk cache.
     */
    SDImageCacheTypeDisk,
    /**
     * The image was obtained from the memory cache.
     */
    SDImageCacheTypeMemory
};

typedef void(^SDCacheQueryCompletedBlock)(UIImage * _Nullable image, NSData * _Nullable data, SDImageCacheType cacheType);

typedef void(^SDWebImageCheckCacheCompletionBlock)(BOOL isInCache);

typedef void(^SDWebImageCalculateSizeBlock)(NSUInteger fileCount, NSUInteger totalSize);


/**
 * SDImageCache maintains a memory cache and an optional disk cache. Disk cache write operations are performed
 * asynchronous so it doesn’t add unnecessary latency to the UI.
 */
@interface SDImageCache : NSObject

#pragma mark - Properties

/** 通过SDImageCacheConfig这个类来管理缓存的配置信息 */
@property (nonatomic, nonnull, readonly) SDImageCacheConfig *config;

/** 可以通过maxMemoryCost来设置内存的最大缓存是多少，这个是以像素为单位的 */
@property (assign, nonatomic) NSUInteger maxMemoryCost;

/** 可以通过maxMemoryCountLimit来设置内存的最大缓存数量是多少 */
@property (assign, nonatomic) NSUInteger maxMemoryCountLimit;

#pragma mark - Singleton and initialization

/** 单例对象 */
+ (nonnull instancetype)sharedImageCache;

/** 通过指定的namespace来初始化 */
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns;

/** 通过指定的namespace和directory来 */
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns
                       diskCacheDirectory:(nonnull NSString *)directory NS_DESIGNATED_INITIALIZER;
// 注意：如果想设置某个方法为指定的初始化方法，通过NS_DESIGNATED_INITIALIZER来实现

#pragma mark - Cache paths

/** 根据namespace获取磁盘缓存路径 */
- (nullable NSString *)makeDiskCachePath:(nonnull NSString*)fullNamespace;

/**
 * 添加一个只读的存储路径
 * Add a read-only cache path to search for images pre-cached by SDImageCache
 * Useful if you want to bundle pre-loaded images with your app
 *
 * @param path The path to use for this read-only cache path
 */
- (void)addReadOnlyCachePath:(nonnull NSString *)path;

#pragma mark - Store Ops

/**
 * 异步存储图片到内存和磁盘中
 *
 * @param image           The image to store
 * @param key             The unique image cache key, usually it's image absolute URL
 * @param completionBlock A block executed after the operation is finished
 */
- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

/**
 * 异步存储图片到内存和磁盘中（如果toDisk为yes则存储到磁盘中）
 *
 * @param image           The image to store
 * @param key             The unique image cache key, usually it's image absolute URL
 * @param toDisk          Store the image to disk cache if YES
 * @param completionBlock A block executed after the operation is finished
 */
- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

/**
 * 异步存储图片到内存和磁盘中（如果toDisk为yes则存储到磁盘中）
 *
 * @param image           The image to store
 * @param imageData       The image data as returned by the server, this representation will be used for disk storage
 *                        instead of converting the given image object into a storable/compressed image format in order
 *                        to save quality and CPU
 * @param key             The unique image cache key, usually it's image absolute URL
 * @param toDisk          Store the image to disk cache if YES
 * @param completionBlock A block executed after the operation is finished
 */
- (void)storeImage:(nullable UIImage *)image
         imageData:(nullable NSData *)imageData
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

/**
 * 同步存储图片到磁盘中
 *
 * @warning This method is synchronous, make sure to call it from the ioQueue
 *
 * @param imageData  The image data to store
 * @param key        The unique image cache key, usually it's image absolute URL
 */
- (void)storeImageDataToDisk:(nullable NSData *)imageData forKey:(nullable NSString *)key;

#pragma mark - Query and Retrieve Ops

/**
 *  异步判断图片是否被缓存到disk (does not load the image)
 *
 *  @param key             the key describing the url
 *  @param completionBlock the block to be executed when the check is done.
 *  @note the completion block will be always executed on the main queue
 */
- (void)diskImageExistsWithKey:(nullable NSString *)key completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;

/**
 * 异步查询图片是否存在，这里返回了一个NSOperation,原因是在内存中获取耗时非常短，在disk中时间相对较长
 *
 * @param key       The unique key used to store the wanted image
 * @param doneBlock The completion block. Will not get called if the operation is cancelled
 *
 * @return a NSOperation instance containing the cache op
 */
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key done:(nullable SDCacheQueryCompletedBlock)doneBlock;

/**
 * 同步在内存中查询图片
 *
 * @param key The unique key used to store the image
 */
- (nullable UIImage *)imageFromMemoryCacheForKey:(nullable NSString *)key;

/**
 * 同步在磁盘中查询图片
 *
 * @param key The unique key used to store the image
 */
- (nullable UIImage *)imageFromDiskCacheForKey:(nullable NSString *)key;

/**
 * 同步查询图片，先从内存中找，如果没找到再去磁盘中找
 *
 * @param key The unique key used to store the image
 */
- (nullable UIImage *)imageFromCacheForKey:(nullable NSString *)key;

#pragma mark - Remove Ops

/**
 * 异步移除图片，包括磁盘和内存都要移除
 *
 * @param key             The unique image cache key
 * @param completion      A block that should be executed after the image has been removed (optional)
 */
- (void)removeImageForKey:(nullable NSString *)key withCompletion:(nullable SDWebImageNoParamsBlock)completion;

/**
 * 异步移除图片，如果fromDisk为yes则移除磁盘图片
 *
 * @param key             The unique image cache key
 * @param fromDisk        Also remove cache entry from disk if YES
 * @param completion      A block that should be executed after the image has been removed (optional)
 */
- (void)removeImageForKey:(nullable NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(nullable SDWebImageNoParamsBlock)completion;

#pragma mark - Cache clean Ops

/** 清空内存 */
- (void)clearMemory;

/** 异步清空磁盘 */
- (void)clearDiskOnCompletion:(nullable SDWebImageNoParamsBlock)completion;

/** 异步清空过期图片 */
- (void)deleteOldFilesWithCompletionBlock:(nullable SDWebImageNoParamsBlock)completionBlock;

#pragma mark - Cache Info

/** 获取磁盘使用size */
- (NSUInteger)getSize;

/** 获取磁盘缓存的图片数目 */
- (NSUInteger)getDiskCount;

/** 异步获取disk使用size */
- (void)calculateSizeWithCompletionBlock:(nullable SDWebImageCalculateSizeBlock)completionBlock;

#pragma mark - Cache Paths

/**
 *  获取某个路径下的指定的图片，比如key为http://www.123.com/image.png, path为http://www.456.com,那么调用后边的方法后，返回http://www.456.com/image.png
 *
 *  @param key  the key (can be obtained from url using cacheKeyForURL)
 *  @param path the cache path root folder
 *
 *  @return the cache path
 */
- (nullable NSString *)cachePathForKey:(nullable NSString *)key inPath:(nonnull NSString *)path;

/**
 *  获取默认的缓存路径
 *
 *  @param key the key (can be obtained from url using cacheKeyForURL)
 *
 *  @return the default cache path
 */
- (nullable NSString *)defaultCachePathForKey:(nullable NSString *)key;

@end
