// WeighTicketPrint - 純邏輯層 (座標換算 / 資料格式化 / .frx XML 解析 / 三聯水平平移)
//
// 重要: 這個檔案「不引用」FastReport 任何組件, 也不繪圖。
//   - .frx 只當作「版面座標藍圖」用 System.Xml 解析, 絕不載入 FastReport 執行。
//   - 可被 PowerShell Add-Type 編譯 (C# 5 相容語法)。
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Xml;

namespace WeighTicket
{
    // 單位換算: FastReport 的 TextObject 座標一律是 96dpi 像素。
    public static class Units
    {
        public const double Dpi = 96.0;
        public const double MmPerInch = 25.4;

        // 像素 -> 公釐
        public static double PxToMm(double px)
        {
            return px / Dpi * MmPerInch;
        }

        // 公釐 -> 像素 (反向, 測試用)
        public static double MmToPx(double mm)
        {
            return mm / MmPerInch * Dpi;
        }
    }

    public enum FmtKind { None, Date, Time }

    // 一個 TextObject (一格文字) 的版面定義, 座標單位為像素 (px)。
    public class FieldDef
    {
        public string Name;
        public double LeftPx;
        public double TopPx;
        public double WidthPx;
        public double HeightPx;
        public string Text;          // 原始字串, 例如 "[Query.SR_GrossWeight] KG" 或 "薪榮環保股份有限公司"
        public FmtKind FormatKind;   // Date / Time / None
        public string FormatString;  // 例如 "d" 或 "HH:mm"
        public string FontFamily;    // 原始字型 (僅供參考, 中文實際改用 CJK 字型)
        public double FontSizePt;

        public double LeftMm { get { return Units.PxToMm(LeftPx); } }
        public double TopMm { get { return Units.PxToMm(TopPx); } }
        public double WidthMm { get { return Units.PxToMm(WidthPx); } }

        public FieldDef Clone()
        {
            FieldDef c = new FieldDef();
            c.Name = Name; c.LeftPx = LeftPx; c.TopPx = TopPx;
            c.WidthPx = WidthPx; c.HeightPx = HeightPx; c.Text = Text;
            c.FormatKind = FormatKind; c.FormatString = FormatString;
            c.FontFamily = FontFamily; c.FontSizePt = FontSizePt;
            return c;
        }
    }

    public class ReportLayout
    {
        public double PaperWidthMm;   // .frx ReportPage PaperWidth (mm)
        public double PaperHeightMm;  // .frx ReportPage PaperHeight (mm)
        public string PrinterName;    // .frx PrintSettings.Printer
        public List<FieldDef> Fields = new List<FieldDef>();
    }

    // 資料格式化: 把 [Query.SR_xxx] 代換成實際值, 並套用日期(d)/時間(HH:mm)格式。
    // 注意: 重量的 " KG" 是樣板裡的字面字串, 不在這裡加。
    public static class Formatter
    {
        private static readonly Regex TokenRx = new Regex(@"\[Query\.(SR_\w+)\]");

        public static string Resolve(FieldDef f, IDictionary<string, object> data, CultureInfo culture)
        {
            if (f == null || string.IsNullOrEmpty(f.Text)) return "";
            FieldDef field = f;
            CultureInfo c = culture;
            IDictionary<string, object> d = data;

            return TokenRx.Replace(field.Text, delegate(Match m)
            {
                string key = m.Groups[1].Value;
                object val = null;
                if (d != null) d.TryGetValue(key, out val);
                if (val == null) return "";

                if (field.FormatKind == FmtKind.Date || field.FormatKind == FmtKind.Time)
                {
                    DateTime dt;
                    if (TryGetDateTime(val, c, out dt))
                    {
                        string fmt = field.FormatString;
                        if (string.IsNullOrEmpty(fmt))
                            fmt = (field.FormatKind == FmtKind.Date) ? "d" : "HH:mm";
                        return dt.ToString(fmt, c);
                    }
                }

                return Convert.ToString(val, c);
            });
        }

