//
//  HTTPRequestManager.h
//
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^HTTPRequestResult)(NSHTTPURLResponse *httpResponse, NSData *webData,
                                  NSError *error, NSDictionary *dicParam);
// webData为nil表示收到响应，totalBytes为数据总长度
typedef void (^HTTPRequestProgress)(NSData *webData, int64_t bytesReceived,
                                    int64_t totalBytes, NSDictionary *dicParam);


/* 保留[[HTTPRequestManager alloc] init]的实例化方案。
   可以使用默认的单例请求数据，也可以另外实例化以与默认的单例对象区分开
 */
@interface HTTPRequestManager : NSObject

// 通用对象
+ (HTTPRequestManager *)sharedManager;

// 根据url获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataFromURL:(NSString *)url withParam:(NSDictionary *)dicParam
                    andResult:(HTTPRequestResult)result;

// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                        andResult:(HTTPRequestResult)result;

// 根据url获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataFromURL:(NSString *)url withParam:(NSDictionary *)dicParam
                     progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result;

// 根据NSURLRequest获取Web数据
// dicParam 可用于回传数据
- (BOOL)requestWebDataWithRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                         progress:(HTTPRequestProgress)progress andResult:(HTTPRequestResult)result;

@end
