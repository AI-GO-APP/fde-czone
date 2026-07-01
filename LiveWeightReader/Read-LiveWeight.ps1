<#
.SYNOPSIS
  地磅即時重量讀取 agent — 讀取 ScalesManager 畫面上的即時磅重。

.DESCRIPTION
  以「唯讀」方式(Win32 WM_GETTEXT)讀取 ScalesManager 顯示的即時重量。
  - 自動定位「會隨磅秤跳動的數字格」(不寫死控制項 handle);
    ScalesManager 重開後 handle 會變,程式會自動重新定位。
  - 只讀不寫,不送任何輸入給 ScalesManager,不影響地磅運作。

  目前階段:只讀取並寫入 log(這是整個 aigo 串接的地基/驗證)。
  之後會在此基礎上加上「推送即時重量到 aigo」。

  由排程任務於「登入時」自動啟動(見 Install-WeightReaderTask.ps1),
  以對付本機偶發斷電/重開機——開機登入後自動把 reader 叫回來。

.NOTES
  log 寫到 LiveWeightReader\out\weight-reader.log(out 已在 .gitignore,不入版控)。
#>

$ErrorActionPreference = 'Stop'

# --- log 路徑(LiveWeightReader/out 已 gitignore) ---
$logDir = 'C:\Users\user\Desktop\fde-czone\LiveWeightReader\out'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'weight-reader.log'

# --- 防止重複執行(同一登入 session 只跑一份) ---
$created = $false
$mtx = New-Object System.Threading.Mutex($true, 'Local\ScalesWeightReader', [ref]$created)
if (-not $created) { return }

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.IO;

public class WeightReader {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeoutW(IntPtr h, uint msg, IntPtr wp, StringBuilder lp, uint flags, uint timeout, out IntPtr res);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  delegate bool EnumProc(IntPtr h, IntPtr l);

  static List<IntPtr> _found = new List<IntPtr>();
  static List<uint> _pidFilter = new List<uint>();
  static EnumProc _topCb = TopCb;
  static EnumProc _childCb = ChildCb;

  static bool ChildCb(IntPtr h, IntPtr l){ _found.Add(h); return true; }
  static bool TopCb(IntPtr h, IntPtr l){
    uint pid; GetWindowThreadProcessId(h, out pid);
    if(_pidFilter.Contains(pid)){ _found.Add(h); EnumChildWindows(h, _childCb, IntPtr.Zero); }
    return true;
  }
  static string GetText(IntPtr h){
    StringBuilder sb = new StringBuilder(256); IntPtr r;
    SendMessageTimeoutW(h, 0x000D, (IntPtr)256, sb, 0x0002, 200, out r);
    return sb.ToString();
  }
  static string GetCls(IntPtr h){
    StringBuilder sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString();
  }

  static void WriteCurrent(string path, int weight, string state){
    string at = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:sszzz");
    string json = "{\"weight\": " + weight + ", \"at\": \"" + at + "\", \"state\": \"" + state + "\"}";
    try { File.WriteAllText(path, json); } catch {}
  }

