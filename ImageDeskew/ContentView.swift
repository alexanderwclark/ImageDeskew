//
//  ContentView.swift
//  ImageDeskew
//
//  Created by Alexander W Clark on 6/29/25.
//

//  ImageDeskewApp.swift — rel 2.4
//  ------------------------------------------------------------
//  Fixes “image flies off‑screen” bug by basing onDrag / pinch math on
//  the **gesture’s starting values** instead of compounding deltas.
//  Added `baseOffset` & `baseScale` caches inside the view‑model.
//  ------------------------------------------------------------
//  Sample lets a user:
//    • Pick a photo from Photos
//    • Pinch‑zoom & pan the image (stable)
//    • Resize crop box via 4 corner + 2 side handles (width‑only)
//    • Undo / Redo any manipulation
//    • Tap “Crop & Deskew” → Vision rectangle detect → Core Image perspective‑correct
//  ------------------------------------------------------------
//  Tested in Xcode 15.3 / iOS 17.

import SwiftUI
import PhotosUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins



// MARK: - Low‑level helpers
extension UIImage {
    /// Returns a new image rendered upright so Core Graphics math is reliable.
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer {
            UIGraphicsEndImageContext()
        }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}



extension CGPoint {
    /// Converts a Vision‑normalized point (0…1) to pixel coords (flips y‑axis).
    func denormalized(to cg: CGImage) -> CGPoint {
        CGPoint(x: x * CGFloat(cg.width),
                y: (1 - y) * CGFloat(cg.height))
    }
}



/// Fits `image` inside `container`, preserving aspect ratio.
func fittedImageSize(for image: CGSize,
                     in container: CGSize) -> CGSize {
    let s = min(container.width / image.width,
                container.height / image.height)
    return .init(width: image.width * s,
                 height: image.height * s)
}



// Convenience snapshot (undo/redo)
struct CropSnapshot: Equatable {
    var scale: CGFloat
    var offset: CGSize
    var cropRect: CGRect
}

/// Behavior when a crop rectangle extends outside the displayed image frame.
enum OutOfBoundsBehavior {
    /// Expand the image with transparent padding so the full crop rect is kept.
    case pad
    /// Adjust the crop origin so the full rect fits inside the image frame.
    case clamp
}



// MARK: - Processing engine
struct CropEngine {
    static func resize(rect r0: CGRect,
                       handleIndex idx: Int,
                       translation t: CGSize,
                       imageFrame f: CGRect,
                       minSide m: CGFloat) -> CGRect
    {
        var r = r0
        switch idx
        {
        case 0: r.origin.x += t.width;
                r.origin.y += t.height;
                r.size.width -= t.width;
                r.size.height -= t.height // TL
        
        case 1: r.origin.y += t.height;
                r.size.width += t.width;
                r.size.height -= t.height // TR
        
        case 2: r.size.width += t.width;
                r.size.height += t.height // BR
        
        case 3: r.origin.x += t.width;
                r.size.width -= t.width;
                r.size.height += t.height // BL
        
        case 4: r.origin.x += t.width;
                r.size.width -= t.width // LEFT‑MID (width only)
        
        case 5: r.size.width += t.width // RIGHT‑MID (width only)
                default: break
        }
        
        // Clamp min side
        r.size.width = max(m, r.width)
        r.size.height = max(m, r.height)
        
        // Clamp within image frame
        if r.minX < f.minX { r.origin.x = f.minX }
        if r.maxX > f.maxX { r.size.width = f.maxX - r.minX }
        if r.minY < f.minY { r.origin.y = f.minY }
        if r.maxY > f.maxY { r.size.height = f.maxY - r.minY }
        return r
    }

    
    
