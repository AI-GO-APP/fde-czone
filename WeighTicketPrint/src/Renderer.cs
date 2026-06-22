// WeighTicketPrint - 渲染層 (Windows GDI 系統列印)
//
// 做法符合決策: 走 System.Drawing.Printing, 自己畫版面, 印到 "EPSON LQ-690CII" 驅動,
// 中文交給 Windows 字型, 由驅動轉點陣。座標以實體公釐(mm)定位。
// 不引用 FastReport, 不手刻 ESC/P2。
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Printing;
using System.Globalization;
using System.IO;
using System.Text;

namespace WeighTicket
{
    public class TicketRenderer : PrintDocument
    {
        private readonly ReportLayout _layout;
        private readonly IDictionary<string, object> _data;
        private readonly CultureInfo _culture;
        private readonly string _cjkFont;

        // 微調位移 (mm): 對齊實體預印格用。正值=往右/往下, 負值=往左/往上。
        // 預覽與列印都會套用 (所以預覽 = 實際會印出的結果)。預設 0。
        public double OffsetXmm = 0;
        public double OffsetYmm = 0;

        // 列印時補償印表機硬體邊界。
        // 原因: OriginAtMargins=false 時 GDI 原點在「可列印區」左上角 (已內縮硬體邊界),
        //       但 .frx 座標以「實體紙角」為 0,0。不補償 -> 內容整體往下/往右偏 (= 跑掉)。
        //       FastReport 會自動補, 我們在列印路徑也補回, 對齊舊系統。
        public bool CompensateHardMargin = true;

        // _cjkFont: 中文要用有中文字庫的字型 (預設新細明體 PMingLiU)。
        //           覆蓋 .frx 原本的 Times New Roman 字族, 但沿用原本的點數(pt)大小。
        public TicketRenderer(ReportLayout layout, IDictionary<string, object> data, string cjkFont)
        {
            _layout = layout;
            _data = data;
            _cjkFont = string.IsNullOrEmpty(cjkFont) ? "新細明體" : cjkFont;
            _culture = new CultureInfo("zh-TW");
            this.OriginAtMargins = false; // 以紙張左上角(0,0)為原點, 與 .frx 邊界=0 一致
        }

        // 把整個版面畫到任一 Graphics (列印頁 / PDF / 點陣圖預覽 共用同一條繪製路徑)。
        public void DrawAll(Graphics g)
        {
            g.PageUnit = GraphicsUnit.Millimeter;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

            // 套用微調位移 (與列印路徑的硬體邊界補償會疊加)。
            g.TranslateTransform((float)OffsetXmm, (float)OffsetYmm);

            StringFormat sf = StringFormat.GenericTypographic;
            sf.FormatFlags = sf.FormatFlags | StringFormatFlags.NoClip;

            foreach (FieldDef f in _layout.Fields)
            {
                string text = Formatter.Resolve(f, _data, _culture);
                if (string.IsNullOrEmpty(text)) continue;

                using (Font font = new Font(_cjkFont, (float)f.FontSizePt, FontStyle.Regular, GraphicsUnit.Point))
                {
                    float x = (float)Units.PxToMm(f.LeftPx);
                    float y = (float)Units.PxToMm(f.TopPx);
                    g.DrawString(text, font, Brushes.Black, x, y, sf);
                }
            }
        }

        protected override void OnPrintPage(PrintPageEventArgs e)
        {
            Graphics g = e.Graphics;
            g.PageUnit = GraphicsUnit.Millimeter;

            // 補償硬體邊界: 讓 (0,0) 對回實體紙角, 內容才不會整體往下/往右偏。
            // HardMarginX/Y 單位為 1/100 吋, 轉 mm 後反向平移。
            if (CompensateHardMargin)
            {
                float hmx = (float)(e.PageSettings.HardMarginX * 0.254);
                float hmy = (float)(e.PageSettings.HardMarginY * 0.254);
                g.TranslateTransform(-hmx, -hmy);
            }

            DrawAll(g); // DrawAll 內再疊加 OffsetXmm/OffsetYmm
            e.HasMorePages = false;
        }

