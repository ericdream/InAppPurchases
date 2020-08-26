//
//  StroeManage.h
//  InAppPurchases
//
//  Created by Eric on 2020/8/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSUInteger, StoreErrorCode) {
    STORE_ERROR_CODE_UNALLOWED = 0,  // 手机未授权支付
    STORE_ERROR_CODE_PENDING,     //  有订单正在进心中
    STORE_ERROR_CODE_UNLEGALID,  // ID 不能为空
    STORE_ERROR_CODE_UNFOUND,  // 未找到商品，查看商品id 是否正确
    STORE_ERROR_CODE_CHECKFAIL, // 商品查询失败
    STORE_ERROR_CODE_RECEIPT_ISNULL, // 凭证为空
    STORE_ERROR_CODE_BUY_FAIL,    // 购买失败
    STORE_ERROR_CODE_USER_CANCEL  // 用户取消
};
@protocol StoreManagerDelegate <NSObject>

- (void)storeWithErrorCode:(StoreErrorCode)code orderId:(NSString *)orderId;

- (void)verifyWithReceipt:(NSString *)receipt orderId:(NSString *)orderId productId:(NSString *)productId callBack:(void(^)(BOOL sucess))callBack;

@end


@interface StoreManager : NSObject
@property (nonatomic,weak) id<StoreManagerDelegate>delegate;
+ (StoreManager *)sharedInstance;

/// 在程序启动的时候就调用 主动验证之前验证失败的订单
- (void)setup;
- (void)unSetup;
// 订单绑定票据
- (void)startProductRequestWithProductId:(NSString *)identifier orderId:(NSString *)orderId;
- (void)refreshStore;
@end

NS_ASSUME_NONNULL_END

