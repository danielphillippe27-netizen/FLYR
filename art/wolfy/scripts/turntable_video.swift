import Foundation
import AVFoundation
import AppKit

let directory=URL(fileURLWithPath:CommandLine.arguments[1])
let output=directory.appendingPathComponent("wolfy-turntable.mp4")
try? FileManager.default.removeItem(at:output)
let writer=try AVAssetWriter(outputURL:output,fileType:.mp4)
let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:512,AVVideoHeightKey:512])
let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:512,kCVPixelBufferHeightKey as String:512])
writer.add(input);writer.startWriting();writer.startSession(atSourceTime:.zero)
for frame in 0..<96 {
 while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.01) }
 let url=directory.appendingPathComponent(String(format:"turntable_%03d.png",frame/4))
 let image=NSImage(contentsOf:url)!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
 var pixel:CVPixelBuffer?
 CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)
 CVPixelBufferLockBaseAddress(pixel!,[])
 let context=CGContext(data:CVPixelBufferGetBaseAddress(pixel!),width:512,height:512,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel!),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
 context.draw(image,in:CGRect(x:0,y:0,width:512,height:512))
 CVPixelBufferUnlockBaseAddress(pixel!,[])
 assert(adaptor.append(pixel!,withPresentationTime:CMTime(value:Int64(frame),timescale:24)))
}
input.markAsFinished();let semaphore=DispatchSemaphore(value:0)
writer.finishWriting{semaphore.signal()};semaphore.wait()
if writer.status != .completed { fatalError("Video export failed: \(String(describing:writer.error))") }
print(output.path)
