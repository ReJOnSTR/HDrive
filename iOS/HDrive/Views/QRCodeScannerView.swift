//
//  QRCodeScannerView.swift
//  HDrive (iOS)
//

import SwiftUI
import AVFoundation

public struct QRCodeScannerView: View {
    public var onCodeScanned: (String) -> Void
    public var onDismiss: () -> Void
    
    @State private var manualAddress: String = "http://192.168.1.100:8080"
    @State private var hasCamera: Bool = true
    
    public init(onCodeScanned: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.onCodeScanned = onCodeScanned
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                #if targetEnvironment(simulator)
                simulatorFallbackView
                #else
                if hasCamera {
                    CameraScannerRepresentable { code in
                        onCodeScanned(code)
                    } onNoCamera: {
                        hasCamera = false
                    }
                    .ignoresSafeArea()
                    
                    // Tarayıcı Hedef Çerçevesi (Viewfinder Reticle)
                    viewfinderOverlay
                } else {
                    simulatorFallbackView
                }
                #endif
            }
            .navigationTitle("PC QR Kodu Tara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
    }
    
    // MARK: - Hedef Çerçevesi
    private var viewfinderOverlay: some View {
        VStack(spacing: 24) {
            Text("Bilgisayar ekranındaki QR kodu çerçevenin içine hizalayın")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.top, 40)
            
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 250, height: 250)
                
                // Köşe Vurguları
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.indigo, lineWidth: 4)
                    .frame(width: 250, height: 250)
                    .opacity(0.6)
            }
            
            Spacer()
            
            // Manuel Giriş Düğmesi
            Button(action: { hasCamera = false }) {
                Label("Adresi Elle Gir", systemImage: "keyboard")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20)
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Simülatör / Kamera Yok Durumu
    private var simulatorFallbackView: some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.indigo)
            
            Text("QR Kod Tarayıcı")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text("Simülatör ortamında veya kamera erişimi yokken bilgisayarınızdaki IP adresini elle girerek doğrudan bağlanabilirsiniz:")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Bilgisayar WebDAV / HTTP Adresi:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                TextField("http://192.168.1.x:8080", text: $manualAddress)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.15))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 28)
            
            Button(action: {
                let trimmed = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCodeScanned(trimmed)
                }
            }) {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Bilgisayara Bağlan")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.indigo)
                .cornerRadius(12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
        }
        .padding()
    }
}

// MARK: - Kamera Denetleyicisi
struct CameraScannerRepresentable: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    var onNoCamera: () -> Void
    
    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let vc = CameraScannerViewController()
        vc.onCodeScanned = onCodeScanned
        vc.onNoCamera = onNoCamera
        return vc
    }
    
    func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {}
}

class CameraScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    var onNoCamera: (() -> Void)?
    var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }
    
    func setupCamera() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onNoCamera?()
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            onNoCamera?()
            return
        }
        
        let session = AVCaptureSession()
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            onNoCamera?()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onNoCamera?()
            return
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview
        
        self.captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }
        
        hasScanned = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        captureSession?.stopRunning()
        onCodeScanned?(stringValue)
    }
}
