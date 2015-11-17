//
//  SecondViewController.m
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import "SecondViewController.h"
#import "HTTPFileManager.h"

@interface SecondViewController ()

@end

@implementation SecondViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSString *urlFile = @"http://dldir1.qq.com/qqfile/QQforMac/QQ_V4.0.6.dmg";
//    urlFile = @"http://cc.cocimg.com/api/uploads/20151113/1447401023180293.png";
    [[HTTPFileManager sharedManager] downloadFile:nil from:urlFile withParam:@{} progress:^(int64_t bytesReceived, int64_t totalBytes, NSDictionary *dicParam) {
        NSLog(@"%lld (%lld)(%.2f%%)", bytesReceived, totalBytes, 100.0f*bytesReceived/totalBytes);
    } andResult:^(NSString *filePath, NSHTTPURLResponse *httpResponse, NSError *error, NSDictionary *dicParam) {
        if (nil == error) {
            NSLog(@"保存路径：%@", filePath);
        }
        else {
            NSLog(@"下载失败:%@", error);
        }
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    NSLog(@"释放 %s", object_getClassName(self));
}

@end
