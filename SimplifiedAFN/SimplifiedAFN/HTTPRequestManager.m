//
//  HTTPRequestManager.m
//
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import "HTTPRequestManager.h"
#import <UIKit/UIKit.h>


#pragma mark -
#pragma mark - NSURLConnection方案
#pragma mark -

static dispatch_group_t urlconnection_operation_completion_group() {
    static dispatch_group_t urlconnection_operation_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        urlconnection_operation_completion_group = dispatch_group_create();
    });
    
    return urlconnection_operation_completion_group;
}

static dispatch_queue_t urlconnection_operation_completion_queue() {
    static dispatch_queue_t urlconnection_operation_completion_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        urlconnection_operation_completion_queue = dispatch_queue_create("com.yjh4866.urlconnection.completion", DISPATCH_QUEUE_CONCURRENT );
    });
    
    return urlconnection_operation_completion_queue;
}

static dispatch_group_t http_request_operation_completion_group() {
    static dispatch_group_t http_request_operation_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        http_request_operation_completion_group = dispatch_group_create();
    });
    
    return http_request_operation_completion_group;
}

static dispatch_queue_t http_request_operation_processing_queue() {
    static dispatch_queue_t http_request_operation_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        http_request_operation_processing_queue = dispatch_queue_create("com.yjh4866.http_request.processing", DISPATCH_QUEUE_CONCURRENT);
    });
    
    return http_request_operation_processing_queue;
}

typedef NS_ENUM(unsigned int, URLConnectionStatus) {
    URLConnectionStatus_Canceling,
    URLConnectionStatus_Waiting,
    URLConnectionStatus_Running,
    URLConnectionStatus_Finished,
};

static inline NSString * KeyPathFromHTTPTaskStatus(URLConnectionStatus state) {
    switch (state) {
        case URLConnectionStatus_Canceling:
            return @"isCanceling";
        case URLConnectionStatus_Waiting:
            return @"isWaiting";
        case URLConnectionStatus_Running:
            return @"isRunning";
        case URLConnectionStatus_Finished:
            return @"isFinished";
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            return @"state";
#pragma clang diagnostic pop
        }
    }
}


#pragma mark - URLConnectionOperation

@interface URLConnectionOperation : NSOperation
@property (nonatomic, readonly) NSURLRequest *request;
@property (nonatomic, readonly) NSHTTPURLResponse *httpResponse;
@property (nonatomic, strong) NSDictionary *param;
@property (nonatomic, readonly) URLConnectionStatus taskStatus;
- (instancetype)init NS_UNAVAILABLE;
@end


#pragma mark - URLConnectionOperation ()

@interface URLConnectionOperation () <NSURLConnectionDataDelegate> {
    NSMutableData *_mdataCache;
}
@property (readwrite, nonatomic, strong) NSRecursiveLock *lock;
@property (readwrite, nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) NSHTTPURLResponse *httpResponse;
@property (readwrite, nonatomic, strong) NSURLConnection *urlConnection;
@property (nonatomic, copy) HTTPRequestProgress progress;
@property (readwrite, nonatomic, strong) NSError *error;
@property (readwrite, nonatomic, assign) URLConnectionStatus taskStatus;
@end


#pragma mark - Implementation URLConnectionOperation

@implementation URLConnectionOperation

+ (void)networkRequestThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"yjh4866"];
        
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

- (instancetype)initWithURLRequest:(NSURLRequest *)urlRequest
{
    self = [super init];
    if (self) {
        _mdataCache = [[NSMutableData alloc] init];
        self.request = urlRequest;
        _taskStatus = URLConnectionStatus_Waiting;
        
        self.lock = [[NSRecursiveLock alloc] init];
        self.lock.name = @"com.yjh4866.URLConnectionOperation.lock";
    }
    return self;
}

- (void)dealloc
{
#if __has_feature(objc_arc)
#else
    self.request = nil;
    self.param = nil;
    self.urlConnection = nil;
    self.progress = nil;
    self.error = nil;
    [_mdataCache release];
    [super dealloc];
#endif
}