        // 取得 DateTime: 原生 boxed DateTime 走快路; 其他 (字串 / PowerShell PSObject 包裝)
        // 以字串往返解析, 避免上游資料型別差異造成格式失效。
        private static bool TryGetDateTime(object val, CultureInfo c, out DateTime dt)
        {
            dt = DateTime.MinValue;
            if (val == null) return false;
            if (val is DateTime) { dt = (DateTime)val; return true; }
            return DateTime.TryParse(Convert.ToString(val, c), c, DateTimeStyles.None, out dt);
        }
    }

    // .frx 解析器 (純 XML, 不碰 FastReport)。
    public static class FrxParser
    {
        public static ReportLayout Parse(string frxPath)
        {
            XmlDocument doc = new XmlDocument();
            doc.Load(frxPath);

            ReportLayout layout = new ReportLayout();

            XmlElement root = doc.DocumentElement; // <Report ...>
            if (root != null)
                layout.PrinterName = root.GetAttribute("PrintSettings.Printer");

            XmlNodeList pages = doc.GetElementsByTagName("ReportPage");
            if (pages.Count > 0)
            {
                XmlElement page = (XmlElement)pages[0];
                layout.PaperWidthMm = ParseD(page.GetAttribute("PaperWidth"), 0);
                layout.PaperHeightMm = ParseD(page.GetAttribute("PaperHeight"), 0);
            }

            XmlNodeList texts = doc.GetElementsByTagName("TextObject");
            foreach (XmlNode n in texts)
            {
                XmlElement el = n as XmlElement;
                if (el == null) continue;

                FieldDef f = new FieldDef();
                f.Name = el.GetAttribute("Name");
                f.LeftPx = ParseD(el.GetAttribute("Left"), 0);
                f.TopPx = ParseD(el.GetAttribute("Top"), 0);
                f.WidthPx = ParseD(el.GetAttribute("Width"), 0);
                f.HeightPx = ParseD(el.GetAttribute("Height"), 0);
                f.Text = el.GetAttribute("Text");

                string fmt = el.GetAttribute("Format");
                if (string.Equals(fmt, "Date", StringComparison.OrdinalIgnoreCase)) f.FormatKind = FmtKind.Date;
                else if (string.Equals(fmt, "Time", StringComparison.OrdinalIgnoreCase)) f.FormatKind = FmtKind.Time;
                else f.FormatKind = FmtKind.None;
                f.FormatString = el.GetAttribute("Format.Format");

                ParseFont(el.GetAttribute("Font"), f);

                layout.Fields.Add(f);
            }

            return layout;
        }

        private static readonly Regex FontSizeRx = new Regex(@"([0-9]+(\.[0-9]+)?)\s*pt");

        private static void ParseFont(string font, FieldDef f)
        {
            f.FontFamily = "Times New Roman";
            f.FontSizePt = 12.0;
            if (string.IsNullOrEmpty(font)) return;

            string[] parts = font.Split(',');
            if (parts.Length > 0) f.FontFamily = parts[0].Trim();

            Match m = FontSizeRx.Match(font);
            if (m.Success)
                f.FontSizePt = ParseD(m.Groups[1].Value, 12.0);
        }

        private static double ParseD(string s, double dflt)
        {
            if (string.IsNullOrEmpty(s)) return dflt;
            double v;
            if (double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out v)) return v;
            return dflt;
        }
    }

    // 三聯水平平移: 把一格往右平移 dxPx, 回傳新的複本 (不改原物件)。
    public static class PanelOps
    {
        public static FieldDef ShiftedCopy(FieldDef f, double dxPx)
        {
            FieldDef c = f.Clone();
            c.LeftPx = f.LeftPx + dxPx;
            return c;
        }

        // 找出某文字內容(例如公司抬頭)在版面上出現的所有 Left(px), 由左到右排序。
        // 用來量測「三聯」的水平基準與間距, 供測試與校準參考。
        public static List<double> HeaderLefts(ReportLayout layout, string literalText)
        {
            List<double> lefts = new List<double>();
            foreach (FieldDef f in layout.Fields)
                if (f.Text == literalText) lefts.Add(f.LeftPx);
            lefts.Sort();
            return lefts;
        }
    }
}
