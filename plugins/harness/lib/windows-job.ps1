param([Parameter(Mandatory=$true)][ValidateSet('supervise','exists')][string]$Mode,
      [Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$outputWriter = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8)
$outputWriter.AutoFlush = $true
[Console]::SetOut($outputWriter)
$errorWriter = New-Object System.IO.StreamWriter([Console]::OpenStandardError(), $utf8)
$errorWriter.AutoFlush = $true
[Console]::SetError($errorWriter)
try {
  Add-Type -Path (Join-Path $PSScriptRoot 'windows-job.cs')
  if ($Mode -eq 'exists') {
    if ([HarnessJob]::Exists($Request)) { [Console]::Out.Write('ACTIVE') }
    else { [Console]::Out.Write('GONE') }
    exit 0
  }
  $spec = Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
  $result = [HarnessJob]::Run($spec.executable, $spec.worker, $spec.cwd, $spec.job, $spec.ipc)
  exit $result
} catch {
  [Console]::Error.WriteLine('PREPARE_JOB_UNREACHED: ' + $_.Exception.Message)
  exit 1
}