- (void)setTaskStatus:(URLConnectionStatus)taskStatus {
    [self.lock lock];
    NSString *oldStateKey = KeyPathFromHTTPTaskStatus(self.taskStatus);
    NSString *newStateKey = KeyPathFromHTTPTaskStatus(taskStatus);
    
    // 下面这四行KVO代码很重要，用以通知Operation任务状态变更
    [self willChangeValueForKey:newStateKey];
    [self willChangeValueForKey:oldStateKey];
    _taskStatus = taskStatus;
    [self didChangeValueForKey:oldStateKey];
    [self didChangeValueForKey:newStateKey];
    [self.lock unlock];
}

- (int64_t)totalBytes
{
    return [self.httpResponse.allHeaderFields[@"Content-Length"] longLongValue];
}

#pragma mark NSOperation

// 这里是为了让该NSOperation能正常释放，不然会在setHTTPRequestResult:中的block循环引用
- (void)setCompletionBlock:(void (^)(void))block {
    [self.lock lock];
    if (!block) {
        [super setCompletionBlock:nil];
    } else {
#if __has_feature(objc_arc)
        __weak __typeof(self)weakSelf = self;
        [super setCompletionBlock:^ {
            
            dispatch_group_t group = urlconnection_operation_completion_group();
            
            dispatch_group_async(group, dispatch_get_main_queue(), ^{
                block();
            });
            
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            dispatch_group_notify(group, urlconnection_operation_completion_queue(), ^{
                [strongSelf setCompletionBlock:nil];
            });
        }];
#else
        [super setCompletionBlock:^ {
            
            dispatch_group_t group = urlconnection_operation_completion_group();
            
            dispatch_group_async(group, dispatch_get_main_queue(), ^{
                block();
            });
            
            dispatch_group_notify(group, urlconnection_operation_completion_queue(), ^{
                [super setCompletionBlock:nil];
            });
        }];
#endif
    }
    [self.lock unlock];
}

- (BOOL)isCancelled
{
    return URLConnectionStatus_Canceling == self.taskStatus;
}
- (BOOL)isExecuting
{
    return URLConnectionStatus_Running == self.taskStatus;
}
- (BOOL)isFinished
{
    return URLConnectionStatus_Finished == self.taskStatus;
}

- (void)start
{
    [self.lock lock];
    self.taskStatus = URLConnectionStatus_Running;
    [self performSelector:@selector(operationDidStart) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
    [self.lock unlock];
}

- (void)operationDidStart {
    [self.lock lock];
    // 用NSURLConnection创建网络连接
#if __has_feature(objc_arc)
    self.urlConnection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
#else
    self.urlConnection = [[[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO] autorelease];
#endif
    // 启动网络连接
    [self.urlConnection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [self.urlConnection start];
    [self.lock unlock];
}

- (void)cancel
{
    [self.lock lock];
    [super cancel];
    self.taskStatus = URLConnectionStatus_Canceling;
    [self.lock unlock];
}

- (void)setHTTPRequestResult:(HTTPRequestResult)result
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
#pragma clang diagnostic ignored "-Wgnu"
    self.completionBlock = ^{
        dispatch_async(http_request_operation_processing_queue(), ^{
            if (result) {
                dispatch_group_async(http_request_operation_completion_group(), dispatch_get_main_queue(), ^{
                    result(self.httpResponse, _mdataCache, self.error, self.param);
                });
            }
        });
    };
#pragma clang diagnostic pop
}


#pragma mark NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self.lock lock];
    self.error = error;
    self.urlConnection = nil;
    self.taskStatus = URLConnectionStatus_Finished;
    [self.lock unlock];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.httpResponse = nil;
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        self.httpResponse = (NSHTTPURLResponse *)response;
    }
    // 通过下载进度提示总大小
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progress) {
            self.progress(nil, 0, self.totalBytes, self.param);
        }
    });
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // 追加数据
    [self.lock lock];
    [_mdataCache appendData:data];
    [self.lock unlock];
    // 下载进度更新
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progress) {
            self.progress(data, _mdataCache.length, self.totalBytes, self.param);
        }
    });
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self.lock lock];
    self.urlConnection = nil;
    self.taskStatus = URLConnectionStatus_Finished;
    [self.lock unlock];
}

@end


#pragma mark -
#pragma mark - NSURLSessionDataTask方案
#pragma mark -

static dispatch_queue_t urlsession_creation_queue() {
    static dispatch_queue_t urlsession_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        urlsession_creation_queue = dispatch_queue_create("com.yjh4866.urlsession.creation", DISPATCH_QUEUE_SERIAL);
    });
    
    return urlsession_creation_queue;
}

