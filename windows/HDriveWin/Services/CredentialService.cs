using System;
using Windows.Security.Credentials;

namespace HDriveWin.Services;

public static class CredentialService
{
    private const string ResourceName = "HDrive_Cloudreve";

    public static void SavePassword(string username, string password)
    {
        if (string.IsNullOrEmpty(username)) return;
        try
        {
            var vault = new PasswordVault();
            try
            {
                var existing = vault.Retrieve(ResourceName, username);
                if (existing != null)
                {
                    vault.Remove(existing);
                }
            }
            catch { }

            if (!string.IsNullOrEmpty(password))
            {
                vault.Add(new PasswordCredential(ResourceName, username, password));
            }
        }
        catch { }
    }

    public static string? GetPassword(string username)
    {
        if (string.IsNullOrEmpty(username)) return null;
        try
        {
            var vault = new PasswordVault();
            var cred = vault.Retrieve(ResourceName, username);
            cred?.RetrievePassword();
            return cred?.Password;
        }
        catch
        {
            return null;
        }
    }

    public static void DeletePassword(string username)
    {
        if (string.IsNullOrEmpty(username)) return;
        try
        {
            var vault = new PasswordVault();
            var cred = vault.Retrieve(ResourceName, username);
            if (cred != null)
            {
                vault.Remove(cred);
            }
        }
        catch { }
    }
}