        // 設定自訂紙張 242mm x 178mm (PaperSize 單位為 1/100 吋)。
        public void ApplyPaper()
        {
            int wHi = (int)Math.Round(_layout.PaperWidthMm / 25.4 * 100.0);   // 242mm -> 953
            int hHi = (int)Math.Round(_layout.PaperHeightMm / 25.4 * 100.0);  // 178mm -> 701
            PaperSize ps = new PaperSize("Custom_WeighTicket", wHi, hHi);
            this.DefaultPageSettings.PaperSize = ps;
            this.DefaultPageSettings.Margins = new Margins(0, 0, 0, 0);
            this.DefaultPageSettings.Landscape = false; // 寬(242) > 高(178), 直接當寬紙
        }

        // 產生「尺寸正確」的 PDF 預覽: 把精確 242x178mm 的點陣圖嵌進一個 MediaBox 正確的最小 PDF。
        // 用途: 螢幕/列印前的版面對齊確認 (不需系統權限, 不依賴 Microsoft Print to PDF 的紙張支援)。
        // 註: 這是「影像版」PDF, 僅供預覽; 真正出紙仍走 Print() 的向量文字路徑。
        public void SaveExactSizePdf(string path, int dpi)
        {
            int wpx = (int)Math.Round(_layout.PaperWidthMm / 25.4 * dpi);
            int hpx = (int)Math.Round(_layout.PaperHeightMm / 25.4 * dpi);

            byte[] jpeg;
            using (Bitmap bmp = new Bitmap(wpx, hpx))
            {
                bmp.SetResolution(dpi, dpi);
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.White);
                    DrawAll(g);
                }
                using (MemoryStream ms = new MemoryStream())
                {
                    bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Jpeg);
                    jpeg = ms.ToArray();
                }
            }

            double wpt = _layout.PaperWidthMm / 25.4 * 72.0;
            double hpt = _layout.PaperHeightMm / 25.4 * 72.0;
            WriteImagePdf(path, jpeg, wpx, hpx, wpt, hpt);
        }

        // 寫出含單張 JPEG 影像的最小 PDF (自行計算 xref 位移)。
        private static void WriteImagePdf(string path, byte[] jpeg, int wpx, int hpx, double wpt, double hpt)
        {
            CultureInfo ci = CultureInfo.InvariantCulture;
            List<long> offsets = new List<long>();

            using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write))
            {
                WriteAscii(fs, "%PDF-1.4\n");

                offsets.Add(fs.Position);
                WriteAscii(fs, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");

                offsets.Add(fs.Position);
                WriteAscii(fs, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");

                offsets.Add(fs.Position);
                WriteAscii(fs, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "
                    + wpt.ToString("0.###", ci) + " " + hpt.ToString("0.###", ci)
                    + "] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>\nendobj\n");

                offsets.Add(fs.Position);
                WriteAscii(fs, "4 0 obj\n<< /Type /XObject /Subtype /Image /Width " + wpx
                    + " /Height " + hpx + " /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length "
                    + jpeg.Length + " >>\nstream\n");
                fs.Write(jpeg, 0, jpeg.Length);
                WriteAscii(fs, "\nendstream\nendobj\n");

                string content = "q " + wpt.ToString("0.###", ci) + " 0 0 " + hpt.ToString("0.###", ci)
                    + " 0 0 cm /Im0 Do Q\n";
                byte[] contentBytes = Encoding.ASCII.GetBytes(content);
                offsets.Add(fs.Position);
                WriteAscii(fs, "5 0 obj\n<< /Length " + contentBytes.Length + " >>\nstream\n");
                fs.Write(contentBytes, 0, contentBytes.Length);
                WriteAscii(fs, "endstream\nendobj\n");

                long xref = fs.Position;
                WriteAscii(fs, "xref\n0 6\n0000000000 65535 f \n");
                foreach (long off in offsets)
                    WriteAscii(fs, off.ToString("D10") + " 00000 n \n");
                WriteAscii(fs, "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n" + xref + "\n%%EOF\n");
            }
        }

        private static void WriteAscii(Stream s, string text)
        {
            byte[] b = Encoding.ASCII.GetBytes(text);
            s.Write(b, 0, b.Length);
        }
    }
}
