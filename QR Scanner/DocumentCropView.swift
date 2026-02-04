import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct DocumentCropView: View {
    let image: UIImage
    var onSave: (UIImage) -> Void
    var onCancel: () -> Void
    
    @State private var topLeft: CGPoint = .zero
    @State private var topRight: CGPoint = .zero
    @State private var bottomLeft: CGPoint = .zero
    @State private var bottomRight: CGPoint = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var initialized = false
    
    private let handleSize: CGFloat = 24
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageSize = calculateImageSize(for: geometry.size)
                let imageOrigin = CGPoint(
                    x: (geometry.size.width - imageSize.width) / 2,
                    y: (geometry.size.height - imageSize.height) / 2
                )
                
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    // Document image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    
                    // Dim overlay with cutout
                    Canvas { context, size in
                        // Fill entire area with dim color
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))
                        
                        // Cut out the crop area
                        var path = Path()
                        path.move(to: topLeft)
                        path.addLine(to: topRight)
                        path.addLine(to: bottomRight)
                        path.addLine(to: bottomLeft)
                        path.closeSubpath()
                        
                        context.blendMode = .destinationOut
                        context.fill(path, with: .color(.black))
                    }
                    .allowsHitTesting(false)
                    
                    // Crop quadrilateral outline
                    Path { path in
                        path.move(to: topLeft)
                        path.addLine(to: topRight)
                        path.addLine(to: bottomRight)
                        path.addLine(to: bottomLeft)
                        path.closeSubpath()
                    }
                    .stroke(Color.white, lineWidth: 2)
                    .allowsHitTesting(false)
                    
                    // Corner handles
                    CornerHandle(position: $topLeft, bounds: geometry.size, handleSize: handleSize)
                    CornerHandle(position: $topRight, bounds: geometry.size, handleSize: handleSize)
                    CornerHandle(position: $bottomLeft, bounds: geometry.size, handleSize: handleSize)
                    CornerHandle(position: $bottomRight, bounds: geometry.size, handleSize: handleSize)
                }
                .onAppear {
                    if !initialized {
                        initializeCorners(imageSize: imageSize, imageOrigin: imageOrigin)
                        imageFrame = CGRect(origin: imageOrigin, size: imageSize)
                        initialized = true
                    }
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let cropped = performPerspectiveCrop()
                        onSave(cropped ?? image)
                    }
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private func calculateImageSize(for containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            let width = containerSize.width * 0.9
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height * 0.9
            return CGSize(width: height * imageAspect, height: height)
        }
    }
    
    private func initializeCorners(imageSize: CGSize, imageOrigin: CGPoint) {
        let margin: CGFloat = 20
        topLeft = CGPoint(x: imageOrigin.x + margin, y: imageOrigin.y + margin)
        topRight = CGPoint(x: imageOrigin.x + imageSize.width - margin, y: imageOrigin.y + margin)
        bottomLeft = CGPoint(x: imageOrigin.x + margin, y: imageOrigin.y + imageSize.height - margin)
        bottomRight = CGPoint(x: imageOrigin.x + imageSize.width - margin, y: imageOrigin.y + imageSize.height - margin)
    }
    
    private func performPerspectiveCrop() -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        // Convert screen coordinates to image coordinates
        let scaleX = image.size.width / imageFrame.width
        let scaleY = image.size.height / imageFrame.height
        
        func toImageCoord(_ point: CGPoint) -> CGPoint {
            let x = (point.x - imageFrame.origin.x) * scaleX
            let y = (point.y - imageFrame.origin.y) * scaleY
            // CIImage has origin at bottom-left, flip Y
            return CGPoint(x: x, y: image.size.height - y)
        }
        
        let imgTopLeft = toImageCoord(topLeft)
        let imgTopRight = toImageCoord(topRight)
        let imgBottomLeft = toImageCoord(bottomLeft)
        let imgBottomRight = toImageCoord(bottomRight)
        
        // Apply perspective correction
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: imgTopLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: imgTopRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: imgBottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: imgBottomRight), forKey: "inputBottomRight")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

struct CornerHandle: View {
    @Binding var position: CGPoint
    let bounds: CGSize
    let handleSize: CGFloat
    
    @State private var isDragging = false
    
    var body: some View {
        Circle()
            .fill(isDragging ? Color.yellow : Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Circle()
                    .stroke(Color.blue, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.5), radius: 4)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newX = min(max(value.location.x, 0), bounds.width)
                        let newY = min(max(value.location.y, 0), bounds.height)
                        position = CGPoint(x: newX, y: newY)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
