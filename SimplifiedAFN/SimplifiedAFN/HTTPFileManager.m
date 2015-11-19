//
//  HTTPFileManager.m
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/14.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import "HTTPFileManager.h"
#import <CommonCrypto/CommonDigest.h>
#import "HTTPRequestManager.h"


#define FilePath(url)   [NSTemporaryDirectory() stringByAppendingPathComponent:transferFileNameFromURL(url)]
#define FilePath_Temp(filePath)   [filePath stringByAppendingPathExtension:@"yjh4866"]


typedef NS_ENUM(unsigned int, HTTPFileTaskStatus) {
    HTTPFileTaskStatus_Canceling = 1,
    HTTPFileTaskStatus_Waiting,
    HTTPFileTaskStatus_GetFileSize,
    HTTPFileTaskStatus_GetFileData,
    HTTPFileTaskStatus_Finished,
};

static inline NSString * KeyPathFromHTTPFileTaskStatus(HTTPFileTaskStatus state) {
    switch (state) {
        case HTTPFileTaskStatus_Canceling:
            return @"isCanceling";
        case HTTPFileTaskStatus_Waiting:
            return @"isWaiting";
        case HTTPFileTaskStatus_GetFileSize:
            return @"isGettingFileSize";
        case HTTPFileTaskStatus_GetFileData:
            return @"isGettingFileData";
        case HTTPFileTaskStatus_Finished:
            return @"isFinished";
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            return @"state";
#pragma clang diagnostic pop
        }
    }
}

// 将url转换为文件名
NSString *transferFileNameFromURL(NSString *url)
{
    if (url.length > 0) {
        // 将url字符MD5处理
        const char *cStr = [url UTF8String];
        unsigned char result[16];
        CC_MD5(cStr, (CC_LONG)strlen(cStr), result);
        NSString *fileName = [NSString stringWithFormat:
                              @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                              result[0], result[1], result[2], result[3],
                              result[4], result[5], result[6], result[7],
                              result[8], result[9], result[10], result[11],
                              result[12], result[13], result[14], result[15]];
        // 加上后缀名
        NSString *pathExtension = [[NSURL URLWithString:url] pathExtension];
        if (pathExtension.length > 0) {
            fileName = [fileName stringByAppendingPathExtension:pathExtension];
        }
        return fileName;
    }
    return @"";
}


static dispatch_queue_t httpfile_operation_headcompletion_queue() {
    static dispatch_queue_t httpfile_operation_headcompletion_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        httpfile_operation_headcompletion_queue = dispatch_queue_create("com.yjh4866.httpfile.completion.head.queue", DISPATCH_QUEUE_CONCURRENT);
    });
    return httpfile_operation_headcompletion_queue;
}
static dispatch_queue_t httpfile_operation_completion_queue() {
    static dispatch_queue_t httpfile_operation_completion_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        httpfile_operation_completion_queue = dispatch_queue_create("com.yjh4866.httpfile.completion.queue", DISPATCH_QUEUE_CONCURRENT);
    });
    return httpfile_operation_completion_queue;
}


#pragma mark - HTTPRequestManager (HTTPFileManager)

@interface HTTPRequestManager (Private)
// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据，需要取消时不可为nil
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                         progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result onCompletionQueue:(dispatch_queue_t)completionQueue;
@end
@implementation HTTPRequestManager (HTTPFileManager)
// HTTPFileManager的专用单例
+ (HTTPRequestManager *)sharedManagerForHTTPFileManger
{
    static HTTPRequestManager *sharedManagerForHTTPFileManger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManagerForHTTPFileManger = [[HTTPRequestManager alloc] init];
    });
    return sharedManagerForHTTPFileManger;
}
@end


typedef void (^Block_Void)();

#pragma mark - HTTPFileTaskOperation

@interface HTTPFileTaskOperation : NSOperation
@property (readwrite, nonatomic, strong) NSRecursiveLock *lock;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) NSString *url;
@property (nonatomic, strong) NSHTTPURLResponse *httpResponse;
@property (nonatomic, strong) NSDictionary *param;
@property (nonatomic, assign) int64_t bytesReceived;
@property (nonatomic, assign) int64_t totalBytes;
@property (nonatomic, strong) NSMutableDictionary *mdicSubTaskInfo;
@property (nonatomic, assign) int countOfExecuteSubTask;
@property (nonatomic, assign) int errCountOfSubTask;
@property (nonatomic, copy) Block_Void executeSubTask;
@property (nonatomic, assign) HTTPFileTaskStatus taskStatus;
@property (nonatomic, copy) HTTPFileProgress progress;
@property (nonatomic, copy) HTTPFileResult result;
- (instancetype)init NS_UNAVAILABLE;
@end

#pragma mark Implementation HTTPFileTaskOperation

