//
//  ChiakiBridge.m
//  chiakiapp
//
//  Created by Tan Thor Jen on 29/3/22.
//

#import <Foundation/Foundation.h>

#import "chiaki/discoveryservice.h"
#import "chiaki/regist.h"
#import "chiaki/session.h"
#import "chiaki/log.h"
#import "chiaki/ffmpegdecoder.h"

#import "ChiakiBridge.h"

@implementation ChiakiDiscoverBridge {
    ChiakiDiscoveryService discoveryService;
    ChiakiLog chiakiLog;
}

static void DiscoveryServiceHostsCallback(ChiakiDiscoveryHost* hosts, size_t hosts_count, void *user)
{
    ChiakiDiscoverBridge *bridge = (__bridge ChiakiDiscoverBridge *)(user);
    bridge.callback(hosts_count, hosts);
}

static void NoLogCb(ChiakiLogLevel level, const char *msg, void *user) {
//    NSLog(@"log %s", msg);
}

static void LogCb(ChiakiLogLevel level, const char *msg, void *user) {
    NSLog(@"log %s", msg);
}

-(void) discover {
    ChiakiDiscoveryServiceOptions options;
    options.ping_ms = 500;
    options.hosts_max = 16;
    options.host_drop_pings = 3;
    options.cb = DiscoveryServiceHostsCallback;
    options.cb_user = (__bridge void *)(self);
    
    struct sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = 0xffffffff; // 255.255.255.255
    options.send_addr = (struct sockaddr *)(&addr);
    options.send_addr_size = sizeof(addr);
        
    chiaki_log_init(&chiakiLog, CHIAKI_LOG_ALL, NoLogCb, NULL);

    ChiakiErrorCode err = chiaki_discovery_service_init(&discoveryService, &options, &chiakiLog);
    NSLog(@"discover err=%d", err);
    
}

-(void)wakeup:(NSString*)host key:(NSData*)key {
    uint64_t credkey = *(uint64_t*)(key.bytes);
    ChiakiErrorCode err = chiaki_discovery_wakeup(&chiakiLog, &discoveryService.discovery, host.UTF8String, credkey, true);
    NSLog(@"chiaki_discovery_wakeup err=%d", err);
}


@end

@implementation ChiakiRegisterBridge {
    ChiakiRegist regist;
    ChiakiLog chiakiLog;
}

static void RegisterCb(ChiakiRegistEvent *event, void *user) {
    NSLog(@"registercb %d", event->type);

    ChiakiRegisterBridge *bridge = (__bridge ChiakiRegisterBridge *)(user);
    bridge.callback(event);
}


-(void)registWithPsn:(NSData*)psn host:(NSString*)host pin:(NSInteger)pin
{
    chiaki_log_init(&chiakiLog, CHIAKI_LOG_ALL, LogCb, NULL);
 
    ChiakiRegistInfo info;

    info.psn_online_id = NULL;
    info.pin = (uint32_t)pin;
    
    if (psn.length != 8) {
        ChiakiRegistEvent evt;
        evt.type = CHIAKI_REGIST_EVENT_TYPE_FINISHED_FAILED;
        evt.registered_host = NULL;
        self.callback(&evt);
        return;
    }

    const uint8_t *b = psn.bytes;
    for(int i = 0; i < 8; i++) {
        info.psn_account_id[i] = b[i];
    }
    
    info.broadcast = false;
    info.target = CHIAKI_TARGET_PS5_1;
    info.host = host.UTF8String;
    
    ChiakiErrorCode err = chiaki_regist_start(&regist, &chiakiLog, &info, &RegisterCb, (__bridge void *)(self));
    NSLog(@"chiaki_regist_start err=%d", err);
    
    if (err != CHIAKI_ERR_SUCCESS) {
        ChiakiRegistEvent evt;
        evt.type = CHIAKI_REGIST_EVENT_TYPE_FINISHED_FAILED;
        evt.registered_host = NULL;
        self.callback(&evt);
    }
}

-(void)cancel {
    chiaki_regist_stop(&regist);
}

@end


@implementation ChiakiSessionBridge {
    ChiakiSession session;
    ChiakiLog chiakiLog;
    ChiakiFfmpegDecoder decoder;
}

static bool VideoCb(uint8_t *buf, size_t buf_size, void *user) {
//    NSData *data = [[NSData alloc] initWithBytesNoCopy:buf length:buf_size];
//    NSLog(@"VideoCb %ld", buf_size);
    
    ChiakiSessionBridge *bridge = (__bridge ChiakiSessionBridge *)(user);
    
    chiaki_ffmpeg_decoder_video_sample_cb(buf, buf_size, &bridge->decoder);
    
//    bridge.callback(data);
    
    return true;
}

static void FrameCb(ChiakiFfmpegDecoder *decoder, void *user) {
    AVFrame *frame = chiaki_ffmpeg_decoder_pull_frame(decoder);
    if (frame == NULL) {
        NSLog(@"Error pulling frame");
        return;
    }
    
//    @autoreleasepool {
//        NSData * data = [[NSData alloc] initWithBytesNoCopy:frame->data[0] length:1920*1080];
//        [data writeToFile:@"/Users/tjtan/downloads/test.raw" atomically:true];
//    }
    
    ChiakiSessionBridge *bridge = (__bridge ChiakiSessionBridge *)(user);
    if (bridge.videoCallback != nil) {
        bridge.videoCallback(frame);
    }
    
    av_frame_free(&frame);
}

-(void)start {
    chiaki_log_init(&chiakiLog, 3, LogCb, NULL);
    
    ChiakiErrorCode err;
    
    err = chiaki_ffmpeg_decoder_init(&decoder, &chiakiLog, CHIAKI_CODEC_H264, NULL, FrameCb, (__bridge void*)self);
    NSLog(@"chiaki_ffmpeg_decoder_init err=%d", err);

    ChiakiConnectInfo info = {};
    info.ps5 = true;
    info.host = [self.host cStringUsingEncoding:NSUTF8StringEncoding];
    info.enable_keyboard = false;
    
    if (self.morning.length != 16) {
        NSLog(@"ERROR Morning is not 16 bytes");
        return;
    }
    memcpy(info.morning, self.morning.bytes, 16);
    memcpy(info.regist_key, self.registKey.bytes, 16);
    
    chiaki_connect_video_profile_preset(&info.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_1080p, CHIAKI_VIDEO_FPS_PRESET_60);
    info.video_profile.codec = CHIAKI_CODEC_H264;
    info.video_profile_auto_downgrade = false;

    
    err = chiaki_session_init(&session, &info, &chiakiLog);
    NSLog(@"chiaki_session_init err=%d", err);
    
    chiaki_session_set_video_sample_cb(&session, VideoCb, (__bridge void*)self);
    chiaki_session_start(&session);
}

-(void)setControllerState:(ChiakiControllerState)state {
    chiaki_session_set_controller_state(&session, &state);
}

@end
