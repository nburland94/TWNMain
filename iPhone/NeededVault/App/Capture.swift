// Needed Mobile Vault for iPhone — the camera (photos and clips) and the code reader
// that pairs the phone with your Mac.

import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// The iPhone camera: a photo or a clip, handed back ready to keep.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (Picked?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        p.videoQuality = .typeHigh
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (Picked?) -> Void
        init(done: @escaping (Picked?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL {
                // The camera's file goes away when the picker does: copy it first.
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(movie.pathExtension.isEmpty ? "mov" : movie.pathExtension)
                try? FileManager.default.copyItem(at: movie, to: dst)
                done(Picked(file: dst, name: Library.stamp("Clip") + ".\(dst.pathExtension)"))
            } else if let img = info[.originalImage] as? UIImage, let d = img.jpegData(compressionQuality: 0.92) {
                done(Picked(data: d, name: Library.stamp("Photo") + ".jpg", preview: img))
            } else {
                done(nil)
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

/// Reads the code on your Mac. Calls `found` once with what it says.
struct CodeReader: UIViewControllerRepresentable {
    let found: (String) -> Void
    func makeUIViewController(context: Context) -> ReaderController { ReaderController(found: found) }
    func updateUIViewController(_ vc: ReaderController, context: Context) {}
}

final class ReaderController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let found: (String) -> Void
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    init(found: @escaping (String) -> Void) { self.found = found; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { if ok { self.setUp() } }
        }
    }
    private func setUp() {
        guard let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else { return }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        p.frame = view.bounds
        view.layer.addSublayer(p)
        preview = p
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        guard PairedMac.from(s) != nil else { return }        // someone else's code: keep looking
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        found(s)
    }
}