@implementation HTTPFileTaskOperation

+ (void)networkRequestThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"yjh4866.HTTPFileTaskOperation"];
        
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }
}

+ (NSThread *)networkRequestThread {
    static NSThread *_networkRequestThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _networkRequestThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
        [_networkRequestThread start];
    });
    
    return _networkRequestThread;
}

- (instancetype)initWithFilePath:(NSString *)filePath andUrl:(NSString *)url
{
    self = [super init];
    if (self) {
        self.filePath = filePath;
        self.url = url;
        _taskStatus = HTTPFileTaskStatus_Waiting;
        self.countOfExecuteSubTask = 0;
        
        self.lock = [[NSRecursiveLock alloc] init];
        self.lock.name = @"com.yjh4866.HTTPFileTaskOperation.lock";
        
        __weak typeof(self) weakSelf = self;
        self.executeSubTask = ^() {
            [weakSelf.lock lock];
            // 一共下载两次，即下载失败可以再试一次
            if (weakSelf.countOfExecuteSubTask < 2) {
                // 启动线程以执行子任务
                [weakSelf performSelector:@selector(operationDidStart) onThread:[HTTPFileTaskOperation networkRequestThread] withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
            }
            // 下载失败
            else {
                // 文件下载任务结束
                weakSelf.taskStatus = HTTPFileTaskStatus_Finished;
                // GCD异步通过dispatch_get_main_queue回调
                __strong typeof(weakSelf) strongSelf = weakSelf;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (strongSelf.result) {
                        NSError *error = [NSError errorWithDomain:@"HTTPFileManager" code:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"未下载完成"]}];
                        strongSelf.result(nil, strongSelf.httpResponse, error, strongSelf.param);
                    }
                });
            }
            [weakSelf.lock unlock];
        };
    }
    return self;
}

- (void)dealloc
{
    
}

- (void)setTaskStatus:(HTTPFileTaskStatus)taskStatus {
    [self.lock lock];
    NSString *oldStateKey = KeyPathFromHTTPFileTaskStatus(self.taskStatus);
    NSString *newStateKey = KeyPathFromHTTPFileTaskStatus(taskStatus);
    
    // 下面这四行KVO代码很重要，用以通知Operation任务状态变更
    [self willChangeValueForKey:newStateKey];
    [self willChangeValueForKey:oldStateKey];
    _taskStatus = taskStatus;
    [self didChangeValueForKey:oldStateKey];
    [self didChangeValueForKey:newStateKey];
    [self.lock unlock];
}

- (BOOL)isCancelled
{
    return HTTPFileTaskStatus_Canceling == self.taskStatus;
}
- (BOOL)isExecuting
{
    return ((HTTPFileTaskStatus_GetFileSize == self.taskStatus) ||
            (HTTPFileTaskStatus_GetFileData == self.taskStatus));
}
- (BOOL)isFinished
{
    return HTTPFileTaskStatus_Finished == self.taskStatus;
}

