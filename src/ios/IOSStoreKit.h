#import <Cordova/CDVPlugin.h>
#import <Cordova/CDVPluginResult.h>
#import <StoreKit/StoreKit.h>
#import <Foundation/Foundation.h>
#import "Base64.h"


@interface SubscriptionManager : CDVPlugin <SKPaymentTransactionObserver, SKRequestDelegate>
{
    NSSet* productIdentifier;
    SKProduct* subscription;
    NSString* productId;
    NSString* callBackId;
    NSString* eventCallbackid;
    NSMutableDictionary* allProducts;
    NSMutableSet* delegates;
    SKReceiptRefreshRequest* refreshRequest;
}

@property (retain) NSSet *productIdentifier;
@property (retain) SKProductsRequest *request;
@property (retain) SKProduct *subscription;
@property (retain) NSString *productId;
@property (retain) NSMutableDictionary *allProducts;
@property (nonatomic,retain) NSString *callbackId;
@property (nonatomic,retain) NSString *eventCallbackId;
@property (retain) NSMutableSet* delegates;
@property (strong, retain) SKReceiptRefreshRequest* refreshRequest;


-(void) emitEvent:(NSString*)evname object:(NSObject*) result;
-(void) commandReply:(CDVInvokedUrlCommand*) command withDictionary:(NSDictionary*) obj;
-(void) commandReply:(CDVInvokedUrlCommand*) command withError:(NSString*) msg;

-(NSData *)readAppStoreReceipt;
-(void) receiptDone: (CDVInvokedUrlCommand*)command data:(NSData*)receiptData;

-(NSMutableDictionary*) serializeTransaction: (SKPaymentTransaction*)transaction;

-(void) init:(CDVInvokedUrlCommand*) command;
-(void) receipt: (CDVInvokedUrlCommand*)command;
-(void) purchase :(CDVInvokedUrlCommand*)command;
-(void) product: (CDVInvokedUrlCommand*)command;
-(void) finish:(CDVInvokedUrlCommand*) command;
-(void) transactions:(CDVInvokedUrlCommand*) command;

-(void) dealloc;
-(void) pluginInitialize;
@end


@interface ProductsRequestDelegate : NSObject <SKProductsRequestDelegate> {
    SubscriptionManager* plugin;
    CDVInvokedUrlCommand* command;
}
@property (retain) SubscriptionManager* plugin;
@property (retain) CDVInvokedUrlCommand* command;
@end



@interface ProductsRefreshDelegate : NSObject <SKRequestDelegate> {
    SubscriptionManager* plugin;
    CDVInvokedUrlCommand* command;
}
@property (retain) SubscriptionManager* plugin;
@property (retain) CDVInvokedUrlCommand* command;
@end
 

