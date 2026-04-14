//
//  DJAppCell.h
//  DarkJIT
//

#import <UIKit/UIKit.h>
#import "AppListManager.h"

@protocol DJAppCellDelegate <NSObject>
- (void)didTapEnableJIT:(DJAppInfo *)app;
- (void)didTapLaunchApp:(DJAppInfo *)app;
@end

@interface DJAppCell : UITableViewCell

@property (nonatomic, weak) id<DJAppCellDelegate> delegate;

- (void)configureWithApp:(DJAppInfo *)app;

@end