- (void)start
{
    [self.lock lock];
    [super start];
    BOOL needHeadRequest = YES;
    // 如果临时文件存在，则从中提取任务信息并添加到下载队列
    NSString *filePathTemp = FilePath_Temp(self.filePath);
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePathTemp]) {
        // 先获取实际文件大小（实际文件大小+配置数据+8字节的实际文件大小）
        int64_t fileSize = 0;
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePathTemp];
        int64_t tempFileSize = [fileHandle seekToEndOfFile];
        [fileHandle seekToFileOffset:tempFileSize-8];
        NSData *dataFileSize = [fileHandle readDataOfLength:8];
        [dataFileSize getBytes:&fileSize length:8];
        self.totalBytes = fileSize;
        // 再获取任务信息数据
        [fileHandle seekToFileOffset:fileSize];
        NSData *dataTaskInfo = [fileHandle readDataOfLength:tempFileSize-fileSize-8];
        [fileHandle closeFile];
        // 解析成字典，即为子任务字典
        self.mdicSubTaskInfo = [NSJSONSerialization JSONObjectWithData:dataTaskInfo options:NSJSONReadingMutableContainers error:nil];
        // 任务信息数据为字典
        if (self.mdicSubTaskInfo && [self.mdicSubTaskInfo isKindOfClass:NSDictionary.class]) {
            needHeadRequest = NO;
            // 计算当前进度
            self.bytesReceived = self.totalBytes;
            for (NSDictionary *dicSubTask in self.mdicSubTaskInfo.allValues) {
                self.bytesReceived -= [dicSubTask[@"Len"] intValue];
            }
            // 告知当前进度
            int64_t bytesReceived = self.bytesReceived;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.progress) {
                    self.progress(bytesReceived, self.totalBytes, self.param);
                }
            });
            // 执行子任务
            self.taskStatus = HTTPFileTaskStatus_GetFileData;
            self.executeSubTask();
        }
        else {
            self.mdicSubTaskInfo = nil;
            [[NSFileManager defaultManager] removeItemAtPath:filePathTemp error:nil];
        }
    }
    // 先获取文件大小
    if (needHeadRequest) {
        self.taskStatus = HTTPFileTaskStatus_GetFileSize;
        // 创建URLRequest
        NSMutableURLRequest *mURLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.url]];
        [mURLRequest setHTTPMethod:@"HEAD"];
        [mURLRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
        [mURLRequest setValue:@"" forHTTPHeaderField:@"Accept-Encoding"];
        // 获取文件大小
        [[HTTPRequestManager sharedManager] requestWebDataWithRequest:mURLRequest param:@{@"Type": @"HEAD", @"url": self.url} progress:nil andResult:^(NSHTTPURLResponse *httpResponse, NSData *webData, NSError *error, NSDictionary *dicParam) {
            self.httpResponse = httpResponse;
            // 存在错误，或数据长度过短，则结束
            if (error || httpResponse.expectedContentLength < 1) {
                // 文件下载任务结束
                self.taskStatus = HTTPFileTaskStatus_Finished;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.result) {
                        self.result(self.filePath, self.httpResponse, error, self.param);
                    }
                });
            }
            else {
                self.totalBytes = httpResponse.expectedContentLength;
                // 通过下载进度提示总大小
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.progress) {
                        self.progress(0, self.totalBytes, self.param);
                    }
                });
                // 生成子任务列表
                int64_t fileSize = self.httpResponse.expectedContentLength;
                const int sizePartFile = 256*1024;
                self.mdicSubTaskInfo = [NSMutableDictionary dictionary];
                unsigned int subTaskCount = ceilf(1.0f*fileSize/sizePartFile); // 每一个任务项大小
                unsigned int subTaskLen = ceilf(1.0f*fileSize/subTaskCount);
                for (int i = 0; i < subTaskCount-1; i++) {
                    [self.mdicSubTaskInfo setObject:[NSMutableDictionary dictionaryWithDictionary:@{@"Len": @(subTaskLen)}] forKey:[NSString stringWithFormat:@"%@", @(i*subTaskLen)]];
                }
                unsigned int startLast = (subTaskCount-1)*subTaskLen;
                [self.mdicSubTaskInfo setValue:[NSMutableDictionary dictionaryWithDictionary:@{@"Len": @(fileSize-startLast)}] forKey:[NSString stringWithFormat:@"%@", @(startLast)]];
                
                // 生成临时文件
                NSString *filePathTemp = FilePath_Temp(self.filePath);
                [[NSFileManager defaultManager] createFileAtPath:filePathTemp contents:nil attributes:nil];
                // 保存临时文件数据
                NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePathTemp];
                // 跳过实际文件数据区，保存任务信息
                [fileHandle seekToFileOffset:fileSize];
                NSData *dataTaskInfo = [NSJSONSerialization dataWithJSONObject:self.mdicSubTaskInfo options:NSJSONWritingPrettyPrinted error:nil];
                [fileHandle writeData:dataTaskInfo];
                // 保存文件大小
                [fileHandle seekToFileOffset:fileSize+dataTaskInfo.length];
                [fileHandle writeData:[NSData dataWithBytes:&fileSize length:8]];
                // 掐掉可能多余的数据
                [fileHandle truncateFileAtOffset:fileSize+dataTaskInfo.length+8];
                [fileHandle closeFile];
                
                // 执行子任务
                self.executeSubTask();
            }
        } onCompletionQueue:httpfile_operation_headcompletion_queue()];
    }
    [self.lock unlock];
}

