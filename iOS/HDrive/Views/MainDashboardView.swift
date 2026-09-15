//
//  MainDashboardView.swift
//  HDrive
//

import SwiftUI

public struct MainDashboardView: View {
    @ObservedObject var config = ServerConfig.shared
    @ObservedObject var server = WebDAVServer.shared
    
    @State private var isCopied = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Sunucu Başlat / Durdur Kartı
                    serverControlCard
                    
                    // 2. Canlı QR Kod ve Bağlantı Kartı
                    if config.isRunning {
                        qrShareCard
                    } else {
                        howItWorksCard
                    }
                    
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
        }
    }
    
    // MARK: - 1. Sunucu Kontrol Kartı
    private var serverControlCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.isRunning ? "Paylaşım Yayında" : "Paylaşım Kapalı")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    
                    Text(config.isRunning ? "Yerel ağdaki cihazlar bağlanabilir" : "Kablosuz dosya aktarımı için başlatın")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Durum Işığı
                ZStack {
                    Circle()
                        .fill(config.isRunning ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .scaleEffect(config.isRunning ? 1.15 : 1.0)
                        .animation(config.isRunning ? Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: config.isRunning)
                    
                    Circle()
                        .fill(config.isRunning ? Color.green : Color.gray)
                        .frame(width: 16, height: 16)
                }
            }
            
            Divider()
            
            Button(action: toggleServer) {
                HStack(spacing: 8) {
                    Image(systemName: config.isRunning ? "stop.fill" : "play.fill")
                        .font(.headline)
                    Text(config.isRunning ? "Paylaşımı Durdur" : "Kablosuz Paylaşımı Başlat")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: config.isRunning ? [Color.red, Color.orange] : [Color.indigo, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: (config.isRunning ? Color.red : Color.indigo).opacity(0.25), radius: 8, x: 0, y: 4)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - 2. QR Kod ve Hızlı Web Paylaşım Kartı (Sunucu Açıkken)
    private var qrShareCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Anında Web Bağlantısı (QR Kod)", systemImage: "qrcode")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.indigo)
                Spacer()
            }
            
            if let qrImage = NetworkUtils.generateQRCode(from: config.serverAddress, size: 220) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            }
            
            Text("Bilgisayarınızın veya başka bir telefonun kamerasıyla bu QR kodu okutarak dosyaları tarayıcıdan anında yönetin.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Divider()
            
            // Web ve WebDAV Adresi
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bağlantı Adresi:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(config.serverAddress)
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: copyAddress) {
                    HStack(spacing: 5) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Kopyalandı" : "Kopyala")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.indigo.opacity(0.1))
                    .foregroundColor(.indigo)
                    .cornerRadius(8)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.indigo.opacity(0.18), lineWidth: 1.5)
        )
    }
    
    // MARK: - Nasıl Çalışır Kartı (Sunucu Kapalıyken)
    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Nasıl Çalışır?", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            
            stepRow(num: "1", text: "Yukarıdaki butona basarak paylaşımı başlatın.")
            stepRow(num: "2", text: "Ekranda beliren QR kodu bilgisayarınızla okutun veya tarayıcınıza adresi yazın.")
            stepRow(num: "3", text: "Kabloya ihtiyaç duymadan dosyalarınızı doğrudan cihazınıza aktarın.")
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
    }
    
    private func stepRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.indigo)
                .clipShape(Circle())
            
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
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