  // durationSec: 執行上限秒數(排程每次登入會重啟,故給很長)
  // pollMs: 取樣間隔; log: 記錄檔路徑
  public static void Run(int durationSec, int pollMs, string log, string jsonPath){
    DateTime end = DateTime.Now.AddSeconds(durationSec);
    File.AppendAllText(log, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] reader started (poll={1}ms)\r\n", DateTime.Now, pollMs));
    Dictionary<IntPtr,string> last = new Dictionary<IntPtr,string>();
    Dictionary<IntPtr,int> maxv = new Dictionary<IntPtr,int>();
    Dictionary<IntPtr,DateTime> lastChg = new Dictionary<IntPtr,DateTime>();
    IntPtr active = IntPtr.Zero;
    string activeVal = null;
    int lastPid = -1;
    DateTime hb = DateTime.Now;
    int curW = 0; string curState = "idle"; DateTime lastWrite = DateTime.MinValue;
    WriteCurrent(jsonPath, curW, curState);
    while(DateTime.Now < end){
      List<uint> pids = new List<uint>();
      int curPid = 0;
      try {
        Process[] ps = Process.GetProcessesByName("ScalesManager");
        foreach(Process p in ps){ pids.Add((uint)p.Id); curPid = p.Id; p.Dispose(); }
      } catch {}
      if(curPid != lastPid){
        File.AppendAllText(log, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] ScalesManager PID={1} (re-scan windows)\r\n", DateTime.Now, curPid));
        lastPid = curPid;
        last.Clear(); maxv.Clear(); lastChg.Clear(); active=IntPtr.Zero; activeVal=null;
      }
      if(pids.Count==0){ System.Threading.Thread.Sleep(pollMs); continue; }
      _pidFilter = pids;
      _found.Clear();
      EnumWindows(_topCb, IntPtr.Zero);
      foreach(IntPtr h in _found){
        string cls = GetCls(h);
        if(cls.IndexOf("STATIC", StringComparison.OrdinalIgnoreCase) < 0) continue;
        string txt = GetText(h).Trim();
        int v;
        if(txt.Length==0 || txt.Length>6 || !int.TryParse(txt, out v)) continue;
        int mx; if(!maxv.TryGetValue(h, out mx)) mx=0;
        if(v>mx){ mx=v; } maxv[h]=mx;
        string prev;
        if(last.TryGetValue(h, out prev)){
          if(prev != txt){ last[h]=txt; lastChg[h]=DateTime.Now; }
        } else {
          last[h]=txt;
        }
      }
      // 選出即時重量格:曾達 >=300kg(排除時鐘/小計數器)、且最近有變動者
      IntPtr best=IntPtr.Zero; DateTime bestT=DateTime.MinValue;
      foreach(KeyValuePair<IntPtr,int> kv in maxv){
        if(kv.Value<300) continue;
        DateTime t; if(!lastChg.TryGetValue(kv.Key,out t)) continue;
        if(t>bestT){ bestT=t; best=kv.Key; }
      }
      if(best!=IntPtr.Zero){
        if(best!=active){
          active=best; activeVal=null;
          File.AppendAllText(log, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] >>> LOCKED weight control hwnd={1} (max={2})\r\n", DateTime.Now, (long)best, maxv[best]));
        }
        string cv; last.TryGetValue(best, out cv);
        if(cv!=activeVal){ activeVal=cv; File.AppendAllText(log, string.Format("[{0:HH:mm:ss.fff}] weight: {1}\r\n", DateTime.Now, cv));
          int pw; if(int.TryParse(cv, out pw)){ curW = pw; curState = (curW==0) ? "idle" : "weighing"; WriteCurrent(jsonPath, curW, curState); lastWrite = DateTime.Now; }
        }
      }
      if((DateTime.Now-hb).TotalMinutes>=30){
        hb=DateTime.Now;
        int numStatics=last.Count;
        if(active!=IntPtr.Zero){
          string av; last.TryGetValue(active,out av);
          File.AppendAllText(log, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] heartbeat alive, numeric statics={1}, locked hwnd={2} val={3}\r\n", DateTime.Now, numStatics, (long)active, av));
        } else {
          File.AppendAllText(log, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] heartbeat alive, numeric statics={1}, no weighing yet\r\n", DateTime.Now, numStatics));
        }
      }
      if((DateTime.Now - lastWrite).TotalSeconds >= 5){ WriteCurrent(jsonPath, curW, curState); lastWrite = DateTime.Now; }
      System.Threading.Thread.Sleep(pollMs);
    }
    File.AppendAllText(log, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] reader finished\r\n", DateTime.Now));
    GC.KeepAlive(_topCb); GC.KeepAlive(_childCb);
  }
}
'@

# 常駐執行(每次登入由排程重啟;此處給很長的執行上限 ~10 年)
$jsonPath = Join-Path $logDir 'current-weight.json'
[WeightReader]::Run(315360000, 300, $log, $jsonPath)
