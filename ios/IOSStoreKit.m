#import "SubscriptionManager.h"

#define NILABLE(obj) ((obj) != nil ? (NSObject *)(obj) : (NSObject *)[NSNull null])

@implementation ProductsRequestDelegate

@synthesize plugin = _plugin;
@synthesize command = _command;

-(void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    NSLog(@"Start: %@ %lu" , @" productsRequested ", (unsigned long)[response.products count]);
    
    NSMutableDictionary *resp = [[NSMutableDictionary alloc] init];
    
    for (SKProduct *product in response.products)
    {
        NSLog(@"Product title: %@" , product.localizedTitle);
        NSLog(@"Product description: %@" , product.localizedDescription);
        NSLog(@"Product price: %@" , product.price);
        NSLog(@"Product id: %@" , product.productIdentifier);
        
        [self.plugin.allProducts setObject:product forKey:product.productIdentifier];
        
        
        NSDictionary *jsonObj = [ [NSDictionary alloc] initWithObjectsAndKeys:
                                 product.localizedTitle, @"title",
                                 product.price, @"price",
                                 product.productIdentifier, @"id",
                                 nil
                                 ];
        [resp setObject:jsonObj forKey:product.productIdentifier];
        
    }
    
    [self.plugin commandReply:self.command withDictionary:resp];
    NSLog(@"End: %@" , @" productsRequested ");
}


- (void)requestDidFinish:(SKRequest *)request NS_AVAILABLE_IOS(3_0)
{
    NSLog(@"---reqdidfinish");
    [self.plugin.delegates removeObject:self];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error NS_AVAILABLE_IOS(3_0);
{
     NSLog(@"---reqdidfail %lu", (long)error.code);
    [self.plugin.delegates removeObject:self];
}

@end

@implementation ProductsRefreshDelegate

@synthesize plugin = _plugin;
@synthesize command = _command;

-(void)requestDidFinish:(SKRequest *)request {
    NSLog(@"requestDidFinish() in ProductsRefreshDelegate");
    
    if([request isKindOfClass:[SKReceiptRefreshRequest class]])
    {
        [self.plugin receiptDone:self.command data:[self.plugin readAppStoreReceipt]];
    }
    
    [self.plugin.delegates removeObject:self];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    NSLog(@"request failed");
    [self.plugin commandReply:self.command withError:@"refresh failed"];
    [self.plugin.delegates removeObject:self];
}
@end

@implementation SubscriptionManager

static SubscriptionManager * _scManager; 

@synthesize request = _request;
@synthesize subscription = _subscription;
@synthesize productId = _productId;
@synthesize productIdentifier = _productIdentifier;
@synthesize callbackId = _callbackId;
@synthesize allProducts = _allProducts;
@synthesize delegates = _delegates;
@synthesize refreshRequest = _refreshRequest;

-(void) pluginInitialize
{
    NSLog(@"pluginInitialize()");
    
    self.delegates = [[NSMutableSet alloc]init];
    self.allProducts = [[NSMutableDictionary alloc] init];
    
    
    //[self emitEvent:@"ready" object:nil];
}

-(void) init:(CDVInvokedUrlCommand*) command
{
    NSLog(@"init()");
    
    [self.commandDelegate evalJs:@"window.kuyashop = {}"];
    
    [self export:@"payment_states" object:[[NSDictionary alloc] initWithObjectsAndKeys:
                                           @(SKPaymentTransactionStatePurchasing), @"purchasing",
                                           @(SKPaymentTransactionStatePurchased), @"purchased",
                                           @(SKPaymentTransactionStateFailed), @"failed",
                                           @(SKPaymentTransactionStateRestored), @"restored",
                                           @(SKPaymentTransactionStateDeferred), @"deferred",
                                           nil
                                           ]];
    
    [self export:@"errors" object:[[NSDictionary alloc] initWithObjectsAndKeys:
                                   @(SKErrorClientInvalid), @"client_invalid",
                                   @(SKErrorPaymentCancelled), @"payment_cancelled",
                                   @(SKErrorPaymentInvalid), @"payment_invalid",
                                   @(SKErrorPaymentNotAllowed), @"payment_not_allowed",
                                   @(SKErrorStoreProductNotAvailable), @"store_product_not_available",
                                   nil
                                   ]];

    
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    
    [self commandReply:command withBool:true];
}

-(void) export:(NSString*)name object:(NSDictionary*) obj
{
    NSError *error = nil;
    NSData* json = [NSJSONSerialization dataWithJSONObject:obj options: 0 error:&error];
    if( error ) {
        NSLog(@"failed creating json %@", error.debugDescription);
    }
    NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    
    NSString *js = [NSString
                    stringWithFormat:@"window.kuyashop.%@=%@;", name, jsonString
                    ];
    [self.commandDelegate evalJs:js];
}

-(void) emitEvent:(NSString*)evname object:(NSObject*)result
{
    NSError *error = nil;
    NSDictionary *wrapper = [ [NSDictionary alloc] initWithObjectsAndKeys :
                             result != nil ? (NSObject*)result : (NSObject *)[NSNull null] , @"data",
                             evname, @"type",
                             nil
                             ];
    
    NSData* json = [NSJSONSerialization dataWithJSONObject:wrapper options: 0 error:&error];
    
    if( error ) {
        NSLog(@"failed creating json %@", error.debugDescription);
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    
    NSString *js = [NSString
                    stringWithFormat:@"window.kuyashop._emit(%@)",
                    jsonString];
    
    
    
    NSLog(@"emitting %@", js);
    [self.commandDelegate evalJs:js];
}

-(void) commandReply:(CDVInvokedUrlCommand*) command withDictionary:(NSDictionary*) obj
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                        messageAsDictionary: obj
                                     ];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void) commandReply:(CDVInvokedUrlCommand*) command withBool:(Boolean) v
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsBool:v
                                     ];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void) commandReply:(CDVInvokedUrlCommand*) command withError:(NSString*) msg
{
    NSDictionary* err = [[NSDictionary alloc] initWithObjectsAndKeys:
                         msg, @"message",
                         nil];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                  messageAsDictionary: err
                                     ];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
    
