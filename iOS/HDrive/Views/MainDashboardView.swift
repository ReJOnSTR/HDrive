//
//  MainDashboardView.swift
//  HDrive
//

import SwiftUI

public struct MainDashboardView: View {
    @ObservedObject var config = ServerConfig.shared
    @ObservedObject var server = WebDAVServer.shared
    
    @State private var showingScannerSheet = false
    @State private var connectedPCURL: String? = nil
    @State private var isCopied = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Birincil Eylem: PC QR Kodu Tara (Kamera)
                    scanPCHeroCard
                    
                    // 2. İkincil Eylem: Telefonun Kendi Paylaşım Sunucusu
                    phoneSharingCard
                    
                    // 3. Cihaz Depolama Durumu
                    deviceStorageCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Paylaşım")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingScannerSheet) {
                QRCodeScannerView(onCodeScanned: { scannedUrl in
                    showingScannerSheet = false
                    connectedPCURL = scannedUrl
                }, onDismiss: {
                    showingScannerSheet = false
                })
            }
            .fullScreenCover(isPresented: Binding(
                get: { connectedPCURL != nil },
                set: { if !$0 { connectedPCURL = nil } }
            )) {
                if let url = connectedPCURL {
                    ConnectedPCView(serverURL: url, onDisconnect: {
                        connectedPCURL = nil
                    })
                }
            }
        }
    }
    
    // MARK: - 1. PC QR Kodu Tara (Kamera)
    private var scanPCHeroCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bilgisayara Bağlan")
                        .font(.title3.bold())
                    Text("Bilgisayarınızın ekranındaki QR kodu okutun")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: { showingScannerSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.headline)
                    Text("PC'deki QR Kodu Tara")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.indigo, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: Color.indigo.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - 2. Telefonun Kendi Paylaşım Sunucusu
    private var phoneSharingCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bu Telefonu Paylaşıma Aç")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(config.isRunning ? "Telefonun web sunucusu yayında" : "Bilgisayardan bu telefona bağlanmak için")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: toggleServer) {
                    Text(config.isRunning ? "Durdur" : "Başlat")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(config.isRunning ? .red : .indigo)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background((config.isRunning ? Color.red : Color.indigo).opacity(0.12))
                        .cornerRadius(10)
                }
            }
            
            if config.isRunning {
                Divider()
                
                if let qrImage = NetworkUtils.generateQRCode(from: config.serverAddress, size: 180) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                }
                
                HStack {
                    Text(config.serverAddress)
                        .font(.system(.footnote, design: .monospaced).weight(.bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: copyAddress) {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "Kopyalandı" : "Kopyala")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.1))
                        .foregroundColor(.indigo)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
    }
    
    // MARK: - 3. Cihaz Depolama Kartı
    private var deviceStorageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Cihaz Depolama Alanı", systemImage: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(ByteCountFormatter.string(fromByteCount: config.usedDiskSpace, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: config.totalDiskSpace, countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: config.diskUsagePercentage)
                .tint(.indigo)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Eylemler
    private func toggleServer() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if config.isRunning {
            server.stop()
        } else {
            server.start()
        }
    }
    
    private func copyAddress() {
        UIPasteboard.general.string = config.serverAddress
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
