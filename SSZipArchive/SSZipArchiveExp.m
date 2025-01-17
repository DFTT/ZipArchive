//
//  SSZipArchiveExp.m
//  Pods
//
//  Created by 大大东 on 2023/2/22.
//

#import "SSZipArchiveExp.h"

@implementation SZipPreViewItem
- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"type: %d, name: %@, path: %@, size: %ld", (int)_type, _name, _absPath, _size];
}
@end






#include "minizip/mz_compat.h"
#include <zlib.h>



// SSZipArchive.m 里面有实现
BOOL _fileIsSymbolicLink(const unz_file_info *fileInfo);

// SSZipArchive.m 里面有实现
@interface SSZipArchive (_interner_func_)
+ (NSString *)_filenameStringWithCString:(const char *)filename
                         version_made_by:(uint16_t)version_made_by
                    general_purpose_flag:(uint16_t)flag
                                    size:(uint16_t)size_filename;

+ (NSDate *)_dateWithMSDOSFormat:(UInt32)msdosDateTime;
@end

// SSZipArchive.m 里面有实现
@interface NSString (_interner_func_)
- (NSString *)_sanitizedPath;
@end



@implementation SSZipArchiveExp

+ (void)preViewZipFileAtPath:(NSString *)path password:(NSString *)password completionHandler:(void (^ _Nullable)(NSArray<SZipPreViewItem *> * _Nullable, BOOL, NSError * _Nullable))completionHandler {
    
    
    // TODO : 本想支持继续预览的 但存在个问题 也许内部这个是加密的 当前api设计不支持传递内层zip的密码
    /// ~~为了支持递归预览 更深层次的zip, 这里先创建文件, 然后读取文件树获得压缩列表 (其实也可以实现一个context来避免创建文件导致的磁盘I/O)~~
    
    
    
    // Guard against empty strings
    if (path.length == 0)
    {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"received invalid argument(s)"};
        NSError *err = [NSError errorWithDomain:SSZipArchiveErrorDomain code:SSZipArchiveErrorCodeInvalidArguments userInfo:userInfo];
        if (completionHandler)
        {
            completionHandler(nil, NO, err);
        }
        return;
    }
    
    // Begin opening
    zipFile zip = unzOpen(path.fileSystemRepresentation);
    if (zip == NULL)
    {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"failed to open zip file"};
        NSError *err = [NSError errorWithDomain:SSZipArchiveErrorDomain code:SSZipArchiveErrorCodeFailedOpenZipFile userInfo:userInfo];
        if (completionHandler)
        {
            completionHandler(nil, NO, err);
        }
        return;
    }
    
    
    unz_global_info globalInfo = {};
    unzGetGlobalInfo(zip, &globalInfo);
    
    // Begin unzipping
    int ret = 0;
    ret = unzGoToFirstFile(zip);
    if (ret != UNZ_OK && ret != MZ_END_OF_LIST)
    {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"failed to open first file in zip file"};
        NSError *err = [NSError errorWithDomain:SSZipArchiveErrorDomain code:SSZipArchiveErrorCodeFailedOpenFileInZip userInfo:userInfo];
        if (completionHandler)
        {
            completionHandler(nil, NO, err);
        }
        unzClose(zip);
        return;
    }
    
    BOOL success = YES;
    int crc_ret = 0;
    
    NSMutableDictionary<NSString *, SZipPreViewItem *> *resDir = [NSMutableDictionary dictionaryWithCapacity:5];
    
    
    NSInteger currentFileNumber = -1;
    NSError *unzippingError;
    do {
        currentFileNumber++;
        if (ret == MZ_END_OF_LIST) {
            break;
        }
        @autoreleasepool {
            if (password.length == 0) {
                ret = unzOpenCurrentFile(zip);
            } else {
                ret = unzOpenCurrentFilePassword(zip, [password cStringUsingEncoding:NSUTF8StringEncoding]);
            }
            
            if (ret != UNZ_OK) {
                unzippingError = [NSError errorWithDomain:@"SSZipArchiveErrorDomain" code:SSZipArchiveErrorCodeFailedOpenFileInZip userInfo:@{NSLocalizedDescriptionKey: @"failed to open file in zip file"}];
                success = NO;
                break;
            }
            
            // Reading data and write to file
            unz_file_info fileInfo;
            memset(&fileInfo, 0, sizeof(unz_file_info));
            
            ret = unzGetCurrentFileInfo(zip, &fileInfo, NULL, 0, NULL, 0, NULL, 0);
            if (ret != UNZ_OK) {
                unzippingError = [NSError errorWithDomain:@"SSZipArchiveErrorDomain" code:SSZipArchiveErrorCodeFileInfoNotLoadable userInfo:@{NSLocalizedDescriptionKey: @"failed to retrieve info for file"}];
                success = NO;
                unzCloseCurrentFile(zip);
                break;
            }
            
            
            char *filename = (char *)malloc(fileInfo.size_filename + 1);
            if (filename == NULL)
            {
                success = NO;
                break;
            }
            
            unzGetCurrentFileInfo(zip, &fileInfo, filename, fileInfo.size_filename + 1, NULL, 0, NULL, 0);
            filename[fileInfo.size_filename] = '\0';
            
            BOOL fileIsSymbolicLink = _fileIsSymbolicLink(&fileInfo);
            
            NSString * strPath = [SSZipArchive _filenameStringWithCString:filename
                                                          version_made_by:fileInfo.version
                                                     general_purpose_flag:fileInfo.flag
                                                                     size:fileInfo.size_filename];
            if ([strPath hasPrefix:@"__MACOSX/"]) {
                // ignoring resource forks: https://superuser.com/questions/104500/what-is-macosx-folder
                unzCloseCurrentFile(zip);
                ret = unzGoToNextFile(zip);
                free(filename);
                continue;
            }
            
            // Check if it contains directory
            BOOL isDirectory = NO;
            if (filename[fileInfo.size_filename-1] == '/' || filename[fileInfo.size_filename-1] == '\\') {
                isDirectory = YES;
            }
            free(filename);
            
            // Sanitize paths in the file name.
            strPath = [strPath _sanitizedPath];
            if (!strPath.length) {
                // if filename data is unsalvageable, we default to currentFileNumber
                strPath = @(currentFileNumber).stringValue;
            }
            
            
            SZipPreViewItem *item = [[SZipPreViewItem alloc] init];
            item.absPath = strPath;
            item.name = strPath.lastPathComponent;
            item.type = fileIsSymbolicLink ? FileType_SymbolLink : (isDirectory ? FileType_Dir : FileType_File);
            item.size = (unsigned long)fileInfo.uncompressed_size;
            if (fileInfo.mz_dos_date != 0) {
                item.lastModifyDate = [SSZipArchive _dateWithMSDOSFormat:(UInt32)fileInfo.mz_dos_date];
            }else {
                item.lastModifyDate = [NSDate date];
            }
            
            NSString *key = [NSString stringWithFormat:@"%@_+_%d", item.absPath, (int)item.type];
            if ([resDir objectForKey:key] == nil) {
                [resDir setObject:item forKey:key];
            }
            
            crc_ret = unzCloseCurrentFile(zip);
            if (crc_ret == MZ_CRC_ERROR) {
                // CRC ERROR
                success = NO;
                break;
            }
            ret = unzGoToNextFile(zip);
        }
    } while (ret == UNZ_OK && success);
    
    // Close
    unzClose(zip);
    
    
    NSError *retErr = nil;
    if (crc_ret == MZ_CRC_ERROR)
    {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"crc check failed for file"};
        retErr = [NSError errorWithDomain:SSZipArchiveErrorDomain code:SSZipArchiveErrorCodeFileInfoNotLoadable userInfo:userInfo];
    }
    
    if (completionHandler)
    {
        if (success) {
            completionHandler(resDir.allValues, YES, nil);
        }else {
            completionHandler(nil, NO, unzippingError ? : retErr);
        }
    }
}



