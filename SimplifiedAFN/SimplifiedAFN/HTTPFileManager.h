//
//  HTTPFileManager.h
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/14.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import <Foundation/Foundation.h>

// 将url转换为文件名
NSString *transferFileNameFromURL(NSString *url);

/**
 *  HTTP文件下载进度
 *
 *  @param bytesReceived 已接收到的数据长度
 *  @param totalBytes    数据总长度。-1表示长度未知
 *  @param dicParam      回传对象
 */
typedef void (^HTTPFileProgress)(int64_t bytesReceived, int64_t totalBytes,
                                 NSDictionary *dicParam);
/**
 *  HTTP文件下载结果
 *
 *  @param filePath     文件保存路径
 *  @param httpResponse HTTP响应对象NSHTTPURLResponse
 *  @param error        发生的错误。nil表示成功
 *  @param dicParam     回传对象
 */
typedef void (^HTTPFileResult)(NSString *filePath, NSHTTPURLResponse *httpResponse,
                               NSError *error, NSDictionary *dicParam);


/* 保留[[HTTPFileManager alloc] init]的实例化方案。
 可以使用默认的单例请求数据，也可以另外实例化以与默认的单例对象区分开
 */
@interface HTTPFileManager : NSObject

// 通用对象
+ (HTTPFileManager *)sharedManager;

// 下载文件到指定路径
- (void)downloadFile:(NSString *)filePath from:(NSString *)url withParam:(NSDictionary *)dicParam
            progress:(HTTPFileProgress)progress andResult:(HTTPFileResult)result;

@end