static dispatch_group_t urlsession_completion_group() {
    static dispatch_group_t urlsession_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        urlsession_completion_group = dispatch_group_create();
    });
    
    return urlsession_completion_group;
}


#pragma mark URLSessionTaskItem

@interface URLSessionTaskItem : NSObject
@property (nonatomic, strong) NSURLSessionDataTask *urlSessionTask;
@property (readwrite, nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) NSHTTPURLResponse *httpResponse;
@property (nonatomic, strong) NSMutableData *mdataCache;
@property (nonatomic, copy) HTTPRequestProgress progress;
@property (nonatomic, copy) HTTPRequestResult result;
@property (nonatomic, strong) NSDictionary *param;
@end


#pragma mark Implementation URLSessionTaskItem

@implementation URLSessionTaskItem
- (instancetype)init
{
    self = [super init];
    if (self) {
#if __has_feature(objc_arc)
        self.mdataCache = [[NSMutableData alloc] init];
#else
        self.mdataCache = [[[NSMutableData alloc] init] autorelease];
#endif
    }
    return self;
}
- (void)dealloc
{
#if __has_feature(objc_arc)
#else
    self.urlSessionTask = nil;
    self.request = nil;
    self.httpResponse = nil;
    self.mdataCache = nil;
    self.progress = nil;
    self.result = nil;
    self.param = nil;
    [super dealloc];
#endif
}
- (int64_t)totalBytes
{
    return [self.httpResponse.allHeaderFields[@"Content-Length"] longLongValue];
}
@end


#pragma mark - HTTPRequestManager ()

@interface HTTPRequestManager () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (readwrite, nonatomic, strong) NSURLSession *urlSession;
@property (readwrite, nonatomic, strong) NSMutableDictionary *mdicTaskItemForTaskIdentifier;
@property (readwrite, nonatomic, strong) NSLock *lock;
@end


#pragma mark - Implementation HTTPRequestManager

@implementation HTTPRequestManager

- (instancetype)init
{
    self = [super init];
    if (self) {
#if __has_feature(objc_arc)
        self.operationQueue = [[NSOperationQueue alloc] init];
#else
        self.operationQueue = [[[NSOperationQueue alloc] init] autorelease];
#endif
        if ([[UIDevice currentDevice].systemVersion floatValue] >= 7.0) {
            self.urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:self.operationQueue];
            self.mdicTaskItemForTaskIdentifier = [[NSMutableDictionary alloc] init];
            self.lock = [[NSLock alloc] init];
            self.lock.name = @"com.yjh4866.HTTPRequestManager.lock";
        }
    }
    return self;
}

- (void)dealloc
{
#if __has_feature(objc_arc)
#else
    self.operationQueue = nil;
    self.urlSession = nil;
    self.mdicTaskItemForTaskIdentifier = nil;
    self.lock = nil;
    [super dealloc];
#endif
}

// 通用对象
+ (HTTPRequestManager *)sharedManager
{
    static HTTPRequestManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[HTTPRequestManager alloc] init];
    });
    return sharedManager;
}

// 根据url获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataFromURL:(NSString *)url withParam:(NSDictionary *)dicParam
                    andResult:(HTTPRequestResult)result
{
    return [self requestWebDataFromURL:url withParam:dicParam progress:nil andResult:result];
}

// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                        andResult:(HTTPRequestResult)result
{
    return [self requestWebDataWithRequest:request param:dicParam progress:nil andResult:result];
}