    static func process(image: UIImage,
                        displaySize: CGSize,
                        scale: CGFloat,
                        offset: CGSize,
                        cropRect: CGRect,
                        outOfBounds: OutOfBoundsBehavior = .clamp) -> UIImage? {
        
        let upright = image.fixedOrientation()
        guard let cg = upright.cgImage else {
            return nil
            }
        
            // 1. Frame of displayed image in container coords
        let fit = fittedImageSize(for: image.size, in: displaySize)
        let shown = CGSize(width: fit.width * scale, height: fit.height * scale)
        let frame = CGRect(
            x: ((displaySize.width - shown.width)/2) + offset.width,
            y: ((displaySize.height - shown.height)/2) + offset.height,
            width: shown.width,
            height: shown.height)

        var adjusted = cropRect
        let exceeds = !frame.contains(cropRect)
        if exceeds && outOfBounds == .clamp {
            if adjusted.minX < frame.minX { adjusted.origin.x = frame.minX }
            if adjusted.minY < frame.minY { adjusted.origin.y = frame.minY }
            if adjusted.maxX > frame.maxX { adjusted.origin.x = frame.maxX - adjusted.width }
            if adjusted.maxY > frame.maxY { adjusted.origin.y = frame.maxY - adjusted.height }
        }

        let displayCrop = outOfBounds == .pad ? cropRect : adjusted

        // Map crop rectangle (in display coords) to normalized
        let nx = (displayCrop.minX - frame.minX) / frame.width
        let ny = (displayCrop.minY - frame.minY) / frame.height
        let nw = displayCrop.width / frame.width
        let nh = displayCrop.height / frame.height

        var pixFull = CGRect(
            x: nx * CGFloat(cg.width),
            y: ny * CGFloat(cg.height),
            width: nw * CGFloat(cg.width),
            height: nh * CGFloat(cg.height))

        let imageRect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let pixClamped = pixFull.intersection(imageRect)
        guard !pixClamped.isNull else { return nil }

        var cropped: CGImage
        if let cgCrop = cg.cropping(to: pixClamped.integral) {
            cropped = cgCrop
        } else {
            return nil
        }

        if outOfBounds == .pad && pixFull != pixClamped {
            let renderer = UIGraphicsImageRenderer(size: pixFull.size)
            let offX = max(0, -pixFull.minX)
            let offY = max(0, -pixFull.minY)
            cropped = renderer.image { ctx in
                ctx.cgContext.setFillColor(UIColor.clear.cgColor)
                ctx.fill(CGRect(origin: .zero, size: pixFull.size))
                ctx.cgContext.draw(cropped, in: CGRect(x: offX, y: offY, width: pixClamped.width, height: pixClamped.height))
            }.cgImage!
        }

        #if DEBUG
        print("Cropping CGImage to rect: \(pixFull)")
        print("Original size: \(cg.width)x\(cg.height)")
        let expectedCropWidth = Int(round(pixClamped.integral.width))
        let expectedCropHeight = Int(round(pixClamped.integral.height))
        assert(cropped.width == expectedCropWidth && cropped.height == expectedCropHeight,
               "CGImage cropped size \(cropped.width)x\(cropped.height) != expected \(expectedCropWidth)x\(expectedCropHeight)")
        #endif
        
        // 3. Vision rect detect
        let handler = VNImageRequestHandler(cgImage: cropped)
        let req = VNDetectRectanglesRequest()
            req.minimumAspectRatio = 0.3  // or 0.2 for receipts/business cards
            req.maximumAspectRatio = 1.0  // 1.0 = square, or use a bit higher for tall/skinny docs
            req.minimumSize = 0.2         // 20% of image min dimension
            req.maximumObservations = 1
            req.minimumConfidence = 0.5
        try? handler.perform([req])
        let o = (req.results as? [VNRectangleObservation])?.first
            if let o = o {
                #if DEBUG
                print("\n Detected Vision corners (in pixels of crop):")
                print("Top Left:     \(o.topLeft.denormalized(to: cropped))")
                print("Top Right:    \(o.topRight.denormalized(to: cropped))")
                print("Bottom Left:  \(o.bottomLeft.denormalized(to: cropped))")
                print("Bottom Right: \(o.bottomRight.denormalized(to: cropped))")
                #endif
            }

            #if DEBUG
            print("\n Found rectangle? \(o != nil), corners: \(o?.topLeft ?? .zero), \(o?.topRight ?? .zero), \(o?.bottomLeft ?? .zero), \(o?.bottomRight ?? .zero)\n")
            print("cropRect (view): \(cropRect)")
            print("frame (image in view): \(frame)")
            print("Resulting normalized crop: x:\(nx), y:\(ny), w:\(nw), h:\(nh)")
            print("Crop in image pixels: \(pixFull)")
            print("Original image size: \(cg.width)x\(cg.height)")
            #endif
            
            // 4. Perspective correction
        let ci = CIImage(cgImage: cropped)
        let ctx = CIContext()
        let outCG: CGImage
        if let o = o {
            let filt = CIFilter.perspectiveCorrection()
                filt.inputImage = ci  // ci is CIImage(cgImage: cropped)
                filt.topLeft     = o.topLeft    .denormalized(to: cropped)
                filt.topRight    = o.topRight   .denormalized(to: cropped)
                filt.bottomLeft  = o.bottomLeft .denormalized(to: cropped)
                filt.bottomRight = o.bottomRight.denormalized(to: cropped)
            if let out = filt.outputImage,
                let result = ctx.createCGImage(out, from: out.extent)
            {
                outCG = result
            } else {
                outCG = cropped
            }
        } else {
            outCG = cropped
        }

        let resultImage = UIImage(cgImage: outCG,
                                   scale: image.scale,
                                   orientation: .up)

        return resultImage
    }
}

