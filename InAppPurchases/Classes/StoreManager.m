//
//  StroeManage.m
//  InAppPurchases
//
//  Created by Eric on 2020/8/18.
//

#import "StoreManager.h"
#import <StoreKit/StoreKit.h>
static NSString * const receiptKey = @"receipt_key";
static NSString * const orderIdKey = @"userId_key";
static NSString * const productIdKey = @"productId_key";
static NSString * const keyChainKey = @"productId_key";
@interface StoreManager()<SKRequestDelegate, SKProductsRequestDelegate,SKPaymentTransactionObserver>
@property (nonatomic,strong) SKProductsRequest *productRequest;
@property (nonatomic,strong) NSString *orderId;
@property (nonatomic,strong) SKReceiptRefreshRequest *refreshRequest;
@property (nonatomic,assign) BOOL lock;
@end
@implementation StoreManager
+ (StoreManager *)sharedInstance {
    static dispatch_once_t onceToken;
    static StoreManager * storeManagerSharedInstance;
    
    dispatch_once(&onceToken, ^{
        storeManagerSharedInstance = [[StoreManager alloc] init];
    });
    return storeManagerSharedInstance;
}

- (instancetype)init {
    self = [super init];

    if (self != nil) {
        self.lock = NO;

    }
    return self;
}

-(void)setup{
    [[SKPaymentQueue defaultQueue] addTransactionObserver:[StoreManager sharedInstance]];
    [self checkIAPFiles];
}

- (void)unSetup{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:[StoreManager sharedInstance]];
}

- (void)startProductRequestWithProductId:(NSString *)identifier orderId:(nonnull NSString *)orderId{
    NSLog(@"startProductRequestWithProductId:%@  %@",identifier,orderId);
    if(self.lock){
        [self errorWithCode:STORE_ERROR_CODE_UNLEGALID orderId:orderId];
        return;
    }
    self.lock = YES;
    self.orderId = orderId;
    if(identifier == nil || identifier.length == 0){
        [self errorWithCode:STORE_ERROR_CODE_UNLEGALID orderId:orderId];
        return;
    }
    NSSet *set = [[NSSet alloc] initWithObjects:identifier, nil];
    if([SKPaymentQueue canMakePayments]){
        self.productRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
        self.productRequest.delegate = self;
        [self.productRequest start];
    }else{
        [self errorWithCode:STORE_ERROR_CODE_UNALLOWED orderId:orderId];
    }
}


- (void)refreshStore{
#warning 需要测试优化暂时未涉及到
    self.refreshRequest = [[SKReceiptRefreshRequest alloc] init];
    self.refreshRequest.delegate = self;
    [self.refreshRequest start];
}

- (void)checkIAPFiles{
    NSArray *allReceipt = [self getAllFromKeyChain];
    [allReceipt enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = obj;
        NSString *receipt = dic[receiptKey];
        NSString *orderId  = dic[orderIdKey];
        NSString *productId  = dic[productIdKey];
        if([self.delegate respondsToSelector:@selector(verifyWithReceipt:orderId:productId:callBack:)]){
            [self.delegate verifyWithReceipt:receipt orderId:orderId productId:productId callBack:^(BOOL sucess) {
                if(sucess){
                    [self removeReceiptWithOrderId:orderId];
                }
                
            }];
        }
    }];
}
-(void)saveReceipt:(NSString *)receipt productId:(NSString*)productId{
    NSDictionary *dic =[NSDictionary dictionaryWithObjectsAndKeys:receipt, receiptKey,self.orderId,                  orderIdKey,productId,productIdKey,
                        nil];
    [self saveKeyChain:dic orider:self.orderId];
}

- (void)saveKeyChain:(NSDictionary *)dic orider:(NSString *)orderId{

    [self save:orderId data:dic];
    NSArray *keys =  [self load:keyChainKey];
    NSMutableArray *tmpArray = [[NSMutableArray alloc] initWithArray:keys];
    [tmpArray addObject:orderId];
    [self save:keyChainKey data:tmpArray];
}
-(NSArray *)getAllFromKeyChain{
    NSArray *keys =  [self load:keyChainKey];
    NSMutableArray *allData = [[NSMutableArray alloc] init];
    [keys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *key = obj;
        NSDictionary *tmpDic = [self load:key];
        [allData addObject:tmpDic];
    }];
    return allData.copy;
}
- (void)removeReceiptWithOrderId:(NSString *)orderId{
    NSArray *keys =  [self load:keyChainKey];
    NSMutableArray *tmpArray = [[NSMutableArray alloc] initWithArray:keys];
    if([tmpArray containsObject:orderId]){
        [tmpArray removeObject:orderId];
    }
    [self save:keyChainKey data:tmpArray];
    [self delete:orderId];
}

