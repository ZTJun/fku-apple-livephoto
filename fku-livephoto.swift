#!/usr/bin/env swift

import Foundation
import AVFoundation
import CoreMedia
import ImageIO

let args = CommandLine.arguments
guard args.count == 5 else {
    print("❌ 用法错误！")
    print("示例: ./fku-livephoto.swift input.heic input.mov output_prefix 5B3C7B5D-9A1F-432A-8E4A-114514191981")
    exit(1)
}

let imageInputURL = URL(fileURLWithPath: args[1])
let videoInputURL = URL(fileURLWithPath: args[2])
let outputPrefix = args[3]
let assetIdentifier = args[4]

let imageOutputURL = URL(fileURLWithPath: "\(outputPrefix).\(imageInputURL.pathExtension)")
let videoOutputURL = URL(fileURLWithPath: "\(outputPrefix).mov")

// --- 文件清理 ---
[imageOutputURL, videoOutputURL].forEach { url in
    if FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.removeItem(at: url)
    }
}

print("开始封装 - 注入 UUID [\(assetIdentifier)]")

// ==========================================
// 1. 处理图片 (HEIC / JPG) - 保持不变
// ==========================================
func processImage() -> Bool {
    print("正在注入图片 Metadata...")
    guard let source = CGImageSourceCreateWithURL(imageInputURL as CFURL, nil),
          let type = CGImageSourceGetType(source),
          let destination = CGImageDestinationCreateWithURL(imageOutputURL as CFURL, type, 1, nil) else {
        print("❌ 图片读取或创建失败！")
        return false
    }

    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return false
    }

    var mutableProperties = properties
    var makerApple = mutableProperties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] ?? [String: Any]()
    makerApple["17"] = assetIdentifier
    mutableProperties[kCGImagePropertyMakerAppleDictionary] = makerApple

    CGImageDestinationAddImageFromSource(destination, source, 0, mutableProperties as CFDictionary)

    if CGImageDestinationFinalize(destination) {
        print("图片处理完成: \(imageOutputURL.path)")
        return true
    } else {
        print("❌ 图片写入失败！")
        return false
    }
}

// ==========================================
// 2. 处理视频 (Apple 现代 async/await 并发版)
// ==========================================
func processVideo() async -> Bool {
    print("正在注入视频、定轨及 Metadata...")
    let asset = AVURLAsset(url: videoInputURL)

    guard let reader = try? AVAssetReader(asset: asset),
          let writer = try? AVAssetWriter(outputURL: videoOutputURL, fileType: .mov) else {
        return false
    }

    var trackOutputs = [AVAssetReaderTrackOutput]()
    var trackInputs = [AVAssetWriterInput]()

    // 【修复警告 1】：使用异步的 load(.tracks) 替代 .tracks
    guard let tracks = try? await asset.load(.tracks) else {
        print("❌ 无法异步加载视频轨道！")
        return false
    }

    for track in tracks {
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil)
        input.expectsMediaDataInRealTime = false

        if track.mediaType == .video {
            // 【修复警告 2】：使用异步的 load(.preferredTransform)
            if let transform = try? await track.load(.preferredTransform) {
                input.transform = transform
            }
        }

        if reader.canAdd(output) && writer.canAdd(input) {
            reader.add(output)
            writer.add(input)
            trackOutputs.append(output)
            trackInputs.append(input)
        }
    }

    let spec: NSDictionary = [
        kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString: "mdta/com.apple.quicktime.still-image-time",
        kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString: kCMMetadataBaseDataType_SInt8
    ]
    var desc: CMFormatDescription? = nil
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &desc)

    let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: desc)
    let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
    metadataInput.expectsMediaDataInRealTime = false

    if writer.canAdd(metadataAdaptor.assetWriterInput) {
        writer.add(metadataAdaptor.assetWriterInput)
    }

    let idItem = AVMutableMetadataItem()
    idItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
    idItem.keySpace = .quickTimeMetadata
    idItem.value = assetIdentifier as NSString
    idItem.dataType = kCMMetadataBaseDataType_UTF8 as String

    // 【修复警告 3】：使用异步的 load(.metadata) 获取原有的 GPS/相机 数据
    var preservedMetadata = (try? await asset.load(.metadata)) ?? []
    preservedMetadata.removeAll { ($0.key as? String)?.contains("content.identifier") == true }
    preservedMetadata.append(idItem)
    writer.metadata = preservedMetadata

    writer.startWriting()
    reader.startReading()
    writer.startSession(atSourceTime: .zero)

    let stillItem = AVMutableMetadataItem()
    stillItem.key = "com.apple.quicktime.still-image-time" as NSString
    stillItem.keySpace = .quickTimeMetadata
    stillItem.value = 0 as NSNumber
    stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
    let timeRange = CMTimeRange(start: .zero, duration: CMTimeMake(value: 1, timescale: 100))
    metadataAdaptor.append(AVTimedMetadataGroup(items: [stillItem], timeRange: timeRange))

    // 桥接 GCD 和 Swift 并发，等待所有轨道搬运完成
    return await withCheckedContinuation { continuation in
        let group = DispatchGroup()
        for (index, input) in trackInputs.enumerated() {
            group.enter()
            let output = trackOutputs[index]
            let queue = DispatchQueue(label: "track.writer.\(index)")

            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sampleBuffer = output.copyNextSampleBuffer() {
                        input.append(sampleBuffer)
                    } else {
                        input.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
        }

        group.notify(queue: .main) {
            writer.finishWriting {
                continuation.resume(returning: writer.status == .completed)
            }
        }
    }
}

// ==========================================
// 3. 执行流程 (Task 异步上下文)
// ==========================================
Task {
    if processImage() {
        let success = await processVideo()
        if success {
            print("Live Photo 已生成: \(imageOutputURL.lastPathComponent) & \(videoOutputURL.lastPathComponent)")
            print("选择两个文件，一并隔空投送 (AirDrop) 至手机即可喵")
            exit(0)
        } else {
            print("❌ 视频处理失败！")
            exit(1)
        }
    } else {
        exit(1)
    }
}

// 挂起主线程，等待 Task 里的异步任务全部跑完再释放资源
dispatchMain()