// 根据url获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataFromURL:(NSString *)url withParam:(NSDictionary *)dicParam
                     progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result
{
    // 实例化NSMutableURLRequest
    NSMutableURLRequest *mURLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [mURLRequest setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
    [mURLRequest setTimeoutInterval:10.0f];
    // 开始请求数据
    return [self requestWebDataWithRequest:mURLRequest param:dicParam progress:progress andResult:result];
}

// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                         progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result
{
    if (self.urlSession) {
        [self.lock lock];
        // 先查一下是否已经存在
        for (URLSessionTaskItem *taskItem in self.mdicTaskItemForTaskIdentifier.allValues) {
            // 参数相等，且未取消未完成
            if ([taskItem.param isEqualToDictionary:dicParam] &&
                NSURLSessionTaskStateCanceling != taskItem.urlSessionTask.state &&
                NSURLSessionTaskStateCompleted != taskItem.urlSessionTask.state) {
                return NO;
            }
        }
        [self.lock unlock];
        // 创建NSURLSessionDataTasks
        __block NSURLSessionDataTask *urlSessionTask = nil;
        dispatch_sync(urlsession_creation_queue(), ^{
            urlSessionTask = [self.urlSession dataTaskWithRequest:request];
        });
        // 配备Delegate
        URLSessionTaskItem *taskItem = [[URLSessionTaskItem alloc] init];
        taskItem.urlSessionTask = urlSessionTask;
        taskItem.progress = progress;
        taskItem.result = result;
        taskItem.param = dicParam;
        [self.lock lock];
        self.mdicTaskItemForTaskIdentifier[@(urlSessionTask.taskIdentifier)] = taskItem;
        [self.lock unlock];
#if __has_feature(objc_arc)
#else
        [taskItem release];
#endif
        // 启动网络连接
        [urlSessionTask resume];
    }
    else {
        // 先查一下是否已经存在
        for (URLConnectionOperation *operation in self.operationQueue.operations) {
            // 参数相等，且未取消未完成
            if ([operation.param isEqualToDictionary:dicParam] &&
                !operation.isCancelled && !operation.finished) {
                return NO;
            }
        }
        // 创建Operation
        URLConnectionOperation *operation = [[URLConnectionOperation alloc] initWithURLRequest:request];
        operation.progress = progress;
        operation.param = dicParam;
        [operation setHTTPRequestResult:result];
        [self.operationQueue addOperation:operation];
#if __has_feature(objc_arc)
#else
        [operation release];
#endif
    }
    return YES;
}


#pragma mark NSURLSessionDelegate

/* The last message a session receives.  A session will only become
 * invalid because of a systemic error or when it has been
 * explicitly invalidated, in which case the error parameter will be nil.
 */
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
    [self.lock lock];
    // 所有请求均出错
    dispatch_group_async(urlsession_completion_group(), dispatch_get_main_queue(), ^{
        for (URLSessionTaskItem *taskItem in self.mdicTaskItemForTaskIdentifier.allValues) {
            if (taskItem.result) {
                taskItem.result(taskItem.httpResponse, taskItem.mdataCache, error, taskItem.param);
            }
        }
    });
    [self.mdicTaskItemForTaskIdentifier removeAllObjects];
    [self.lock unlock];
}

#pragma mark NSURLSessionTaskDelegate

/* Sent as the last message related to a specific task.  Error may be
 * nil, which implies that no error occurred and this task is complete.
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    [self.lock lock];
    URLSessionTaskItem *taskItem = self.mdicTaskItemForTaskIdentifier[@(task.taskIdentifier)];
    [self.lock unlock];
    // 通知处理结果
    dispatch_group_async(urlsession_completion_group(), dispatch_get_main_queue(), ^{
        if (taskItem.result) {
            taskItem.result(taskItem.httpResponse, taskItem.mdataCache, error, taskItem.param);
        }
    });
    [self.lock lock];
    [self.mdicTaskItemForTaskIdentifier removeObjectForKey:@(task.taskIdentifier)];
    [self.lock unlock];
}


#pragma mark NSURLSessionDataDelegate

// The task has received a response
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    [self.lock lock];
    URLSessionTaskItem *taskItem = self.mdicTaskItemForTaskIdentifier[@(dataTask.taskIdentifier)];
    [self.lock unlock];
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        taskItem.httpResponse = (NSHTTPURLResponse *)response;
    }
    // 通过下载进度提示总大小
    dispatch_group_async(urlsession_completion_group(), dispatch_get_main_queue(), ^{
        if (taskItem.progress) {
            taskItem.progress(nil, 0, taskItem.totalBytes, taskItem.param);
        }
    });
    
    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    [self.lock lock];
    URLSessionTaskItem *taskItem = self.mdicTaskItemForTaskIdentifier[@(dataTask.taskIdentifier)];
    [self.lock unlock];
    // 追加数据
    [taskItem.mdataCache appendData:data];
    // 下载进度更新
    dispatch_group_async(urlsession_completion_group(), dispatch_get_main_queue(), ^{
        if (taskItem.progress) {
            taskItem.progress(data, taskItem.mdataCache.length, taskItem.totalBytes, taskItem.param);
        }
    });
}

@end
