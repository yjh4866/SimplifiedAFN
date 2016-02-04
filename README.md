# SimplifiedAFN
SimplifiedAFN是精简化的AFNetworking，同时增加了去重功能，并在功能实现中对系统版本做了兼容。

大多数的app开发主要用GET请求，偶尔会用到POST，HEAD、PUT等很少能用到。而AFNetworking太过庞大，绝大多数的功能又用不到，对于需要精简ipa包大小的开发者还是比较头疼的。

如果是做SDK开发，用AFNetworking基本是不可行方案。一方面会增加SDK包的大小，另一方面也很容易与app或其他SDK包冲突，改类名则需要修改相当众多的类。还有比较重要的一点，不能放弃iOS6的兼容，毕竟有开发者要求适配iOS6，用AFNetwoking的话每次请求都得做系统版本的判断。基于种种方面的原因，提供SimplifiedAFN以做参考。

iOS7以下使用NSURLConnection进行网络连接，iOS7及以上使用NSURLSession。

## NBLHTTPManager
提供单例方法**sharedManager**，但也保留[[NBLHTTPManager alloc] init]的实例化方法。

- 首先定义了一个枚举类型，以设定返回对象的类型

    ```
    typedef NS_ENUM(unsigned int, NBLResponseObjectType){
        // 普通NSData数据
        NBLResponseObjectType_Data = 0,
        // NSString
        NBLResponseObjectType_String,
        // JSON对象，一般是NSDictionary或NSArray
        NBLResponseObjectType_JSON
    };
    ```

- 然后定义了两个block：

    第一个用于返回HTTP请求结果。error为nil表示请求成功

    ```
    typedef void (^NBLHTTPResult)(NSHTTPURLResponse *httpResponse, id responseObject,
	                              NSError *error, NSDictionary *dicParam);
    ```

    第二个用于请求进度回调。webData为nil表示收到响应

    ```
    typedef void (^NBLHTTPProgress)(NSData *webData, int64_t bytesReceived,
                                    int64_t totalBytes, NSDictionary *dicParam);

    ```


- 获取指定url的网页数据

    这个接口是最常用的接口，以**GET**方式从指定url获取数据。dicParam用于result回传参数，可为nil

    ```
    - (BOOL)requestObject:(NBLResponseObjectType)resObjType fromURL:(NSString *)url
                withParam:(NSDictionary *)dicParam andResult:(NBLHTTPResult)result;
    ```                
                
    需要使用GET以外的HTTP命令，如POST等，或者需要设置HTTP的Header，则可以创建NSURLRequest，然后使用下面这个万能接口

    ```
    - (BOOL)requestObject:(NBLResponseObjectType)resObjType
              withRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                andResult:(NBLHTTPResult)result;
    ```                

    与这两个方法对应的，还有相应的带进度block参数的方法。
    
    ```
    - (BOOL)requestObject:(NBLResponseObjectType)resObjType fromURL:(NSString *)url
                withParam:(NSDictionary *)dicParam
                 progress:(NBLHTTPProgress)progress andResult:(NBLHTTPResult)result;
    ```
    
    ```
    - (BOOL)requestObject:(NBLResponseObjectType)resObjType
              withRequest:(NSURLRequest *)request param:(NSDictionary *)dicParam
                 progress:(NBLHTTPProgress)progress andResult:(NBLHTTPResult)result;
    ```

- 查询网络请求，或取消网络请求

    取消网络请求

    ```
    - (void)cancelRequestWithParam:(NSDictionary *)dicParam;
    ```

    查询网络请求

    ```
    - (BOOL)requestIsExist:(NSDictionary *)dicParam;
    ```
    
    ```
    - (BOOL)urlIsRequesting:(NSString *)url;
    ```




## NBLHTTPFileManager
提供单例方法**sharedManager**，但也保留[[NBLHTTPFileManager alloc] init]的实例化方法。

- 定义了两个block：

    第一个用于返回HTTP文件下载结果。error为nil表示请求成功

    ```
    typedef void (^NBLHTTPFileResult)(NSString *filePath, NSHTTPURLResponse *httpResponse,
                                      NSError *error, NSDictionary *dicParam);
    ```

    第二个用于HTTP文件下载进度回调。

    ```
    typedef void (^NBLHTTPFileProgress)(int64_t bytesReceived, int64_t totalBytes,
                                        NSDictionary *dicParam);

    ```





