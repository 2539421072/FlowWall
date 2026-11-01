#import <Cocoa/Cocoa.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { printf("usage: mkicon src out\n"); return 1; }
        NSImage *src = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        if (!src) { printf("load fail\n"); return 2; }
        const NSInteger S = 1024;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:S pixelsHigh:S
                                                                       bitsPerSample:8 samplesPerPixel:4
                                                                            hasAlpha:YES isPlanar:NO
                                                                      colorSpaceName:NSCalibratedRGBColorSpace
                                                                         bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext setCurrentContext:ctx];
        [[NSColor clearColor] set];
        NSRectFill(NSMakeRect(0, 0, S, S));

        CGFloat inset = 100, body = S - 2 * inset, radius = 185;
        NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(inset, inset, body, body)
                                                            xRadius:radius yRadius:radius];
        [clip addClip];
        CGFloat over = body * 0.055;
        [src drawInRect:NSMakeRect(inset - over, inset - over, body + over * 2, body + over * 2)
               fromRect:NSZeroRect
              operation:NSCompositingOperationSourceOver
               fraction:1.0];
        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        BOOL ok = [png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
        printf("%s (%lu bytes)\n", ok ? "ok" : "write fail", (unsigned long)png.length);
    }
    return 0;
}