- (NSData *)readAppStoreReceipt
{
    NSLog(@"readAppStoreReceipt()");
    NSURL *receiptURL = nil;
    NSBundle *bundle = [NSBundle mainBundle];
    if ([bundle respondsToSelector:@selector(appStoreReceiptURL)]) {
        // The general best practice of weak linking using the respondsToSelector: method
        // cannot be used here. Prior to iOS 7, the method was implemented as private SPI,
        // but that implementation called the doesNotRecognizeSelector: method.
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
            receiptURL = [bundle performSelector:@selector(appStoreReceiptURL)];
        }
    }
    
    NSLog(@"appStoreReceipt(), receiptURL=%@", receiptURL.debugDescription);
    
    if (receiptURL != nil) {
        NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
#if ARC_DISABLED
        [receiptData autorelease];
#endif
        return receiptData;
    }
    else {
        return nil;
    }
}


- (void) receiptDone: (CDVInvokedUrlCommand*)command data:(NSData*)receiptData
{
    [self.commandDelegate
        sendPluginResult:[CDVPluginResult
           resultWithStatus:CDVCommandStatus_OK
           messageAsString:(receiptData ? [Base64 encode:receiptData] : nil)
        ]
        callbackId:command.callbackId
    ];
}


- (void) receipt: (CDVInvokedUrlCommand*)command {
    NSData *receiptData = [self readAppStoreReceipt];
    
    if (receiptData != nil) {
        [self receiptDone:command data:receiptData];
    } else {
     
        NSLog(@"receipt() refreshing receipts because none found");
        self.refreshRequest = [[SKReceiptRefreshRequest alloc] init];
        
        ProductsRefreshDelegate *delegate = [[ProductsRefreshDelegate alloc] init];
        delegate.plugin = self;
        delegate.command = command;
        
        [self.delegates addObject: delegate];
        NSLog(@"delegates len %lu", (unsigned long)self.delegates.count);
    
        self.refreshRequest.delegate = delegate;
        
        [self.refreshRequest start];
        NSLog(@"done request refresh");
    }
}


-(void) product:(CDVInvokedUrlCommand*)command
{
    
    NSString* prodId  = [command.arguments objectAtIndex:0];
    
    NSSet* pid = [NSSet setWithObject:prodId ];
    
    NSLog(@"Start: %@ %@" , @"getProduct",prodId);
    
    ProductsRequestDelegate* delegate = [[ProductsRequestDelegate alloc] init];
    delegate.plugin = self;
    delegate.command = command;
    [self.delegates addObject:delegate];
    
    self.request = [[SKProductsRequest alloc] initWithProductIdentifiers:pid];
    self.request.delegate = delegate;
    [self.request start];
    
    NSLog(@"End: %@" , @"getProduct");
}


