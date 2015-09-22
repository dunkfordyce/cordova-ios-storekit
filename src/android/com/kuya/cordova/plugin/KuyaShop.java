package com.kuya.cordova.plugin;

import android.content.Intent;
import android.content.res.Configuration;
import android.text.SpanWatcher;
import android.util.Log;
import android.util.SparseArray;

import com.kuya.cordova.plugin.util.*;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;

/**
 * Created by dunk on 04/09/15.
 */
public class KuyaShop extends CordovaPlugin {
    private final String TAG = "KuyaShop";
    // The helper object
    IabHelper mHelper;
    private SparseArray<CallbackContext> purchases = new SparseArray<CallbackContext>();
    private int purchase_id = 1000;

    private String getPublicKey() {
        int billingKeyFromParam = cordova.getActivity().getResources().getIdentifier("billing_key_param", "string", cordova.getActivity().getPackageName());

        if(billingKeyFromParam > 0) {
            return cordova.getActivity().getString(billingKeyFromParam);
        }

        int billingKey = cordova.getActivity().getResources().getIdentifier("billing_key", "string", cordova.getActivity().getPackageName());
        return cordova.getActivity().getString(billingKey);
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        Log.d(TAG, "onActivityResult(" + requestCode + "," + resultCode + "," + data);

        // Pass on the activity result to the helper for handling
        if (!mHelper.handleActivityResult(requestCode, resultCode, data)) {
            // not handled, so handle it ourselves (here's where you'd
            // perform any handling of activity results not related to in-app
            // billing...
            super.onActivityResult(requestCode, resultCode, data);
        }
        else {
            Log.d(TAG, "onActivityResult handled by IABUtil.");
        }
    }

    public boolean execute(String action, JSONArray data, final CallbackContext callbackContext) {
        try {
            return executeSafe(action, data, callbackContext);
        } catch( JSONException e ) {
            callbackContext.error("unhandled json fail");
        }
        return true;
    }

    public boolean executeSafe(String action, JSONArray data, final CallbackContext callbackContext) throws JSONException {
        if( "init".equals(action) ) {
            init(data, callbackContext);
        } else if( "details".equals(action) ) {
            details(data, callbackContext);
        } else if( "purchase".equals(action) ) {
            purchase(data, callbackContext);
        } else if( "subscribe".equals(action) ) {
            subscribe(data, callbackContext);
        } else if( "query".equals(action) ) {
            query(data, callbackContext);
        } else if( "consume".equals(action) ) {
            consume(data, callbackContext);
        } else {
            return false;
        }

        return true;
    }

    private void init(JSONArray data, final CallbackContext callbackContext) {
        String base64EncodedPublicKey = getPublicKey();

        if (base64EncodedPublicKey.isEmpty()) {
            callbackContext.error("no key found");
        }

        // Create the helper, passing it our context and the public key to verify signatures with
        Log.d(TAG, "Creating IAB helper.");
        mHelper = new IabHelper(cordova.getActivity().getApplicationContext(), base64EncodedPublicKey);

        JSONObject options;



        try {
            options = data.getJSONObject(0);
        } catch( JSONException e ) {
            options = new JSONObject();
        }

        // enable debug logging (for a production application, you should set this to false).
        mHelper.enableDebugLogging(options.optBoolean("debug"));

        mHelper.startSetup(new IabHelper.OnIabSetupFinishedListener() {
            public void onIabSetupFinished(IabResult result) {
                Log.d(TAG, "Setup finished.");

                if (!result.isSuccess()) {
                    // Oh no, there was a problem.
                    callbackContext.error("Problem setting up in-app billing: " + result);
                    return;
                }

                // Have we been disposed of in the meantime? If so, quit.
                if (mHelper == null) {
                    callbackContext.error("The billing helper has been disposed");
                }

                callbackContext.success();
            }
        });
    }

    private void details(JSONArray data, final CallbackContext callbackContext) {
        final List<String> skus = new ArrayList<String>();
        JSONArray in_skus;

        try {
            in_skus = data.getJSONArray(0);
        } catch( JSONException e ) {
            callbackContext.error("no skus found");
            return;
        }

        try {
            for (int i = 0; i != in_skus.length(); i++) {
                skus.add(in_skus.getString(i));
            }
        } catch( JSONException e ) {
            callbackContext.error("error reading skus");
        }



        mHelper.queryInventoryAsync(true, skus, new IabHelper.QueryInventoryFinishedListener() {
            @Override
            public void onQueryInventoryFinished(IabResult result, Inventory inv) {
                if (result.isFailure()) {
                    callbackContext.error(result.getMessage());
                    return;
                }

                JSONObject js_result = new JSONObject();

                for (String sku : skus) {
                    SkuDetails details = inv.getSkuDetails(sku);
                    try {
                        if (details == null) {
                            js_result.put(sku, null);
                            continue;
                        }

                        JSONObject out_details = new JSONObject();

                        out_details.put("price", details.getPrice());
                        out_details.put("description", details.getDescription());
                        out_details.put("title", details.getTitle());
                        out_details.put("type", details.getType());

                        js_result.put(sku, out_details);
                    } catch (JSONException e) {
                        callbackContext.error("error converting sku to json");
                        return;
                    }
                }

                callbackContext.success(js_result);
            }
        });

    }

