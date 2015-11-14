//
//  HTTPRequestManager.h
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  HTTP请求结果
 *
 *  @param httpResponse HTTP响应对象NSHTTPURLResponse
 *  @param webData      请求到数据
 *  @param error        发生的错误。nil表示成功
 *  @param dicParam     回传对象
 */
typedef void (^HTTPRequestResult)(NSHTTPURLResponse *httpResponse, NSData *webData,
                                  NSError *error, NSDictionary *dicParam);
/**
 *  HTTP请求进度
 *
 *  @param webData       webData为nil表示收到响应
 *  @param bytesReceived 已接收到的数据长度
 *  @param totalBytes    数据总长度。-1表示长度未知
 *  @param dicParam      回传对象
 */
typedef void (^HTTPRequestProgress)(NSData *webData, int64_t bytesReceived,
                                    int64_t totalBytes, NSDictionary *dicParam);


/* 保留[[HTTPRequestManager alloc] init]的实例化方案。
   可以使用默认的单例请求数据，也可以另外实例化以与默认的单例对象区分开
 */
@interface HTTPRequestManager : NSObject

// 通用对象
+ (HTTPRequestManager *)sharedManager;

// 根据url获取Web数据
// dicParam 可用于回传数据，需要取消时不可为nil
- (BOOL)requestWebDataFromURL:(NSString *)url withParam:(NSDictionary *)dicParam
                    andResult:(HTTPRequestResult)result;

// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据，需要取消时不可为nil
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                        andResult:(HTTPRequestResult)result;

// 根据url获取Web数据
// dicParam 可用于回传数据，需要取消时不可为nil
- (BOOL)requestWebDataFromURL:(NSString *)url withParam:(NSDictionary *)dicParam
                     progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result;

// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据，需要取消时不可为nil
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                         progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result;

// 取消网络请求
- (void)cancelRequestWithParam:(NSDictionary *)dicParam;

@end
