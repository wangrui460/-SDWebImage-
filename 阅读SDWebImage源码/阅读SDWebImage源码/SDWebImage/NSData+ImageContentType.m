/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Fabrice Aneche
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "NSData+ImageContentType.h"


@implementation NSData (ImageContentType)

+ (SDImageFormat)sd_imageFormatForImageData:(nullable NSData *)data {
    if (!data) {
        return SDImageFormatUndefined;
    }
    
    // uint8_t: 1字节、uint16_t: 2字节、uint32_t: 4字节、uint64_t: 8字节
    uint8_t c;
    // 获取data的一第个字节数据，存储在c中
    [data getBytes:&c length:1];
    switch (c) {
        case 0xFF:
            return SDImageFormatJPEG;   // JPEG (jpg)，文件头：FFD8FFE1
        case 0x89:
            return SDImageFormatPNG;    // PNG (png)，文件头：89504E47
        case 0x47:
            return SDImageFormatGIF;    // GIF (gif)，文件头：47494638
        case 0x49:
        case 0x4D:
            return SDImageFormatTIFF;   // TIFF tif;tiff 0x49492A00、0x4D4D002A
        case 0x52:
            // R as RIFF for WEBP
            if (data.length < 12) {
                return SDImageFormatUndefined;  // 当第一个字节为52时，如果长度<12 我们就认定为不是图片
            }
            
            // 通过数据截取并encode成ASCII后获得testString
            NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
            if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"]) {
                return SDImageFormatWebP;   // 如果testString头部包含RIFF且尾部也包含WEBP，那么就认定该图片格式为webp
            }
    }
    return SDImageFormatUndefined;
}

@end
