//
//  SSZipArchiveExp.h
//  Pods
//
//  Created by 大大东 on 2023/2/22.
//

#import "SSZipArchive.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SZipFileType){
    FileType_File = 0,
    FileType_Dir,
    FileType_SymbolLink,
};


@interface SZipPreViewItem : NSObject

@property (nonatomic, assign) SZipFileType type;
@property (nonatomic, copy  ) NSString *name;
@property (nonatomic, copy  ) NSString *absPath;
@property (nonatomic, strong) NSDate *lastModifyDate;
@property (nonatomic, assign) unsigned long size; // KB

@end



@interface SSZipArchiveExp: NSObject

/// 预览一个zip文件的内容 不解压 速度快
+ (void)preViewZipFileAtPath:(NSString *)path
                    password:(nullable NSString *)password
           completionHandler:(void (^_Nullable)(NSArray<SZipPreViewItem *> * _Nullable items, BOOL succeeded, NSError * _Nullable error))completionHandler;

/// 创建一个zip, 会保持paths里的文件夹路径 (原作者的实现 会把不同层级的文件 压缩到同一目录层级)
+ (BOOL)keepDirectoryCreateZipFileAtPath:(NSString *)outpath
                               withPaths:(NSArray *)paths
                                password:(nullable NSString *)password
                         progressHandler:(void(^ _Nullable)(NSUInteger entryNumber, NSUInteger total))progressHandler;

@end

NS_ASSUME_NONNULL_END
