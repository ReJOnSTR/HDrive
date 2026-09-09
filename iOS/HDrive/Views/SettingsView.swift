//
//  SettingsView.swift
//  HDrive
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var config = ServerConfig.shared
    @State private var portString: String = "8080"
    @State private var showingRestartAlert = false
    
    public init() {}
    
    public var body: some View {
        Form {
            Section(header: Text("Sunucu Yapılandırması")) {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("8080", text: $portString)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: portString) { newValue in
                            if let newPort = UInt16(newValue) {
                                config.port = newPort
                                config.refreshIPAddress()
                                if config.isRunning {
                                    showingRestartAlert = true
                                }
                            }
                        }
                }
                
                Toggle("Yazma ve Düzenleme İzni", isOn: $config.allowWrite)
                Toggle("Ekranı Açık Tut (Uyku Engelleme)", isOn: $config.keepScreenOn)
                    .onChange(of: config.keepScreenOn) { enabled in
                        UIApplication.shared.isIdleTimerDisabled = enabled && config.isRunning
                    }
            }
            
            Section(header: Text("Güvenlik & Parola"), footer: Text("Parola koruması açıldığında, PC veya Web üzerinden bağlanırken bu kullanıcı adı ve şifre istenir.")) {
                Toggle("Parola Koruması", isOn: $config.requiresAuth)
                
                if config.requiresAuth {
                    HStack {
                        Text("Kullanıcı Adı")
                        Spacer()
                        TextField("admin", text: $config.username)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Şifre")
                        Spacer()
                        SecureField("hdrive", text: $config.password)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            
            Section(header: Text("Uygulama Hakkında")) {
                HStack {
                    Text("Sürüm")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Protokol")
                    Spacer()
                    Text("WebDAV (RFC 4918) & HTTP")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Geliştirici Mimarisi")
                    Spacer()
                    Text("Native Swift & SwiftUI")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            portString = "\(config.port)"
        }
        .alert("Sunucu Yeniden Başlatılsın mı?", isPresented: $showingRestartAlert) {
            Button("Evet, Yeniden Başlat") {
                WebDAVServer.shared.restart()
            }
            Button("Sonra", role: .cancel) {}
        } message: {
            Text("Port değişikliğinin geçerli olması için sunucunun yeniden başlatılması gerekir.")
        }
    }
}
