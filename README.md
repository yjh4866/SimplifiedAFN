# SimplifiedAFN
SimplifiedAFN是精简化的AFNetworking，同时增加了去重功能，并在功能实现中对系统版本做了兼容。

大多数的app开发主要用GET请求，偶尔会用到POST，HEAD、PUT等很少能用到。而AFNetworking太过庞大，绝大多数的功能又用不到，对于需要精简ipa包大小的开发者还是比较头疼的。

如果是做SDK开发，用AFNetworking基本是不可行方案。一方面会增加SDK包的大小，另一方面也很容易与app或其他SDK包冲突，改类名则需要修改相当众多的类。还有比较重要的一点，不能放弃iOS6的兼容，毕竟有开发者要求适配iOS6，用AFNetwoking的话每次请求都得做系统版本的判断。基于种种方面的原因，提供SimplifiedAFN以做参考。

iOS7以下使用NSURLConnection进行网络连接，iOS7及以上使用NSURLSession。

## HTTPRequestManager
提供单例方法**sharedManager**，但也保留[[HTTPRequestManager alloc] init]的实例化方法。

首先定义了两个block

第一个用于返回HTTP请求结果。error为nil表示请求成功
~~~
typedef void (^HTTPRequestResult)(NSHTTPURLResponse *httpResponse, 
                                  NSData *webData, NSError *error, 
                                  NSDictionary *dicParam);
~~~
第二个用于请求进度回调。webData为nil表示收到响应
~~~
typedef void (^HTTPRequestProgress)(NSData *webData, int64_t bytesReceived, 
                                    int64_t totalBytes, NSDictionary *dicParam);
~~~


### 获取指定url的网页数据
这个接口是最常用的接口。dicParam用于result回传参数，可为nil
~~~
- (BOOL)requestWebDataFromURL:(NSString *)url 
                    withParam:(NSDictionary *)dicParam
                    andResult:(HTTPRequestResult)result;
~~~






