#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

static void HSVtoRGB(double h, double s, double v, CGFloat *r, CGFloat *g, CGFloat *b) {
    double i = floor(h * 6.0), f = h * 6.0 - i;
    double p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
    switch (((int)i) % 6) {
        case 0: *r = v; *g = t; *b = p; break;
        case 1: *r = q; *g = v; *b = p; break;
        case 2: *r = p; *g = v; *b = t; break;
        case 3: *r = p; *g = q; *b = v; break;
        case 4: *r = t; *g = p; *b = v; break;
        default: *r = v; *g = p; *b = q; break;
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { printf("usage: mkvideo out.mp4 [seconds]\n"); return 1; }
        NSString *outPath = [NSString stringWithUTF8String:argv[1]];
        int seconds = argc > 2 ? atoi(argv[2]) : 6;
        int W = 1280, H = 720, FPS = 30;
        NSURL *url = [NSURL fileURLWithPath:outPath];
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];

        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:NULL];
        NSDictionary *settings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(W), AVVideoHeightKey: @(H),
            AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(4000000)}
        };
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
        input.expectsMediaDataInRealTime = NO;
        NSDictionary *attrs = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString *)kCVPixelBufferWidthKey: @(W),
            (NSString *)kCVPixelBufferHeightKey: @(H)
        };
        AVAssetWriterInputPixelBufferAdaptor *adaptor =
            [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                                                             sourcePixelBufferAttributes:attrs];
        if (![writer canAddInput:input]) { printf("cannot add input\n"); return 2; }
        [writer addInput:input];
        [writer startWriting];
        [writer startSessionAtSourceTime:kCMTimeZero];

        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        int total = FPS * seconds;
        for (int f = 0; f < total; f++) {
            while (!input.isReadyForMoreMediaData) usleep(1500);
            CVPixelBufferRef pb = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pb);
            if (!pb) { printf("no pixel buffer\n"); return 3; }
            CVPixelBufferLockBaseAddress(pb, 0);
            CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), W, H, 8,
                                                    CVPixelBufferGetBytesPerRow(pb), cs,
                                                    kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
            double t = (double)f / total;
            CGFloat r1, g1, b1, r2, g2, b2;
            HSVtoRGB(fmod(0.55 + t * 0.35, 1.0), 0.75, 0.85, &r1, &g1, &b1);
            HSVtoRGB(fmod(0.72 + t * 0.35, 1.0), 0.85, 0.35, &r2, &g2, &b2);
            CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
            CGFloat comps[8] = {r1, g1, b1, 1.0, r2, g2, b2, 1.0};
            CGGradientRef grad = CGGradientCreateWithColorComponents(rgb, comps, NULL, 2);
            CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, H), CGPointMake(W, 0), 0);
            CGGradientRelease(grad);
            for (int i = 0; i < 5; i++) {
                double phase = t * 2 * M_PI + i * 1.3;
                double cx = W * (0.5 + 0.32 * cos(phase));
                double cy = H * (0.5 + 0.28 * sin(phase * 1.4));
                double rad = 90 + 40 * sin(phase * 2);
                CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.10);
                CGContextFillEllipseInRect(ctx, CGRectMake(cx - rad, cy - rad, rad * 2, rad * 2));
            }
            CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.92);
            CGContextSelectFont(ctx, "Helvetica-Bold", 64, kCGEncodingMacRoman);
            CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
            CGContextShowTextAtPoint(ctx, W * 0.5 - 150, H * 0.5, "FlowWall", 8);
            CGContextRelease(ctx);
            CGColorSpaceRelease(rgb);
            CVPixelBufferUnlockBaseAddress(pb, 0);
            [adaptor appendPixelBuffer:pb withPresentationTime:CMTimeMake(f, FPS)];
            CVPixelBufferRelease(pb);
        }
        [input markAsFinished];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        CGColorSpaceRelease(cs);
        printf("wrote %s\n", outPath.UTF8String);
    }
    return 0;
}