//// MARK: - App entry
//@main struct ImageDeskewApp: App {
//    var body: some Scene { WindowGroup { ContentView() } }
//}

// MARK: Root picker / preview
struct ContentView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var original: UIImage?
    @State private var corrected: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Group {
                    if let ui = corrected ?? original {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 5)
                    } else {
                        Text("Pick a photo to begin")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: 340)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Pick Photo", systemImage: "photo")
                }
                    .buttonStyle(.borderedProminent)
                    .onChange(of: pickerItem)
                {
                    _ in loadImage()
                }

                if let orig = original {
                    NavigationLink("Crop / Deskew") {
                        CropperView(input: orig) { corrected = $0 }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("ImageDeskew")
        }
    }
    
    
    private func loadImage() {
        Task {
            @MainActor in
            guard let data = try? await pickerItem?.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data)
            else
            {
                return
            }
            original = ui;
            corrected = nil
        }
    }
}



// MARK: - Cropper Screen
struct CropperView: View {
    let input: UIImage
    var onComplete: (UIImage) -> Void
    @StateObject private var vm: CropperViewModel
    @Environment(\.dismiss) private var dismiss

    init(input: UIImage, onComplete: @escaping (UIImage) -> Void) {
        self.input = input
        self.onComplete = onComplete
        _vm = StateObject(wrappedValue: CropperViewModel(imageSize: input.size))
    }

