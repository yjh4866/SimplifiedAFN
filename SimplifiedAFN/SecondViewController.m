//
//  SecondViewController.m
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import "SecondViewController.h"
#import "NBLHTTPFileManager.h"
#import "UIImageView+NBL.h"

@interface SecondViewController ()
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@end

@implementation SecondViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
//    NSString *urlFile = @"http://dldir1.qq.com/qqfile/QQforMac/QQ_V4.0.6.dmg";
//    urlFile = @"http://cocostudio.download.appget.cn/CocosCreator/v1.0.0/CocosCreator_v1.0.0_2016032904.dmg";
//    [[NBLHTTPFileManager sharedManager] downloadFile:nil from:urlFile withParam:@{} progress:^(int64_t bytesReceived, int64_t totalBytes, NSDictionary *dicParam) {
//        NSLog(@"%lld (%lld)(%.2f%%)", bytesReceived, totalBytes, 100.0f*bytesReceived/totalBytes);
//    } andResult:^(NSString *filePath, NSHTTPURLResponse *httpResponse, NSError *error, NSDictionary *dicParam) {
//        if (nil == error) {
//            NSLog(@"保存路径：%@", filePath);
//        }
//        else {
//            NSLog(@"下载失败：%@", error);
//        }
//        NSLog(@"回传参数：%@", dicParam);
//    }];
    
    NSString *urlPic = @"http://www.bjsubway.com/subway/images/subway_map.jpg";
    [self.imageView loadImageFromCachePath:nil orPicUrl:urlPic withDownloadResult:^(UIImageView *imageView, NSString *picUrl, float progress, BOOL finished, NSError *error) {
        NSLog(@"下载进度：%.2f%%", 100*progress);
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    [self.imageView cancelDownload];
    NSLog(@"释放 %s", object_getClassName(self));
}

@end
