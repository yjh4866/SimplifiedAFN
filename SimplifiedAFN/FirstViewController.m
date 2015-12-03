//
//  FirstViewController.m
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import "FirstViewController.h"
#import "NBLHTTPManager.h"

@interface FirstViewController ()
@property (strong, nonatomic) IBOutlet UILabel *labelDetail;

@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    __weak typeof (self) weakSelf = self;
    [[NBLHTTPManager sharedManager] requestWebDataFromURL:@"http://www.baidu.com" withParam:@{} andResult:^(NSHTTPURLResponse *httpResponse, NSData *webData, NSError *error, NSDictionary *dicParam) {
        if (nil == error) {
            NSLog(@"正常收到服务器返回的数据了");
            weakSelf.labelDetail.text = [[NSString alloc] initWithData:webData encoding:NSUTF8StringEncoding];
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