+ (BOOL)keepDirectoryCreateZipFileAtPath:(NSString *)outpath
                               withPaths:(NSArray *)paths
                                password:(nullable NSString *)password
                         progressHandler:(void(^ _Nullable)(NSUInteger entryNumber, NSUInteger total))progressHandler {
    
    SSZipArchive *zipArchive = [[SSZipArchive alloc] initWithPath:outpath];
    BOOL success = [zipArchive open];
    if (!success) {
        return NO;
    }
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSMutableArray *dataArr = [NSMutableArray arrayWithCapacity:0];
    for (NSString *path in paths) {
        BOOL isDir;
        if (![fileManager fileExistsAtPath:path isDirectory:&isDir]) {
            continue;
        }
        if (!isDir) {
            success &= [zipArchive writeFileAtPath:path withFileName:[path lastPathComponent] withPassword:password];
            [dataArr addObject: @{@"fileName":[path lastPathComponent],
                                  @"abspath":path,
                                  @"isDir":@(0)
                                }];
            continue;
        }
        
        // use a local fileManager (queue/thread compatibility)
        NSString *directoryPath  = path;
        NSDirectoryEnumerator *dirEnumerator = [fileManager enumeratorAtPath:directoryPath];
        NSArray<NSString *> *allObjects = dirEnumerator.allObjects;
        NSUInteger total = allObjects.count, complete = 0;
        if (!total) {
            allObjects = @[@""];
            total = 1;
        }
        for (__strong NSString *fileName in allObjects) {
            NSString *fullFilePath = [directoryPath stringByAppendingPathComponent:fileName];
            fileName = [directoryPath.lastPathComponent stringByAppendingPathComponent:fileName];
            
            BOOL isDir;
            [fileManager fileExistsAtPath:fullFilePath isDirectory:&isDir];
            if (!isDir) {
                // file
                [dataArr addObject: @{@"fileName":fileName,
                                      @"abspath":fullFilePath,
                                      @"isDir":@(0)
                                    }];
            } else {
                // directory
                if (![fileManager enumeratorAtPath:fullFilePath].nextObject) {
                    // empty directory
                    [dataArr addObject: @{@"fileName":fileName,
                                          @"abspath":fullFilePath,
                                          @"isDir":@(1)
                                        }];
                }
            }
        }
    }
    
    NSInteger complete = 0;
    for (NSDictionary *dic in dataArr) {
        if ([dic[@"isDir"] intValue] == 1) {
            success &= [zipArchive writeFolderAtPath:dic[@"abspath"] withFolderName:dic[@"fileName"] withPassword:password];
        } else {
            success &= [zipArchive writeFileAtPath:dic[@"abspath"] withFileName:dic[@"fileName"] withPassword:password];
        }
        
        if (progressHandler) {
            complete++;
            progressHandler(complete, dataArr.count);
        }
    }
    success &= [zipArchive close];
    
    return success;
}

@end