    private void purchase(JSONArray data, final CallbackContext callbackContext) {
        String sku;

        try {
            sku = data.getString(0);
        } catch (JSONException e) {
            callbackContext.error("no/bad sku");
            return;
        }

        Log.d(TAG, "purchasing " + sku);

        IabHelper.OnIabPurchaseFinishedListener iabPurchaseFinishedListener = new IabHelper.OnIabPurchaseFinishedListener() {
            @Override
            public void onIabPurchaseFinished(IabResult result, Purchase info) {
                JSONObject ret = new JSONObject();

                if (result.isFailure()) {
                    try {
                        ret.put("message", result.getMessage());
                        ret.put("response", result.getResponse());
                    } catch( JSONException e ) {
                        e.printStackTrace();
                        callbackContext.error("total fail");
                        return;
                    }

                    Log.d(TAG, "Error purchasing: " + result);
                    callbackContext.error(ret);
                    return;
                }

                try {
                    ret.put("developer_payload", info.getDeveloperPayload());
                    ret.put("item_type", info.getItemType());
                    ret.put("order_id", info.getOrderId());
                    ret.put("package_name", info.getPackageName());
                    ret.put("purchase_state", info.getPurchaseState());
                    ret.put("purchase_time", info.getPurchaseTime());
                    ret.put("signature", info.getSignature());
                    ret.put("sku", info.getSku());
                    ret.put("token", info.getToken());
                } catch (JSONException e) {
                    e.printStackTrace();
                    callbackContext.error("error returning purchase");
                    return;
                }
                callbackContext.success(ret);
            }
        };

        Log.d(TAG, "doing purchase request_id " + purchase_id);
        cordova.setActivityResultCallback(this);
        mHelper.launchPurchaseFlow(cordova.getActivity(), sku, purchase_id, iabPurchaseFinishedListener, "");
        purchase_id ++;
    }

    private JSONObject jsonifyPurchase(Purchase purchase) throws JSONException {
        JSONObject ret = new JSONObject();

        ret.put("developer_payload", purchase.getDeveloperPayload());
        ret.put("item_type", purchase.getItemType());
        ret.put("order_id", purchase.getOrderId());
        ret.put("package_name", purchase.getPackageName());
        ret.put("purchase_state", purchase.getPurchaseState());
        ret.put("purchase_time", purchase.getPurchaseTime());
        ret.put("signature", purchase.getSignature());
        ret.put("sku", purchase.getSku());
        ret.put("token", purchase.getToken());

        return ret;
    }

    private void subscribe(JSONArray data, final CallbackContext callbackContext) {
        String sku;
        String payload;

        try {
            sku = data.getString(0);
        } catch (JSONException e) {
            callbackContext.error("no/bad sku");
            return;
        }

        if( data.length() < 2 ) {
            payload = "";
        } else {
            try {
                payload = data.getString(1);
            } catch (JSONException e) {
                e.printStackTrace();
                callbackContext.error("bad payload");
                return;
            }
        }

        Log.d(TAG, "subscribe " + sku+" payload "+payload);

        cordova.setActivityResultCallback(this);
        mHelper.launchSubscriptionPurchaseFlow(
                cordova.getActivity(),
                sku,
                purchase_id++,
                new IabHelper.OnIabPurchaseFinishedListener() {
                    @Override
                    public void onIabPurchaseFinished(IabResult result, Purchase info) {
                        JSONObject ret = new JSONObject();

                        if (result.isFailure()) {
                            try {
                                ret.put("message", result.getMessage());
                                ret.put("response", result.getResponse());
                            } catch (JSONException e) {
                                e.printStackTrace();
                                callbackContext.error("total fail");
                                return;
                            }

                            Log.d(TAG, "Error purchasing: " + result);
                            callbackContext.error(ret);
                            return;
                        }

                        try {
                            ret = jsonifyPurchase(info);
                        } catch (JSONException e) {
                            e.printStackTrace();
                            callbackContext.error("error returning purchase");
                            return;
                        }
                        callbackContext.success(ret);
                    }
                },
                payload
        );
    }

    private void query(JSONArray data, final CallbackContext callbackContext) {
        final JSONArray skus;

        try {
            skus= data.getJSONArray(0);
        } catch (JSONException e) {
            e.printStackTrace();
            callbackContext.error("bad arguments");
            return;
        }

        mHelper.queryInventoryAsync(new IabHelper.QueryInventoryFinishedListener() {
            @Override
            public void onQueryInventoryFinished(IabResult result, Inventory inv) {
                if (result.isFailure()) {
                    callbackContext.error(result.getMessage());
                    return;
                }

                JSONObject ret = new JSONObject();
                String sku;

                for( int i=0; i!= skus.length(); i++ ) {
                    try {
                        sku = skus.getString(i);
                        Log.d(TAG, "testing sku " + sku);
                        if( inv.hasPurchase(sku) ) {
                            ret.put(sku, jsonifyPurchase(inv.getPurchase(sku)));
                        } else {
                            ret.put(sku, false);
                        }
                        //ret.put(sku, inv.hasPurchase(sku));
                    } catch (JSONException e) {
                        e.printStackTrace();
                        continue;
                    }
                }

                callbackContext.success(ret);
            }
        });
    }

    private void consume(JSONArray data, final CallbackContext callbackContext) {
        final String sku;

        try {
            sku = data.getString(0);
        } catch (JSONException e) {
            e.printStackTrace();
            callbackContext.error("bad argument");
            return;
        }

        mHelper.queryInventoryAsync(new IabHelper.QueryInventoryFinishedListener() {
            @Override
            public void onQueryInventoryFinished(IabResult result, Inventory inv) {
                if (result.isFailure()) {
                    callbackContext.error(result.getMessage());
                    return;
                }
                if( !inv.hasPurchase(sku) ) {
                    callbackContext.error("not purchased");
                    return;
                }
                mHelper.consumeAsync(inv.getPurchase(sku), new IabHelper.OnConsumeFinishedListener() {
                    @Override
                    public void onConsumeFinished(Purchase purchase, IabResult result) {
                        if (result.isFailure()) {
                            callbackContext.error(result.getMessage());
                            return;
                        }
                        callbackContext.success();
                    }
                });
            }
        });
    }




}
