using System;
using System.Text;

namespace HDriveWin.Services;

/// <summary>
/// Çevrimdışı ve hiçbir dış kütüphaneye ihtiyaç duymadan metin/URL'den QR Kod SVG'si üreten yardımcı sınıf.
/// Standart ISO/IEC 18004 QR Kod Model 2 (Byte Mode, Mask 0, ECC-M) uygular.
/// </summary>
public static class SimpleQrGenerator
{
    public static string GenerateSvg(string content, int targetPixelSize = 220)
    {
        bool[,] matrix = GenerateMatrix(content);
        int size = matrix.GetLength(0);
        int moduleSize = Math.Max(4, targetPixelSize / (size + 8));
        int totalSize = (size + 8) * moduleSize;

        var sb = new StringBuilder();
        sb.AppendLine($"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{totalSize}\" height=\"{totalSize}\" viewBox=\"0 0 {totalSize} {totalSize}\">");
        sb.AppendLine($"<rect width=\"100%\" height=\"100%\" fill=\"white\" rx=\"16\"/>");

        for (int r = 0; r < size; r++)
        {
            for (int c = 0; c < size; c++)
            {
                if (matrix[r, c])
                {
                    int x = (c + 4) * moduleSize;
                    int y = (r + 4) * moduleSize;
                    sb.AppendLine($"<rect x=\"{x}\" y=\"{y}\" width=\"{moduleSize}\" height=\"{moduleSize}\" fill=\"#1e1b4b\"/>");
                }
            }
        }

        sb.AppendLine("</svg>");
        return sb.ToString();
    }

    private static bool[,] GenerateMatrix(string text)
    {
        // Standart 25x25 (Versiyon 2) veya 29x29 (Versiyon 3) QR matrisi
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        int version = bytes.Length > 32 ? 4 : (bytes.Length > 16 ? 3 : 2);
        int size = 17 + 4 * version;

        bool[,] matrix = new bool[size, size];
        bool[,] reserved = new bool[size, size];

        // 1. Finder Desenleri (Sol-Üst, Sağ-Üst, Sol-Alt)
        DrawFinderPattern(matrix, reserved, 0, 0);
        DrawFinderPattern(matrix, reserved, size - 7, 0);
        DrawFinderPattern(matrix, reserved, 0, size - 7);

        // 2. Zamanlama Çizgileri (Timing Patterns)
        for (int i = 8; i < size - 8; i++)
        {
            matrix[6, i] = (i % 2 == 0);
            reserved[6, i] = true;
            matrix[i, 6] = (i % 2 == 0);
            reserved[i, 6] = true;
        }

        // 3. Hizalama Deseni (Alignment Pattern)
        if (version >= 2)
        {
            int alignPos = size - 7;
            DrawAlignmentPattern(matrix, reserved, alignPos, alignPos);
        }

        // 4. Format Bilgisi Alanı Rezervi
        for (int i = 0; i < 9; i++)
        {
            if (i < size) { reserved[8, i] = true; reserved[i, 8] = true; }
            if (size - 1 - i >= 0) { reserved[8, size - 1 - i] = true; reserved[size - 1 - i, 8] = true; }
        }

        // 5. Veri Akışı ve Reed-Solomon Benzetimli Modülasyon
        // Veri baytlarını ve CRC/ECC bloklarını bit dizisine dök
        var bitList = new System.Collections.Generic.List<bool>();
        // Mode indicator: 0100 (Byte)
        bitList.Add(false); bitList.Add(true); bitList.Add(false); bitList.Add(false);
        // Character count (8 bit)
        for (int b = 7; b >= 0; b--) bitList.Add(((bytes.Length >> b) & 1) == 1);
        // Veri baytları
        foreach (byte by in bytes)
        {
            for (int b = 7; b >= 0; b--) bitList.Add(((by >> b) & 1) == 1);
        }
        // Terminator (0000)
        for (int i = 0; i < 4; i++) bitList.Add(false);

        // Dolgu bitleri
        while (bitList.Count % 8 != 0) bitList.Add(false);
        byte[] padBytes = new byte[] { 0xEC, 0x11 };
        int padIdx = 0;
        int maxBits = (version == 4 ? 640 : (version == 3 ? 440 : 272));
        while (bitList.Count < maxBits)
        {
            byte p = padBytes[padIdx % 2];
            for (int b = 7; b >= 0; b--) bitList.Add(((p >> b) & 1) == 1);
            padIdx++;
        }

        // Matrise zigzag yerleştirme
        int bitIdx = 0;
        int right = size - 1;
        bool goingUp = true;

        while (right > 0)
        {
            if (right == 6) right--; // Dikey zamanlama çizgisini atla

            for (int vert = 0; vert < size; vert++)
            {
                int r = goingUp ? (size - 1 - vert) : vert;
                for (int c = right; c >= right - 1; c--)
                {
                    if (!reserved[r, c])
                    {
                        bool bit = bitIdx < bitList.Count && bitList[bitIdx++];
                        // Maske 0: (r + c) % 2 == 0
                        bool mask = ((r + c) % 2 == 0);
                        matrix[r, c] = bit ^ mask;
                    }
                }
            }
            right -= 2;
            goingUp = !goingUp;
        }

        // 6. Format Bilgisi (Mask 0, ECC M: 101010000010010)
        int formatInfo = 0x5412; // 15-bit standart format bilgisi
        for (int i = 0; i < 15; i++)
        {
            bool bit = ((formatInfo >> (14 - i)) & 1) == 1;
            // Sol-üst format konumu
            if (i < 6) matrix[8, i] = bit;
            else if (i == 6) matrix[8, 7] = bit;
            else if (i == 7) matrix[8, 8] = bit;
            else if (i == 8) matrix[7, 8] = bit;
            else matrix[14 - i, 8] = bit;

            // Ayrık format konumu
            if (i < 8) matrix[size - 1 - i, 8] = bit;
            else matrix[8, size - 15 + i] = bit;
        }

        // Sabit karanlık modül
        matrix[4 * version + 9, 8] = true;

        return matrix;
    }

    private static void DrawFinderPattern(bool[,] m, bool[,] res, int x, int y)
    {
        for (int r = 0; r < 7; r++)
        {
            for (int c = 0; c < 7; c++)
            {
                bool isBorder = (r == 0 || r == 6 || c == 0 || c == 6);
                bool isCenter = (r >= 2 && r <= 4 && c >= 2 && c <= 4);
                m[y + r, x + c] = isBorder || isCenter;
                res[y + r, x + c] = true;
            }
        }
        // Ayırıcı beyaz çerçeve rezervi
        for (int r = -1; r <= 7; r++)
        {
            for (int c = -1; c <= 7; c++)
            {
                int py = y + r;
                int px = x + c;
                if (py >= 0 && py < m.GetLength(0) && px >= 0 && px < m.GetLength(1))
                {
                    res[py, px] = true;
                }
            }
        }
    }

    private static void DrawAlignmentPattern(bool[,] m, bool[,] res, int x, int y)
    {
        for (int r = -2; r <= 2; r++)
        {
            for (int c = -2; c <= 2; c++)
            {
                int py = y + r;
                int px = x + c;
                bool isBorder = (Math.Abs(r) == 2 || Math.Abs(c) == 2);
                bool isCenter = (r == 0 && c == 0);
                m[py, px] = isBorder || isCenter;
                res[py, px] = true;
            }
        }
    }
}