    var body: some View {
        GeometryReader {
            geo in
            ZStack {
                Color.black
                     .opacity(0.9)
                     .ignoresSafeArea()

                //let display = vm.displaySize(for: input, in: geo.size)
                // Displayed image
                Image(uiImage: input)
                    .resizable()
                    .frame(width: vm.displaySize(for: input,
                                                 in: geo.size).width,
                           height: vm.displaySize(for: input,
                                                  in: geo.size).height)
                    .scaleEffect(vm.scale)
                    .offset(vm.offset)
                    .gesture(vm.isDraggingHandle ? nil : vm.combinedGestures())

                // Crop overlay & handles
                CropOverlay(rect: vm.cropRect)
                {
                    idx, value, isDragging in
                    vm.handleHandleDrag(idx: idx,
                                        value: value,
                                        isDragging: isDragging,
                                        container: geo.size)
                }

                // Toolbar
                VStack {
                    Spacer()
                    HStack {
                        Button("Undo") { vm.undo() }.disabled(!vm.canUndo)
                        Button("Redo") { vm.redo() }.disabled(!vm.canRedo)
                        Spacer()
                        Button("Cancel") { dismiss() }.tint(.red)
                        Button("Crop & Deskew") {
                            if let out = CropEngine.process(image: input,
                                                            displaySize: geo.size,
                                                            scale: vm.scale,
                                                            offset: vm.offset,
                                                            cropRect: vm.cropRect)
                            {
                                onComplete(out);
                                dismiss()
                            }
                        }
                        .tint(.green)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .onAppear { vm.imageSize = input.size; vm.containerSize = geo.size }            .
            onChange(of: geo.size) { s in vm.containerSize = s }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}



// MARK: - View‑model (fixed gesture math)
final class CropperViewModel: ObservableObject {
    // Live state
    @Published var scale: CGFloat = 1
    @Published var offset: CGSize = .zero
    @Published var cropRect: CGRect = .zero
    @Published var isDraggingHandle: Bool = false

    
    // Image dimensions
       //private let imageSize: CGSize

       init(imageSize: CGSize = .zero) {
           self.imageSize = imageSize
       }
    
    // Gesture bases
    private var baseScale: CGFloat = 1
    private var baseOffset: CGSize = .zero

    // Undo/redo
    private var history: [CropSnapshot] = []
    private var cursor = 0

    var imageSize: CGSize = .zero
    // Container tracking
    var containerSize: CGSize = .zero {
        didSet {
            guard cropRect == .zero else { return }
            let imgFrame = imageFrame(in: containerSize)
            // Inset by 10% on each side (or 60% of shortest dimension)
            let side = min(imgFrame.width, imgFrame.height) * 0.6
            let crop = CGRect(x: imgFrame.midX - (side / 2),
                              y: imgFrame.midY - (side / 2),
                              width: side,
                              height: side)
            cropRect = clampRect(crop,
                                 to: imgFrame,
                                 minSize: 40)
            pushSnapshot()
        }
    }

    
    
    func clampRect(_ rect: CGRect,
                   to bounds: CGRect,
                   minSize: CGFloat,
                   behavior: OutOfBoundsBehavior = .clamp) -> CGRect {
        var r = rect

        // Clamp size
        r.size.width = max(r.width, minSize)
        r.size.height = max(r.height, minSize)

        guard behavior == .clamp else { return r }

        // Clamp position so rect stays within bounds
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }

        // If still out of bounds after clamping (crop box bigger than image), force fit
        r.origin.x = min(max(r.origin.x, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.origin.y, bounds.minY), bounds.maxY - r.height)

        return r
    }

    
    
    // MARK: Gestures (stable)
    func combinedGestures() -> some Gesture {
        let onDrag = DragGesture()
            .onChanged { [self] value in
                offset = CGSize(width: self.baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height)
            }
            .onEnded { [self] _ in
                self.baseOffset = self.offset
                pushSnapshot()
            }

        let pinch = MagnificationGesture()
            .onChanged { [self] value in
                scale = max(0.5,
                        min(4, self.baseScale * value))
            }
            .onEnded { [self] _ in
                baseScale = scale
                pushSnapshot()
            }

        return onDrag.simultaneously(with: pinch)
    }
 
    
    
    private func imageFrame(in container: CGSize) -> CGRect {
        let fit = fittedImageSize(for: imageSize,
                                  in: container)
        let shown = CGSize(width: fit.width * scale,
                           height: fit.height * scale)
        return CGRect(x: ((container.width - shown.width) / 2) + offset.width,
                      y: ((container.height - shown.height) / 2) + offset.height,
                      width: shown.width,
                      height: shown.height
        )
    }
    
    
    
    private var baseCropRect: CGRect = .zero
    // Handle onDrag
    func handleHandleDrag(idx: Int,
                          value: DragGesture.Value,
                          isDragging: Bool,
                          container: CGSize)
    {
            isDraggingHandle = isDragging
            let minSide: CGFloat = 40
            let imgFrame = imageFrame(in: container)

            if value.startLocation == value.location {
                // On drag start: anchor the cropRect
                baseCropRect = cropRect
                pushSnapshot()
            }
            
            // Always apply translation relative to baseCropRect, not to cropRect directly
            let proposedRect = CropEngine.resize(rect: baseCropRect,
                                                 handleIndex: idx,
                                                 translation: value.translation,
                                                 imageFrame: imgFrame,
                                                 minSide: minSide)
            cropRect = clampRect(proposedRect,
                                 to: imgFrame,
                                 minSize: minSide)
            
            if value.predictedEndTranslation == .zero {
                pushSnapshot()
            }
        }


    
    // Undo/redo
    var canUndo: Bool { cursor > 1 }
    var canRedo: Bool { cursor < history.count }
    func undo() { guard canUndo else { return }; cursor-=1; apply(history[cursor-1]) }
    func redo() { guard canRedo else { return }; apply(history[cursor]); cursor+=1 }

    private func pushSnapshot() {
        let snap = CropSnapshot(scale: scale,
                                offset: offset,
                                cropRect: cropRect)
        if cursor < history.count {
            history.removeSubrange(cursor...)
        }
        history.append(snap);
        cursor = history.count
    }
    
    
    
    private func apply(_ s: CropSnapshot) {
        scale = s.scale;
        offset = s.offset;
        cropRect = s.cropRect
        baseScale = scale;
        baseOffset = offset
    }

    
    
    // Image size helper
    func displaySize(for image: UIImage? = nil,
                     in container: CGSize) -> CGSize {
        let base = image?.size ?? imageSize
        return fittedImageSize(for: base == .zero ? CGSize(width:1, height:1) : base,
                               in: container)
    }
}



// MARK: - Overlay with handles
struct CropOverlay: View {
    let rect: CGRect
    var onDrag: (Int, DragGesture.Value, Bool) -> Void
    private let handleSize: CGFloat = 20
    
    var body: some View {
        // Outside shade
            Color.black
                 .opacity(0.5)
                 .mask
        {
            Rectangle()
                .fill(style: .init(eoFill: true))
                .overlay(
                    Rectangle()
                        .path(in: rect)
                        .fill(Color.white))
            }
            // Border
            Rectangle()
                .path(in: rect)
                .stroke(Color.yellow, lineWidth: 2)
            // Handles
            ForEach(0..<6, id: \.self) { idx in
                Circle()
                    .fill(Color.yellow)
                    .frame(width: handleSize, height: handleSize)
                    .position(handlePosition(idx: idx,
                                             in: rect))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onDrag(idx, value, true)
                            }
                            .onEnded { value in
                                onDrag(idx, value, false)
                            }
                    )
                    .shadow(radius: 2)
            }
        }
        
    
    
        // Calculate handle positions: 0-TL, 1-TR, 2-BR, 3-BL, 4-LEFT-MID, 5-RIGHT-MID
        func handlePosition(idx: Int,
                            in rect: CGRect) -> CGPoint {
            switch idx {
            case 0: // Top Left
                return rect.origin
            case 1: // Top Right
                return CGPoint(x: rect.maxX, y: rect.minY)
            case 2: // Bottom Right
                return CGPoint(x: rect.maxX, y: rect.maxY)
            case 3: // Bottom Left
                return CGPoint(x: rect.minX, y: rect.maxY)
            case 4: // Left-Mid (width only)
                return CGPoint(x: rect.minX, y: rect.midY)
            case 5: // Right-Mid (width only)
                return CGPoint(x: rect.maxX, y: rect.midY)
            default:
                return .zero
            }
        }
    }
