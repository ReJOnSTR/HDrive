//
//  MainDashboardView.swift
//  HDrive
//

import SwiftUI

public struct MainDashboardView: View {
    @ObservedObject var config = ServerConfig.shared
    @ObservedObject var server = WebDAVServer.shared
    
    @State private var showingQRCodeSheet = false
    @State private var showingGuideSheet = false
    @State private var isCopied = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Sunucu Durum Kahraman Kartı (Hero Status Card)
                    serverStatusHeroCard
                    
                    // 2. IP ve Bağlantı Adresi Kartı
                    if config.isRunning {
                        connectionAddressCard
                    }
                    
                    // 3. Canlı İstatistikler & Depolama
                    liveStatsSection
                    
                    // 4. Hızlı Erişim Eylemleri
                    quickActionsGrid
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("HDrive")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingQRCodeSheet) {
                qrCodeModalView
            }
            .sheet(isPresented: $showingGuideSheet) {
                QuickConnectGuideView()
            }
        }
    }
    
    // MARK: - Kahraman Durum Kartı
    private var serverStatusHeroCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.isRunning ? "Sunucu Yayında" : "Sunucu Durduruldu")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    
                    Text(config.isRunning ? "Bilgisayarlar bu cihaza bağlanabilir" : "Yerel ağ paylaşımı kapalı")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Durum Gösterge Işığı (Pulse Animasyonu)
                ZStack {
                    Circle()
                        .fill(config.isRunning ? Color.green.opacity(0.25) : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .scaleEffect(config.isRunning ? 1.15 : 1.0)
                        .animation(config.isRunning ? Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: config.isRunning)
                    
                    Circle()
                        .fill(config.isRunning ? Color.green : Color.gray)
                        .frame(width: 18, height: 18)
                }
            }
            
            Divider()
            
            // Başlat / Durdur Büyük Buton
            Button(action: toggleServer) {
                HStack {
                    Image(systemName: config.isRunning ? "stop.fill" : "play.fill")
                        .font(.headline)
                    Text(config.isRunning ? "Paylaşımı Durdur" : "Kablosuz Paylaşımı Başlat")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: config.isRunning ? [Color.red, Color.orange] : [Color.indigo, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: (config.isRunning ? Color.red : Color.indigo).opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
    
    // MARK: - Bağlantı Adresi Kartı
    private var connectionAddressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("PC Doğrudan Bağlantı Adresi", systemImage: "network")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.indigo)
                
                Spacer()
                
                Button(action: { showingQRCodeSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                        Text("QR Kod")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundColor(.indigo)
                    .cornerRadius(8)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.serverAddress)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundColor(.primary)
                    Text("Windows Dosya Gezgini veya Mac Finder'a yapıştırın")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: copyAddress) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(isCopied ? .green : .indigo)
                        .padding(10)
                        .background(Color.indigo.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            
            // Bilgisayara Bağlantı Sihirbazı Butonu
            Button(action: { showingGuideSheet = true }) {
                HStack {
                    Image(systemName: "display")
                    Text("Windows / Mac Ağ Sürücüsü Kurulum Rehberi")
                        .font(.footnote.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundColor(.indigo)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.indigo.opacity(0.2), lineWidth: 1.5)
        )
    }
    
    // MARK: - Canlı İstatistikler & Depolama
    private var liveStatsSection: some View {
        VStack(spacing: 12) {
            // İstatistik Hücreleri
            HStack(spacing: 12) {
                statCard(
                    title: "Aktif Bağlantı",
                    value: "\(config.activeConnectionsCount)",
                    icon: "person.2.fill",
                    tint: .blue
                )
                
                statCard(
                    title: "Alınan Veri",
                    value: ByteCountFormatter.string(fromByteCount: config.totalBytesReceived, countStyle: .file),
                    icon: "arrow.down.circle.fill",
                    tint: .green
                )
                
                statCard(
                    title: "Gönderilen",
                    value: ByteCountFormatter.string(fromByteCount: config.totalBytesSent, countStyle: .file),
                    icon: "arrow.up.circle.fill",
                    tint: .purple
                )
            }
            
            // Cihaz Depolama Kullanımı
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cihaz Depolama Durumu")
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
    }
    
    private func statCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .font(.footnote)
                Spacer()
            }
            Text(value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
    
    // MARK: - Hızlı Eylemler Izgarası
    private var quickActionsGrid: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: FileBrowserView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telefondaki Dosyalar")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Depolanan dosyalara göz at, yönet veya yeni ekle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
            }
        }
    }
    
    // MARK: - QR Kod Modalı
    private var qrCodeModalView: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Bilgisayardan Anında Bağlanın")
                    .font(.title3.bold())
                
                Text("Aynı Wi-Fi ağındaki bilgisayarınızın kamerası veya telefonu ile bu QR kodu okutarak web arayüzünü anında açabilirsiniz.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                if let qrImage = NetworkUtils.generateQRCode(from: config.serverAddress, size: 240) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                }
                
                Text(config.serverAddress)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.indigo)
                
                Spacer()
            }
            .padding(.top, 32)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        showingQRCodeSheet = false
                    }
                }
            }
        }
    }
    
    // MARK: - Yardımcı Fonksiyonlar
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
