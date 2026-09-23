using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Windows.Security.Credentials;

namespace HDriveWin.Services;

public static class CredentialService
{
    private const string ResourceName = "HDrive_Vault";

    public static void SavePassword(string key, string password)
    {
        if (string.IsNullOrEmpty(key)) return;

        // 1. Windows Credential Vault
        try
        {
            var vault = new PasswordVault();
            try
            {
                var existing = vault.Retrieve(ResourceName, key);
                if (existing != null)
                {
                    vault.Remove(existing);
                }
            }
            catch { }

            if (!string.IsNullOrEmpty(password))
            {
                vault.Add(new PasswordCredential(ResourceName, key, password));
            }
        }
        catch { }

        // 2. Güvenli Yerel Şifrelenmiş DPAPI Yedeklemesi (Windows User Korumalı)
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var vaultDir = Path.Combine(appData, "HDrive", ".vault");
            Directory.CreateDirectory(vaultDir);

            // Güvenli anahtar dosya adı (hex)
            var keyHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)));
            var filePath = Path.Combine(vaultDir, $"{keyHash}.sec");

            if (string.IsNullOrEmpty(password))
            {
                if (File.Exists(filePath)) File.Delete(filePath);
            }
            else
            {
                var plainBytes = Encoding.UTF8.GetBytes(password);
                var encrypted = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
                File.WriteAllBytes(filePath, encrypted);
            }
        }
        catch { }
    }

    public static string? GetPassword(string key)
    {
        if (string.IsNullOrEmpty(key)) return null;

        // 1. Önce Windows Credential Vault dene
        try
        {
            var vault = new PasswordVault();
            var cred = vault.Retrieve(ResourceName, key);
            cred?.RetrievePassword();
            if (!string.IsNullOrEmpty(cred?.Password))
            {
                return cred.Password;
            }
        }
        catch { }

        // 2. Windows Credential Vault bulunamazsa DPAPI şifrelenmiş dosyasından çek
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var vaultDir = Path.Combine(appData, "HDrive", ".vault");
            var keyHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)));
            var filePath = Path.Combine(vaultDir, $"{keyHash}.sec");

            if (File.Exists(filePath))
            {
                var encrypted = File.ReadAllBytes(filePath);
                var plainBytes = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(plainBytes);
            }
        }
        catch { }

        return null;
    }

    public static void DeletePassword(string key)
    {
        if (string.IsNullOrEmpty(key)) return;

        try
        {
            var vault = new PasswordVault();
            var cred = vault.Retrieve(ResourceName, key);
            if (cred != null)
            {
                vault.Remove(cred);
            }
        }
        catch { }

        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var vaultDir = Path.Combine(appData, "HDrive", ".vault");
            var keyHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)));
            var filePath = Path.Combine(vaultDir, $"{keyHash}.sec");
            if (File.Exists(filePath)) File.Delete(filePath);
        }
        catch { }
    }
}