- (void)handleReceiptWithTransaction:(SKPaymentTransaction *)transaction{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    NSString *orderId = transaction.payment.applicationUsername;
    if(receiptData){
        NSString *result = [receiptData base64EncodedStringWithOptions:0];
        NSString *transactionId = transaction.transactionIdentifier;
        NSString *productId = transaction.payment.productIdentifier;
        NSDictionary *parameter = @{@"TransactionID":transactionId,@"Payload":result};
        NSData *data = [NSJSONSerialization dataWithJSONObject:parameter options:NSJSONWritingFragmentsAllowed error:nil];
        NSString *receipt = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self saveReceipt:receipt productId:productId];
        [self checkIAPFiles];
    }else{
        [self errorWithCode:STORE_ERROR_CODE_RECEIPT_ISNULL orderId:orderId];
    }
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    self.lock = NO;
}

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction{
    NSString *orderId = transaction.payment.applicationUsername;
    if(transaction.error.code == SKErrorPaymentCancelled){
        [self errorWithCode:STORE_ERROR_CODE_USER_CANCEL orderId:orderId];
    }else{
        [self errorWithCode:STORE_ERROR_CODE_BUY_FAIL orderId:orderId];
    }
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}
- (void)handleRestoredTransaction:(SKPaymentTransaction *)transaction{
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
    self.lock = NO;
}
#pragma mark -SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response{
    SKProduct * product = response.products.firstObject;
    if(response.products.count == 0){
        [self errorWithCode:STORE_ERROR_CODE_UNFOUND orderId:self.orderId];
    }else{
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
        payment.applicationUsername = self.orderId; // 放弃使用这种范式来保存订单ID 因为苹果明确说明不能保证持久也就是会丢失数据，说以我是用了keychain 来持久化凭证和订单id
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        
        NSLog(@"applicationUsername:%@",self.orderId);
    }
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    [self errorWithCode:STORE_ERROR_CODE_CHECKFAIL orderId:self.orderId];
}

#pragma  mark SKPaymentTransactionObserver
- (void)paymentQueue:(nonnull SKPaymentQueue *)queue updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSLog(@"updatedTransactions:%@",obj.payment.applicationUsername);
        switch (obj.transactionState) {
            case SKPaymentTransactionStatePurchasing:
                break;
            case SKPaymentTransactionStatePurchased:{
                // success
                [self handleReceiptWithTransaction:obj];
            }
                break;
            case SKPaymentTransactionStateFailed:{
                [self handleFailedTransaction:obj];
            }
                break;
            case SKPaymentTransactionStateRestored:{
                [self handleRestoredTransaction:obj];
            }
                break;
            case SKPaymentTransactionStateDeferred:
                self.lock = NO;
                [[SKPaymentQueue defaultQueue] finishTransaction: obj];
                break;
                
            default:
                break;
        }
     }];
}
#pragma mark delegate error call back
- (void)errorWithCode:(StoreErrorCode) code orderId:(NSString *)orderId {
    self.lock = NO;
    if([self.delegate respondsToSelector:@selector(storeWithErrorCode:orderId:)]){
        [self.delegate storeWithErrorCode:code orderId:orderId] ;
    }
}
#pragma  mark key chain
- (NSMutableDictionary *)getKeychainQuery:(NSString *)service {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            (__bridge_transfer id)kSecClassGenericPassword,(__bridge_transfer id)kSecClass,
            service, (__bridge_transfer id)kSecAttrService,
            service, (__bridge_transfer id)kSecAttrAccount,
            (__bridge_transfer id)kSecAttrAccessibleAfterFirstUnlock,(__bridge_transfer id)kSecAttrAccessible,
            nil];
}

- (void)save:(NSString *)service data:(id)data {
    NSMutableDictionary *keychainQuery = [self getKeychainQuery:service];
    SecItemDelete((__bridge_retained CFDictionaryRef)keychainQuery);
    [keychainQuery setObject:[NSKeyedArchiver archivedDataWithRootObject:data] forKey:(__bridge_transfer id)kSecValueData];
    SecItemAdd((__bridge_retained CFDictionaryRef)keychainQuery, NULL);
}

- (id)load:(NSString *)service {
    id ret = nil;
    NSMutableDictionary *keychainQuery = [self getKeychainQuery:service];
    [keychainQuery setObject:(id)kCFBooleanTrue forKey:(__bridge_transfer id)kSecReturnData];
    [keychainQuery setObject:(__bridge_transfer id)kSecMatchLimitOne forKey:(__bridge_transfer id)kSecMatchLimit];
    CFDataRef keyData = NULL;
    if (SecItemCopyMatching((__bridge_retained CFDictionaryRef)keychainQuery, (CFTypeRef *)&keyData) == noErr) {
        @try {
            ret = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge_transfer NSData *)keyData];
        } @catch (NSException *e) {
            NSLog(@"Unarchive of %@ failed: %@", service, e);
        } @finally {
        }
    }
    return ret;
}
- (void)delete:(NSString *)service {
        NSMutableDictionary *keychainQuery = [self getKeychainQuery:service];
        SecItemDelete((__bridge_retained CFDictionaryRef)keychainQuery);
    }
@end
