using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Windows.Security.Credentials;

namespace HDriveWin.Services;

public static class CredentialService
{
    private const string ResourceName = "HDrive_Vault";
    private const string LegacyResourceName = "HDrive_Cloudreve";

    public static void SavePassword(string key, string password)
    {
        if (string.IsNullOrEmpty(key)) return;

        // 1. Güvenli Yerel Şifrelenmiş DPAPI (Windows Kullanıcı Seviyesinde Şifreleme)
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var vaultDir = Path.Combine(appData, "HDrive", ".vault");
            Directory.CreateDirectory(vaultDir);

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

        // 2. İsteğe bağlı Windows PasswordVault (hata verirse yutulur)
        try
        {
            var vault = new PasswordVault();
            try
            {
                var existing = vault.Retrieve(ResourceName, key);
                if (existing != null) vault.Remove(existing);
            }
            catch { }

            if (!string.IsNullOrEmpty(password))
            {
                vault.Add(new PasswordCredential(ResourceName, key, password));
            }
        }
        catch { }
    }

    public static string? GetPassword(string key)
    {
        if (string.IsNullOrEmpty(key)) return null;

        // 1. Önce güvenilir DPAPI'den oku
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

        // 2. DPAPI'de yoksa eski PasswordVault'tan dene (geriye dönük uyumluluk)
        try
        {
            var vault = new PasswordVault();
            try
            {
                var cred = vault.Retrieve(ResourceName, key);
                cred?.RetrievePassword();
                if (!string.IsNullOrEmpty(cred?.Password)) return cred.Password;
            }
            catch { }

            try
            {
                var credLegacy = vault.Retrieve(LegacyResourceName, key);
                credLegacy?.RetrievePassword();
                if (!string.IsNullOrEmpty(credLegacy?.Password)) return credLegacy.Password;
            }
            catch { }
        }
        catch { }

        return null;
    }

    public static void DeletePassword(string key)
    {
        if (string.IsNullOrEmpty(key)) return;

        // DPAPI sil
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var vaultDir = Path.Combine(appData, "HDrive", ".vault");
            var keyHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)));
            var filePath = Path.Combine(vaultDir, $"{keyHash}.sec");
            if (File.Exists(filePath)) File.Delete(filePath);
        }
        catch { }

        // PasswordVault sil
        try
        {
            var vault = new PasswordVault();
            try
            {
                var cred = vault.Retrieve(ResourceName, key);
                if (cred != null) vault.Remove(cred);
            }
            catch { }

            try
            {
                var credLegacy = vault.Retrieve(LegacyResourceName, key);
                if (credLegacy != null) vault.Remove(credLegacy);
            }
            catch { }
        }
        catch { }
    }
}
