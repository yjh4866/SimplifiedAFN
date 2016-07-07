//
//  FirstViewController.m
//  SimplifiedAFN
//
//  Created by yangjh on 15/11/12.
//  Copyright © 2015年 yjh4866. All rights reserved.
//

#import "FirstViewController.h"
#import "NBLHTTPManager.h"
#import "UIImageView+NBL.h"

@interface FirstViewController ()
@property (strong, nonatomic) IBOutlet UILabel *labelDetail;
@property (strong, nonatomic) IBOutlet UIImageView *imageView;

@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    __weak typeof (self) weakSelf = self;
    [[NBLHTTPManager sharedManager] requestObject:NBLResponseObjectType_String fromURL:@"http://appforyou.net/app/com.3dmaze/MoreGame.php" withParam:@{} andResult:^(NSHTTPURLResponse *httpResponse, id responseObject, NSError *error, NSDictionary *dicParam) {
        if (nil == error) {
            NSLog(@"正常收到服务器返回的数据了");
            weakSelf.labelDetail.text = responseObject;
        }
    }];
    
    [self.imageView loadImageFromCachePath:nil orPicUrl:@"http://appleyuan.net/app/com.3dmaze/icon150x150.jpg" withDownloadResult:^(UIImageView *imageView, NSString *picUrl, float progress, BOOL finished, NSError *error) {
        if (finished) {
            
        }
        else {
            NSLog(@"Progress: %.2f%%", 100*progress);
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