- (void)operationDidStart {
    [self.lock lock];
    
    self.countOfExecuteSubTask += 1;
    self.errCountOfSubTask = 0;
    self.bytesReceived = self.totalBytes;
    // 遍历子任务并启动下载
    for (NSString *strKey in self.mdicSubTaskInfo.allKeys) {
        NSMutableDictionary *mdicSubTask = self.mdicSubTaskInfo[strKey];
        self.bytesReceived -= [mdicSubTask[@"Len"] intValue];
        // 创建URLRequest
        NSMutableURLRequest *mURLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.url]];
        [mURLRequest setValue:[NSString stringWithFormat:@"bytes=%@-%@", strKey, @([strKey intValue]+[mdicSubTask[@"Len"] intValue]-1)] forHTTPHeaderField:@"RANGE"];
        [mURLRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
        [mURLRequest setValue:@"" forHTTPHeaderField:@"Accept-Encoding"];
        // 下载文件段
        [[HTTPRequestManager sharedManagerForHTTPFileManger] requestWebDataWithRequest:mURLRequest param:@{@"url": self.url, @"Start": strKey, @"Len": mdicSubTask[@"Len"]} progress:nil andResult:^(NSHTTPURLResponse *httpResponse, NSData *webData, NSError *error, NSDictionary *dicParam) {
            [self.lock lock];
            // 下载成功
            if (nil == error) {
                // 将下载到的数据保存到临时文件
                NSString *filePathTemp = FilePath_Temp(self.filePath);
                NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePathTemp];
                [fileHandle seekToFileOffset:[strKey intValue]];
                [fileHandle writeData:webData];
                // 删除该子任务
                [self.mdicSubTaskInfo removeObjectForKey:dicParam[@"Start"]];
                // 还存在未完成的子任务，更新任务进度
                if (self.mdicSubTaskInfo.count > 0) {
                    self.bytesReceived += [dicParam[@"Len"] intValue];
                    // 将任务进度更新到文件
                    [fileHandle seekToFileOffset:self.totalBytes];
                    NSData *dataTaskInfo = [NSJSONSerialization dataWithJSONObject:self.mdicSubTaskInfo options:NSJSONWritingPrettyPrinted error:nil];
                    [fileHandle writeData:dataTaskInfo];
                    // 保存文件大小
                    [fileHandle seekToFileOffset:self.totalBytes+dataTaskInfo.length];
                    int64_t fileSize = self.totalBytes;
                    [fileHandle writeData:[NSData dataWithBytes:&fileSize length:8]];
                    // 掐掉可能多余的数据
                    [fileHandle truncateFileAtOffset:fileSize+dataTaskInfo.length+8];
                    [fileHandle closeFile];
                    // 文件下载进度变更
                    int64_t bytesReceived = self.bytesReceived;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.progress) {
                            self.progress(bytesReceived, self.totalBytes, self.param);
                        }
                    });
                    // 错误的子任务数量，与剩余子任务数量相同，则所有子任务均已完成，再次执行子任务
                    if (self.mdicSubTaskInfo.count == self.errCountOfSubTask) {
                        self.executeSubTask();
                    }
                }
                else {
                    // 掐掉下载进度相关数据
                    [fileHandle truncateFileAtOffset:self.totalBytes];
                    [fileHandle closeFile];
                    // 将临时文件修改为正式文件
                    [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:nil];
                    [[NSFileManager defaultManager] moveItemAtPath:filePathTemp toPath:self.filePath error:nil];
                    // 文件下载任务结束
                    self.taskStatus = HTTPFileTaskStatus_Finished;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.result) {
                            self.result(self.filePath, self.httpResponse, nil, self.param);
                        }
                    });
                }
            }
            // 下载失败
            else {
                self.errCountOfSubTask += 1;
                // 错误的子任务数量，与剩余子任务数量相同，则所有子任务均已完成
                if (self.mdicSubTaskInfo.count == self.errCountOfSubTask) {
                    self.executeSubTask();
                }
            }
            [self.lock unlock];
        } onCompletionQueue:httpfile_operation_completion_queue()];
    }
    [self.lock unlock];
}

@end


#pragma mark - HTTPFileManager

@interface HTTPFileManager ()
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (readwrite, nonatomic, strong) NSLock *lock;
@end

#pragma mark Implementation HTTPFileManager

@implementation HTTPFileManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.operationQueue = [[NSOperationQueue alloc] init];
        self.operationQueue.maxConcurrentOperationCount = 1;
        
        self.lock = [[NSLock alloc] init];
        self.lock.name = @"com.yjh4866.HTTPFileManager.lock";
    }
    return self;
}

- (void)dealloc
{
}

// 通用对象
+ (HTTPFileManager *)sharedManager
{
    static HTTPFileManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[HTTPFileManager alloc] init];
    });
    return sharedManager;
}

// 下载文件到指定路径
- (void)downloadFile:(NSString *)filePath from:(NSString *)url withParam:(NSDictionary *)dicParam
            progress:(HTTPFileProgress)progress andResult:(HTTPFileResult)result
{
    [self.lock lock];
    // 先查一下下载任务是否已经存在
    for (HTTPFileTaskOperation *operation in self.operationQueue.operations) {
        // 参数相等，且未取消未完成
        if ([operation.param isEqualToDictionary:dicParam] &&
            !operation.isCancelled && !operation.finished) {
            return ;
        }
    }
    // 未给定文件保存路径，则生成一个临时路径
    if (nil == filePath) {
        filePath = FilePath(url);
    }
    // 创建Operation
    HTTPFileTaskOperation *operation = [[HTTPFileTaskOperation alloc] initWithFilePath:filePath andUrl:url];
    operation.progress = progress;
    operation.result = result;
    operation.param = dicParam;
    [self.operationQueue addOperation:operation];
    [self.lock unlock];
}

@end