-(void) purchase:(CDVInvokedUrlCommand*)command
{
    if( ![SKPaymentQueue canMakePayments] ) {
        [self commandReply:command withError:@"nopayments"];
        return;
    }
    
    NSString* ident = [command.arguments objectAtIndex:0];
    SKProduct* product = [self.allProducts objectForKey:ident];
    
    if( !product ) {
        NSLog(@"keys %@", [self.allProducts allKeys]);
        NSLog(@"Didnt find product in subscribe() for %@", ident);
        [self commandReply:command withError:@"no such product"];
    } else {
        NSLog(@"Found product - purchasing %@", ident);
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    }
}

-(NSMutableDictionary*) serializeTransaction: (SKPaymentTransaction*)transaction
{
    NSDateFormatter* formatter = [[NSDateFormatter alloc]init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZ";
    
    NSMutableDictionary* ret = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                NILABLE(transaction.transactionIdentifier), @"id",
                                NILABLE([NSNumber numberWithInteger:transaction.transactionState]), @"state",
                                NILABLE(transaction.payment.productIdentifier), @"product",
                                NILABLE([formatter stringFromDate:transaction.transactionDate]), @"date",
                                nil];
    return ret;
}

-(void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    NSLog(@"Start: paymentQueue() %lu" , (unsigned long)[queue.transactions count]);
    
    for (SKPaymentTransaction *transaction in transactions)
    {
        NSMutableDictionary *jsonObj = [self serializeTransaction:transaction];
        
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStatePurchased:
                NSLog(@"Start: %@" , @"completeTransaction()");
                [self addTransactionDetails:transaction ev:jsonObj];
                break;
            case SKPaymentTransactionStateFailed:
                NSLog(@"Start: %@" , @"failedTransaction()");
                [self failedTransaction:transaction ev:jsonObj];
                break;
            case SKPaymentTransactionStateRestored:
                [self addTransactionDetails:transaction ev:jsonObj];
                NSLog(@"Start: %@" , @"restoreTransaction()");
                //[self restoreTransaction:transaction  ev:jsonObj];
                break;
            default:
                //NSLog(@"unhandled state %lu", (long)transaction.transactionState);
                break;
        }
      
        [self emitEvent:@"payment:update" object:jsonObj];
    }
}

-(void) finish:(CDVInvokedUrlCommand*) command
{
    NSString* ident = [command.arguments objectAtIndex:0];
    
    NSLog(@"finish(%@)", ident);
    
    for( SKPaymentTransaction* transaction in [[SKPaymentQueue defaultQueue] transactions])
    {
        if( [transaction.transactionIdentifier isEqualToString:ident]) {
             NSLog(@"found transaction %@", ident);
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            [self commandReply:command withBool:true];
            return;
        }
    }
    [self commandReply:command withError:@"no such transaction"];
}

-(void) transactions:(CDVInvokedUrlCommand*) command
{
    NSMutableDictionary* ret = [[NSMutableDictionary alloc] init];
    
    for( SKPaymentTransaction* transaction in [[SKPaymentQueue defaultQueue] transactions])
    {
        [ret setObject:[self serializeTransaction:transaction] forKey:transaction.transactionIdentifier];
    }
    
    [self commandReply:command withDictionary:ret];
}

- (void)addTransactionDetails:(SKPaymentTransaction *)transaction ev:(NSMutableDictionary*)ev
{
    NSLog(@"completeTransaction - now you need to finalize it manually");

    NSData *receiptData = [NSData dataWithData:transaction.transactionReceipt];
    
    NSString *encodedString = [Base64 encode:receiptData];
    NSString *receiptStr = [[NSString alloc] initWithData:receiptData encoding:NSUTF8StringEncoding];
    
    NSDictionary* data = [ [NSDictionary alloc]
                          initWithObjectsAndKeys :
                          encodedString, @"encodedString",
                          receiptStr, @"receiptStr",
                          nil
                          ];
    
    [ev setObject: data forKey: @"transaction"];
    
    /*
    // save the transaction receipt to disk
    [[NSUserDefaults standardUserDefaults] setValue:encodedString forKey:@"TransactionReceipt" ];
    [[NSUserDefaults standardUserDefaults] synchronize];
    */
}


- (void)failedTransaction:(SKPaymentTransaction *)transaction ev:(NSMutableDictionary*)ev
{
    NSLog(@"failedTransaction()");
    [ev setObject:@(transaction.error.code) forKey: @"error_code"];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}


- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray *)transactions{
   
    for (SKPaymentTransaction *transaction in transactions)
    {
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }
}


- (void)dealloc
{

}

@end