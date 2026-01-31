import Cocoa
import CoreGraphics

class WallpaperTextOverlay {
    static func addTextToImage(imagePath: String, outputPath: String, title: String, location: String, date: String) {
        guard let image = NSImage(contentsOfFile: imagePath) else {
            print("Error: Could not load image from \(imagePath)")
            return
        }
        
        // Get image dimensions
        var imageRect = CGRect.zero
        imageRect.size = image.size
        
        // Create bitmap context with Retina support
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let width = Int(imageRect.size.width * scale)
        let height = Int(imageRect.size.height * scale)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Error: Could not create graphics context")
            return
        }
        
        // Scale context for Retina
        context.scaleBy(x: scale, y: scale)
        
        // Draw original image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Error: Could not get CGImage")
            return
        }
        context.draw(cgImage, in: imageRect)
        
        // Prepare text
        let text = "\(title) • \(location) • \(date)"
        
        // Text styling with SF Pro (native macOS font)
        let fontSize: CGFloat = 16
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        
        // Calculate text size
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: textAttributes)
        
        // Position: Bottom left with padding
        let padding: CGFloat = 30
        let textRect = CGRect(
            x: padding,
            y: padding,
            width: textSize.width + 20,
            height: textSize.height + 16
        )
        
        // Draw semi-transparent background
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        let path = CGPath(roundedRect: textRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.fillPath()
        
        // Draw text
        let textPoint = CGPoint(x: textRect.origin.x + 10, y: textRect.origin.y + 8)
        let nsText = text as NSString
        nsText.draw(at: textPoint, withAttributes: textAttributes)
        
        // Get final image
        guard let finalCgImage = context.makeImage() else {
            print("Error: Could not create final image")
            return
        }
        
        // Save as JPEG with high quality
        let finalImage = NSImage(cgImage: finalCgImage, size: imageRect.size)
        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            print("Error: Could not encode JPEG")
            return
        }
        
        // Write to file
        do {
            try jpegData.write(to: URL(fileURLWithPath: outputPath))
            print("Success: Image saved with text overlay to \(outputPath)")
        } catch {
            print("Error writing file: \(error)")
        }
    }
}

// Command line interface
if CommandLine.arguments.count >= 6 {
    let imagePath = CommandLine.arguments[1]
    let outputPath = CommandLine.arguments[2]
    let title = CommandLine.arguments[3]
    let location = CommandLine.arguments[4]
    let date = CommandLine.arguments[5]
    
    WallpaperTextOverlay.addTextToImage(
        imagePath: imagePath,
        outputPath: outputPath,
        title: title,
        location: location,
        date: date
    )
} else {
    print("Usage: WallpaperTextOverlay <input> <output> <title> <location> <date>")
    print("Example: WallpaperTextOverlay input.jpg output.jpg 'Eiffel Tower' 'Paris, France' '2026-01-30'")
}
