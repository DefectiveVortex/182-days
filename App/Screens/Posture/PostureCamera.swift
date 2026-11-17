import AVFoundation
import DaysCore
import PhotosUI
import SwiftUI
import UIKit

/// This week's posture photo: the live camera with the week-1 photo laid over it as a ghost, so he
/// stands where he stood. A 5-second timer for a propped-up phone. No camera (simulator) or no
/// permission: choose a photo from the library instead.
struct PostureCameraSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    enum Status { case starting, live, denied, unavailable }

    @State private var camera = CameraSession()
    @State private var status: Status = .starting
    @State private var front = true
    @State private var showGhost = true
    @State private var useTimer = true
    @State private var countdown: Int?
    @State private var ghost: UIImage?
    @State private var taken: Data?
    @State private var takenImage: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var shutter = 0
    @State private var saved = 0

    var body: some View {
        let week = PhotoSummary.weekToday(store)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                        .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                Spacer()
                Text.label("Posture · week \(week)")
                Spacer()
                Button { showGhost.toggle() } label: {
                    Text("Ghost")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(showGhost ? Palette.accent : Palette.muted)
                        .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(ghost == nil)
                .opacity(ghost == nil ? 0 : 1)
                .accessibilityLabel(Text("Ghost overlay"))
                .accessibilityValue(Text(showGhost ? "On" : "Off"))
            }

            viewfinder

            Text(caption(week: week))
                .textStyle(.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task {
            if let url = PhotoSummary.ghost(store) { ghost = await PhotoImage.load(url) }
            await start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { setTaken(data) }
                picked = nil
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutter)
        .sensoryFeedback(.success, trigger: saved)
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                ZStack {
                    Palette.track
                    if let takenImage {
                        Image(uiImage: takenImage).resizable().scaledToFill()
                    } else if status == .live {
                        CameraPreview(session: camera.session)
                    } else {
                        unavailableNote
                    }
                    if showGhost, let ghost {
                        Image(uiImage: ghost).resizable().scaledToFill()
                            .opacity(0.35)
                            .allowsHitTesting(false)
                    }
                    if let countdown {
                        Text("\(countdown)")
                            .textStyle(.hero)
                            .foregroundStyle(Palette.text)
                            .contentTransition(.numericText(countdown: true))
                    }
                }
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(viewfinderLabel))
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var unavailableNote: some View {
        VStack(spacing: 12) {
            switch status {
            case .denied:
                Text("Camera access is off.").textStyle(.bodyMedium).foregroundStyle(Palette.text)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: Metrics.minTarget)
                }
                .buttonStyle(PressStyle())
            case .unavailable:
                Text("No camera on this device.").textStyle(.bodyMedium).foregroundStyle(Palette.text)
            case .starting, .live:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .padding(16)
    }

    private var viewfinderLabel: String {
        if takenImage != nil { return "This week's photo" + (showGhost && ghost != nil ? ", week one ghost over it" : "") }
        switch status {
        case .live: return "Camera" + (showGhost && ghost != nil ? ", week one ghost over it" : "")
        case .denied: return "Camera access is off"
        case .unavailable: return "No camera on this device"
        case .starting: return "Camera starting"
        }
    }

    private func caption(week: Int) -> String {
        if takenImage != nil { return "Keep it, or take it again." }
        if ghost == nil { return "Week 1. Side on, phone at chest height. This one becomes the ghost every Sunday after." }
        return "Stand where week one stood: side on, phone at chest height. Line up with the ghost."
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if let taken {
            WeightedRow(weights: [1, 1], spacing: 8) {
                OutlineButton(label: "Take it again") {
                    Text("Retake").textStyle(.bodyMedium)
                } action: {
                    self.taken = nil
                    takenImage = nil
                }
                FillButton(title: "KEEP", label: "Keep this photo") {
                    if store.savePosturePhoto(taken) {
                        saved += 1
                        dismiss()
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    OutlineButton(label: "Five second timer") {
                        Text(useTimer ? "5 s" : "No timer")
                            .textStyle(.bodyMedium)
                            .foregroundStyle(useTimer ? Palette.accent : Palette.text)
                    } action: {
                        useTimer.toggle()
                    }
                    .accessibilityValue(Text(useTimer ? "On" : "Off"))

                    Button(action: shoot) {
                        Rectangle()
                            .fill(Palette.text)
                            .frame(width: 64, height: 64)
                            .padding(5)
                            .overlay(Rectangle().strokeBorder(Palette.text, lineWidth: 2))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(status != .live || countdown != nil)
                    .opacity(status == .live ? 1 : 0.35)
                    .accessibilityLabel(Text("Take photo"))

                    OutlineButton(label: "Switch camera") {
                        Text("Flip").textStyle(.bodyMedium)
                    } action: {
                        front.toggle()
                        Task { _ = await camera.start(front: front) }
                    }
                    .disabled(status != .live)
                    .opacity(status == .live ? 1 : 0.35)
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Text("Choose from photos")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(status == .live ? Palette.muted : Palette.text)
                        .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: Actions

    private func start() async {
        guard CameraSession.hasCamera else { status = .unavailable; return }
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else { status = .denied; return }
        status = await camera.start(front: front) ? .live : .unavailable
    }

    private func shoot() {
        Task {
            if useTimer {
                for n in stride(from: 5, through: 1, by: -1) {
                    withAnimation { countdown = n }
                    try? await Task.sleep(for: .seconds(1))
                }
                countdown = nil
            }
            shutter += 1
            if let data = await camera.capture() { setTaken(data) }
        }
    }

    private func setTaken(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let jpeg = Self.downscaled(image)
        taken = jpeg
        takenImage = UIImage(data: jpeg)
    }

    /// At most 1600 px on the long side, JPEG 0.8: a few hundred KB a week.
    static func downscaled(_ image: UIImage, longSide: CGFloat = 1600) -> Data {
        let s = image.size
        let scale = min(1, longSide / max(s.width, s.height, 1))
        let size = CGSize(width: (s.width * scale).rounded(), height: (s.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Capture

/// The capture session. Configured, started and stopped on its own queue; only the preview layer
/// touches `session` from the main thread.
final class CameraSession: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "days.camera")
    private var input: AVCaptureDeviceInput?
    private var pending: [Int64: PhotoDelegate] = [:]

    static var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    /// Points the session at the front or back camera and starts it. False when that can't be done.
    func start(front: Bool) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async { cont.resume(returning: self.configure(front: front)) }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture() async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            queue.async {
                guard self.session.isRunning else { cont.resume(returning: nil); return }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                let id = settings.uniqueID
                let delegate = PhotoDelegate { data in
                    self.queue.async { self.pending[id] = nil }
                    cont.resume(returning: data)
                }
                self.pending[id] = delegate
                self.output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func configure(front: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
                ?? AVCaptureDevice.default(for: .video),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            return false
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { session.commitConfiguration(); return false }
            session.addOutput(output)
        }
        if let c = output.connection(with: .video) {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            // The saved photo matches the mirrored front preview, so the ghost lines up either way.
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = device.position == .front
            }
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        return true
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let done: @Sendable (Data?) -> Void
    init(done: @escaping @Sendable (Data?) -> Void) { self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        done(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let c = previewLayer.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
