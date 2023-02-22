//
//  SSZipArchivePreview.h
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



@interface SSZipArchivePreview: NSObject

+ (void)preViewZipFileAtPath:(NSString *)path
                    password:(nullable NSString *)password
           completionHandler:(void (^_Nullable)(NSArray<SZipPreViewItem *> * _Nullable items, BOOL succeeded, NSError * _Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
