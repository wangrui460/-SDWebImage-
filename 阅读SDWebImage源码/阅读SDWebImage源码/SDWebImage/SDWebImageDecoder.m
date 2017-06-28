/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) james <https://github.com/mystcolor>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDecoder.h"

@implementation UIImage (ForceDecode)

#if SD_UIKIT || SD_WATCH
// kBytesPerPixel：用来说明每个像素占用内存多少个字节，在这里是占用4个字节（图像在iOS设备上是以像素为单位显示的）
static const size_t kBytesPerPixel = 4;
// kBitsPerComponent：表示每一个组件占多少位。比方说R、G、B、A是4个组件，每个像素由这4个组件组成，那么我们就用8位来表示着每一个组件，所以这个RGBA就是8*4 = 32位
static const size_t kBitsPerComponent = 8;

+ (nullable UIImage *)decodedImageWithImage:(nullable UIImage *)image {
    if (![UIImage shouldDecodeImage:image]) {
        return image;
    }
    
    // autorelease the bitmap context and all vars to help system to free memory when there are memory warning.
    // on iOS7, do not forget to call [[SDImageCache sharedImageCache] clearMemory];
    @autoreleasepool{
        
        // 通过CGImageRef imageRef = image.CGImage可以拿到和图像有关的各种参数
        CGImageRef imageRef = image.CGImage;
        
        // 获取image的颜色空间
        CGColorSpaceRef colorspaceRef = [UIImage colorSpaceForImageRef:imageRef];
        
        size_t width = CGImageGetWidth(imageRef);
        size_t height = CGImageGetHeight(imageRef);
        // 获取每行的字节数
        size_t bytesPerRow = kBytesPerPixel * width;

        // CGBitmapContextCreate 不支持透明通道.
        // 创建位图上下文
        CGContextRef context = CGBitmapContextCreate(NULL,
                                                     width,
                                                     height,
                                                     kBitsPerComponent,
                                                     bytesPerRow,
                                                     colorspaceRef,
                                                     kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
        if (context == NULL) {
            return image;
        }
        
        // 绘制图形到位图上下文中
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
        // 根据位图上下文创建CGImageRef
        CGImageRef imageRefWithoutAlpha = CGBitmapContextCreateImage(context);
        // 将 CGImageRef 转为 UIImage
        UIImage *imageWithoutAlpha = [UIImage imageWithCGImage:imageRefWithoutAlpha
                                                         scale:image.scale
                                                   orientation:image.imageOrientation];
        CGImageRelease(imageRef);
        CGContextRelease(context);
        CGImageRelease(imageRefWithoutAlpha);
        
        return imageWithoutAlpha;
    }
}

/*
 * 最大支持压缩图像源的大小
 * Suggested value for iPad1 and iPhone 3GS: 60.
 * Suggested value for iPad2 and iPhone 4: 120.
 * Suggested value for iPhone 3G and iPod 2 and earlier devices: 30.
 */
static const CGFloat kDestImageSizeMB = 60.0f;

/*
 * 原图方块的大小,这个方块将会被用来分割原图，默认设置为20M
 * Suggested value for iPad1 and iPhone 3GS: 20.
 * Suggested value for iPad2 and iPhone 4: 40.
 * Suggested value for iPhone 3G and iPod 2 and earlier devices: 10.
 */
static const CGFloat kSourceImageTileSizeMB = 20.0f;

// 1M有多少字节
static const CGFloat kBytesPerMB = 1024.0f * 1024.0f;
// 1M有多少像素
static const CGFloat kPixelsPerMB = kBytesPerMB / kBytesPerPixel;
// 目标总像素
static const CGFloat kDestTotalPixels = kDestImageSizeMB * kPixelsPerMB;
// 原图方块总像素
static const CGFloat kTileTotalPixels = kSourceImageTileSizeMB * kPixelsPerMB;
// 重叠像素大小
static const CGFloat kDestSeemOverlap = 2.0f;   // the numbers of pixels to overlap the seems where tiles meet.


// 原理： 首先定义一个大小固定的方块，然后把原图按照方块的大小进行分割，最后把每个方块中的数据画到目标画布上，这样就能得到目标图像了。
+ (nullable UIImage *)decodedAndScaledDownImageWithImage:(nullable UIImage *)image
{
    // 检测图像能否解码
    if (![UIImage shouldDecodeImage:image]) {
        return image;
    }
    
    // 检查图像应不应该压缩，原则是：如果图像大于目标尺寸才需要压缩
    if (![UIImage shouldScaleDownImage:image]) {
        return [UIImage decodedImageWithImage:image];
    }
    
    CGContextRef destContext;
    
    // autorelease the bitmap context and all vars to help system to free memory when there are memory warning.
    // on iOS7, do not forget to call [[SDImageCache sharedImageCache] clearMemory];
    @autoreleasepool {
        // 拿到数据信息 sourceImageRef
        CGImageRef sourceImageRef = image.CGImage;
        
        // 计算原图的像素 sourceResolution
        CGSize sourceResolution = CGSizeZero;
        sourceResolution.width = CGImageGetWidth(sourceImageRef);
        sourceResolution.height = CGImageGetHeight(sourceImageRef);
        
        // 计算原图总像素 sourceTotalPixels
        float sourceTotalPixels = sourceResolution.width * sourceResolution.height;
        
        // 计算压缩比例 imageScale
        float imageScale = kDestTotalPixels / sourceTotalPixels;
        
        // 计算目标像素 destResolution
        CGSize destResolution = CGSizeZero;
        destResolution.width = (int)(sourceResolution.width*imageScale);
        destResolution.height = (int)(sourceResolution.height*imageScale);
        
        // 获取当前的颜色空间 colorspaceRef
        CGColorSpaceRef colorspaceRef = [UIImage colorSpaceForImageRef:sourceImageRef];
        
        // 计算目标每行像素
        size_t bytesPerRow = kBytesPerPixel * destResolution.width;
        
        // 创建目标图像需要的内存空间：destBitmapData
        void* destBitmapData = malloc( bytesPerRow * destResolution.height );
        if (destBitmapData == NULL) {
            return image;
        }
        
        // 创建目标位图上下文
        destContext = CGBitmapContextCreate(destBitmapData,
                                            destResolution.width,
                                            destResolution.height,
                                            kBitsPerComponent,
                                            bytesPerRow,
                                            colorspaceRef,
                                            kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
        // 如果创建目标位图上下文，则释放内存空间：destBitmapData
        if (destContext == NULL) {
            free(destBitmapData);
            return image;
        }
        // 设置压缩质量
        CGContextSetInterpolationQuality(destContext, kCGInterpolationHigh);
        
        // 计算第一个原图方块 sourceTile，这个方块的宽度同原图一样，高度根据方块容量计算
        CGRect sourceTile = CGRectZero;
        sourceTile.size.width = sourceResolution.width;
        // The source tile height is dynamic. Since we specified the size
        // of the source tile in MB, see how many rows of pixels high it
        // can be given the input image width.
        sourceTile.size.height = (int)(kTileTotalPixels / sourceTile.size.width );
        sourceTile.origin.x = 0.0f;
        
        // 计算目标图像方块 destTile
        CGRect destTile;
        destTile.size.width = destResolution.width;
        destTile.size.height = sourceTile.size.height * imageScale;
        destTile.origin.x = 0.0f;
        
        // 计算原图像方块与方块重叠的像素大小 sourceSeemOverlap
        float sourceSeemOverlap = (int)((kDestSeemOverlap/destResolution.height)*sourceResolution.height);
        CGImageRef sourceTileImageRef;
        
        // 计算原图像需要被分割成多少个方块 iterations
        int iterations = (int)( sourceResolution.height / sourceTile.size.height );
        // If tile height doesn't divide the image height evenly, add another iteration
        // to account for the remaining pixels.
        int remainder = (int)sourceResolution.height % (int)sourceTile.size.height;
        if(remainder) {
            iterations++;
        }
        
        // 根据重叠像素计算原图方块的大小后，获取原图中该方块内的数据，把该数据写入到相对应的目标方块中
        float sourceTileHeightMinusOverlap = sourceTile.size.height;
        sourceTile.size.height += sourceSeemOverlap;
        destTile.size.height += kDestSeemOverlap;
        for( int y = 0; y < iterations; ++y ) {
            @autoreleasepool {
                sourceTile.origin.y = y * sourceTileHeightMinusOverlap + sourceSeemOverlap;
                destTile.origin.y = destResolution.height - (( y + 1 ) * sourceTileHeightMinusOverlap * imageScale + kDestSeemOverlap);
                sourceTileImageRef = CGImageCreateWithImageInRect( sourceImageRef, sourceTile );
                if( y == iterations - 1 && remainder ) {
                    float dify = destTile.size.height;
                    destTile.size.height = CGImageGetHeight( sourceTileImageRef ) * imageScale;
                    dify -= destTile.size.height;
                    destTile.origin.y += dify;
                }
                CGContextDrawImage( destContext, destTile, sourceTileImageRef );
                CGImageRelease( sourceTileImageRef );
            }
        }
        
        // 返回目标图像
        CGImageRef destImageRef = CGBitmapContextCreateImage(destContext);
        CGContextRelease(destContext);
        if (destImageRef == NULL) {
            return image;
        }
        UIImage *destImage = [UIImage imageWithCGImage:destImageRef scale:image.scale orientation:image.imageOrientation];
        CGImageRelease(destImageRef);
        if (destImage == nil) {
            return image;
        }
        return destImage;
    }
}

+ (BOOL)shouldDecodeImage:(nullable UIImage *)image {
    // image 为 nil的时候不解码
    if (image == nil) {
        return NO;
    }

    // 如果是动图的话不解码
    if (image.images != nil) {
        return NO;
    }
    
    CGImageRef imageRef = image.CGImage;
    
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(imageRef);
    // 判断当前图片是否带有alpha通道
    BOOL anyAlpha = (alpha == kCGImageAlphaFirst ||
                     alpha == kCGImageAlphaLast ||
                     alpha == kCGImageAlphaPremultipliedFirst ||
                     alpha == kCGImageAlphaPremultipliedLast);
    
    // 这是我自己加的，因为CG对象需要我们自己来释放
    CFRelease(imageRef);
    
    // 带有alpha通道的image不解码
    if (anyAlpha) {
        return NO;
    }
    
    return YES;
}

+ (BOOL)shouldScaleDownImage:(nonnull UIImage *)image {
    BOOL shouldScaleDown = YES;
        
    CGImageRef sourceImageRef = image.CGImage;
    CGSize sourceResolution = CGSizeZero;
    sourceResolution.width = CGImageGetWidth(sourceImageRef);
    sourceResolution.height = CGImageGetHeight(sourceImageRef);
    float sourceTotalPixels = sourceResolution.width * sourceResolution.height;
    float imageScale = kDestTotalPixels / sourceTotalPixels;
    if (imageScale < 1) {
        shouldScaleDown = YES;
    } else {
        shouldScaleDown = NO;
    }
    
    return shouldScaleDown;
}

+ (CGColorSpaceRef)colorSpaceForImageRef:(CGImageRef)imageRef {
    // current
    CGColorSpaceModel imageColorSpaceModel = CGColorSpaceGetModel(CGImageGetColorSpace(imageRef));
    CGColorSpaceRef colorspaceRef = CGImageGetColorSpace(imageRef);
    
    BOOL unsupportedColorSpace = (imageColorSpaceModel == kCGColorSpaceModelUnknown ||
                                  imageColorSpaceModel == kCGColorSpaceModelMonochrome ||
                                  imageColorSpaceModel == kCGColorSpaceModelCMYK ||
                                  imageColorSpaceModel == kCGColorSpaceModelIndexed);
    if (unsupportedColorSpace) {
        colorspaceRef = CGColorSpaceCreateDeviceRGB();
        CFAutorelease(colorspaceRef);
    }
    return colorspaceRef;
}
#elif SD_MAC
+ (nullable UIImage *)decodedImageWithImage:(nullable UIImage *)image {
    return image;
}

+ (nullable UIImage *)decodedAndScaledDownImageWithImage:(nullable UIImage *)image {
    return image;
}
#endif

@end
