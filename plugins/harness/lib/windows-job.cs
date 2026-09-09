// Windows-only process ownership. Preparation policy and receipts live in Node.
// Windows 10 / Server 2016+: JOB_LIST makes assignment atomic with creation.
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class HarnessJob {
  [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a,b,c,d,e,f; }
  [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT {
    public long processTime, jobTime; public uint flags; public UIntPtr min, max;
    public uint active; public UIntPtr affinity; public uint priority, scheduling;
  }
  [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT {
    public BASIC_LIMIT basic; public IO_COUNTERS io; public UIntPtr processMemory, jobMemory, peakProcess, peakJob;
  }
  [StructLayout(LayoutKind.Sequential)] struct ACCOUNTING {
    public long user, kernel, periodUser, periodKernel;
    public uint faults, total, active, terminated;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO {
    public uint cb; public string reserved, desktop, title;
    public uint x,y,xSize,ySize,xChars,yChars,fill,flags;
    public ushort show, reservedCount; public IntPtr reservedBytes, input, output, error;
  }
  [StructLayout(LayoutKind.Sequential)] struct STARTUPINFOEX { public STARTUPINFO info; public IntPtr attributes; }
  [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr process, thread; public uint pid, tid; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenJobObject(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int type, ref EXTENDED_LIMIT data, uint size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, int type, out ACCOUNTING data, uint size, IntPtr returned);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint code);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
  [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string app, StringBuilder command, IntPtr pSecurity, IntPtr tSecurity, bool inherit, uint flags, IntPtr environment, string cwd, ref STARTUPINFOEX startup, out PROCESS_INFORMATION process);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
  [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int handle);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  static void Require(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  static string Quote(string value) {
    var output = new StringBuilder("\""); int slashes = 0;
    foreach (char ch in value) {
      if (ch == '\\') { slashes++; continue; }
      output.Append('\\', ch == '"' ? slashes * 2 + 1 : slashes); slashes = 0; output.Append(ch);
    }
    output.Append('\\', slashes * 2); return output.Append('"').ToString();
  }
  static uint Active(IntPtr job) {
    ACCOUNTING data; Require(QueryInformationJobObject(job, 1, out data, (uint)Marshal.SizeOf(typeof(ACCOUNTING)), IntPtr.Zero)); return data.active;
  }
  public static bool Exists(string name) {
    if (!System.Text.RegularExpressions.Regex.IsMatch(name, @"^Local\\HarnessPrepare-[0-9a-f-]{36}$")) throw new ArgumentException("invalid job identity");
    IntPtr job = OpenJobObject(4, false, name); // JOB_OBJECT_QUERY only
    if (job == IntPtr.Zero) { int error = Marshal.GetLastWin32Error(); if (error == 2) return false; throw new Win32Exception(error); }
    CloseHandle(job); return true;
  }
  public static int Run(string executable, string worker, string cwd, string name, string ipc) {
    IntPtr job = CreateJobObject(IntPtr.Zero, name);
    int createError = Marshal.GetLastWin32Error();
    if (job == IntPtr.Zero) throw new Win32Exception(createError);
    if (createError == 183) { CloseHandle(job); throw new InvalidOperationException("job identity collision"); }
    IntPtr list = IntPtr.Zero, jobs = IntPtr.Zero; bool initialized = false;
    PROCESS_INFORMATION child = new PROCESS_INFORMATION();
    try {
      EXTENDED_LIMIT limit = new EXTENDED_LIMIT(); limit.basic.flags = 0x2000; // KILL_ON_JOB_CLOSE; no breakaway
      Require(SetInformationJobObject(job, 9, ref limit, (uint)Marshal.SizeOf(typeof(EXTENDED_LIMIT))));
      IntPtr size = IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
      list = Marshal.AllocHGlobal(size); Require(InitializeProcThreadAttributeList(list, 1, 0, ref size)); initialized = true;
      jobs = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(jobs, job);
      Require(UpdateProcThreadAttribute(list, 0, new IntPtr(0x2000D), jobs, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero));
      STARTUPINFOEX startup = new STARTUPINFOEX(); startup.info.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFOEX)); startup.attributes = list;
      startup.info.flags = 0x100; startup.info.input = GetStdHandle(-10); startup.info.output = GetStdHandle(-11); startup.info.error = GetStdHandle(-12);
      foreach (IntPtr handle in new IntPtr[]{startup.info.input, startup.info.output, startup.info.error}) Require(SetHandleInformation(handle, 1, 1));
      Environment.SetEnvironmentVariable("HARNESS_PREPARE_JOB", name);
      Environment.SetEnvironmentVariable("HARNESS_PREPARE_IPC", ipc);
      Environment.SetEnvironmentVariable("HARNESS_PREPARE_SUPERVISOR", System.Diagnostics.Process.GetCurrentProcess().Id.ToString());
      var command = new StringBuilder(Quote(executable) + " " + Quote(worker) + " " + Quote(cwd));
      // The Job is assigned by the kernel during CreateProcess, before any
      // instruction can execute. Even supervisor death cannot orphan a child.
      Require(CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, true, 0x80004, IntPtr.Zero, cwd, ref startup, out child));
      if (ResumeThread(child.thread) == 0xffffffff) throw new Win32Exception(Marshal.GetLastWin32Error());
      for (;;) {
        uint wait = WaitForSingleObject(child.process, 10);
        if (wait == 0) break;
        if (wait != 258) throw new Win32Exception(Marshal.GetLastWin32Error());
        foreach (string request in Directory.GetFiles(ipc, "query-*")) {
          string nonce;
          using (var stream = new FileStream(request, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
          using (var reader = new StreamReader(stream)) nonce = reader.ReadToEnd().Trim();
          Guid parsed;
          if (Guid.TryParseExact(nonce, "D", out parsed) && Path.GetFileName(request) == "query-" + nonce) {
            string target = Path.Combine(ipc, "reply-" + nonce);
            File.WriteAllText(target + ".tmp", "{\"nonce\":\"" + nonce + "\",\"active\":" + Active(job) + "}", new UTF8Encoding(false));
            File.Move(target + ".tmp", target);
            File.Delete(request);
          }
        }
      }
      uint exit; Require(GetExitCodeProcess(child.process, out exit));
      Require(TerminateJobObject(job, 124)); // also reap descendants after worker crash
      DateTime deadline = DateTime.UtcNow.AddSeconds(10);
      while (Active(job) != 0) { if (DateTime.UtcNow > deadline) throw new TimeoutException("job termination not observed"); Thread.Sleep(10); }
      // PowerShell's native inherited handles are not the result channel.
      // The worker atomically publishes one response in its private IPC scope.
      string diagnostics = Path.Combine(ipc, "diagnostics.log");
      if (File.Exists(diagnostics)) Console.Error.Write(File.ReadAllText(diagnostics, Encoding.UTF8));
      if (exit == 0) {
        string result = Path.Combine(ipc, "result.json");
        if (!File.Exists(result)) throw new InvalidOperationException("PREPARE_PROTOCOL_UNREACHED: worker exited without result.json");
        Console.Out.Write(File.ReadAllText(result, Encoding.UTF8));
      }
      return unchecked((int)exit);
    } finally {
      // Closing the only owning handle is the final crash/failure backstop.
      CloseHandle(job);
      if (child.thread != IntPtr.Zero) CloseHandle(child.thread);
      if (child.process != IntPtr.Zero) CloseHandle(child.process);
      if (initialized) DeleteProcThreadAttributeList(list);
      if (list != IntPtr.Zero) Marshal.FreeHGlobal(list);
      if (jobs != IntPtr.Zero) Marshal.FreeHGlobal(jobs);
      try { Directory.Delete(ipc, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
  }
}
