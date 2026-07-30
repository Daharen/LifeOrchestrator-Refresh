#requires -Version 7.0
# Mock llama-server for model.gateway OFF-MACHINE (no-GPU) tests. It ignores the llama.cpp arguments the
# gateway passes (-m/-ngl/-c/--host/--no-warmup), reads --port, and serves a minimal HTTP/1.1 API:
#   GET  /health               -> 200 {"status":"ok"}
#   GET  /v1/models            -> 200 canned model list (provenance)
#   GET  /props                -> 200 canned props
#   POST /slots/<id>?action=erase -> 200 ack (KV isolation); logged for the fault-injection suite
#   POST /v1/chat/completions  -> 200 canned OpenAI-style reply (content "PONG", finish_reason "stop")
#
# IMPORTANT: it binds a RAW System.Net.Sockets.TcpListener (NOT HttpListener). On Windows HttpListener is
# backed by the kernel http.sys driver, so the LISTENING SOCKET is owned by System (pid 4), not this process
# -- which would (correctly) fail the gateway's Stage-1.1 socket-owner gate the same way a spoofed endpoint
# would. A real llama-server binds its own socket; a raw TcpListener does too, so the socket owner is THIS
# process's pid and the gateway can verify it on Windows exactly as it would a real server. Runs until killed.
$ErrorActionPreference = 'Stop'
$raw = [Environment]::GetCommandLineArgs()
$port = 0
for ($i = 0; $i -lt $raw.Count; $i++) {
    if ($raw[$i] -eq '--port' -and ($i + 1) -lt $raw.Count) { $port = [int]$raw[$i + 1]; break }
}
if ($port -le 0) { [Console]::Error.WriteLine('mock-llama-server: no --port in args'); exit 2 }
$utf8 = [System.Text.UTF8Encoding]::new($false)
# WMI-safe erase log: a deterministic port-derived path (an env var does not survive Win32_Process.Create,
# so the fault-injection suite reads THIS path). Records every /slots erase so KV isolation is provable.
$eraseLog = Join-Path ([System.IO.Path]::GetTempPath()) "mock-erase-$port.log"

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
try { $listener.Start() } catch { [Console]::Error.WriteLine("mock-llama-server: listener start failed on ${port}: $($_.Exception.Message)"); exit 3 }
[Console]::Error.WriteLine("mock-llama-server (raw tcp) listening on $port pid=$PID")

function Send-Http($stream, [int]$code, [string]$body) {
    $bytes = $utf8.GetBytes($body)
    $head = "HTTP/1.1 $code OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
    $hb = $utf8.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
}

try {
    while ($true) {
        $client = $null
        try { $client = $listener.AcceptTcpClient() } catch { break }
        try {
            $client.ReceiveTimeout = 5000
            $stream = $client.GetStream()
            # ---- read the request head (until CRLFCRLF), then any Content-Length body ----
            $buf = New-Object System.Collections.Generic.List[byte]
            $one = New-Object 'byte[]' 1
            $headerEnd = -1
            while ($headerEnd -lt 0) {
                $n = $stream.Read($one, 0, 1)
                if ($n -le 0) { break }
                $buf.Add($one[0])
                if ($buf.Count -ge 4 -and $buf[$buf.Count-4] -eq 13 -and $buf[$buf.Count-3] -eq 10 -and $buf[$buf.Count-2] -eq 13 -and $buf[$buf.Count-1] -eq 10) { $headerEnd = $buf.Count }
            }
            if ($headerEnd -lt 0) { $client.Close(); continue }
            $headText = $utf8.GetString($buf.ToArray(), 0, $headerEnd)
            $lines = $headText -split "`r`n"
            $reqLine = if ($lines.Count -gt 0) { $lines[0] } else { '' }
            $parts = $reqLine -split '\s+'
            $method = if ($parts.Count -gt 0) { $parts[0] } else { '' }
            $target = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            $qidx = $target.IndexOf('?'); $path = if ($qidx -ge 0) { $target.Substring(0, $qidx) } else { $target }
            $query = if ($qidx -ge 0) { $target.Substring($qidx + 1) } else { '' }
            $clen = 0
            foreach ($ln in $lines) { if ($ln -match '(?i)^Content-Length:\s*(\d+)') { $clen = [int]$Matches[1] } }
            if ($clen -gt 0) { $body = New-Object 'byte[]' $clen; $read = 0; while ($read -lt $clen) { $r = $stream.Read($body, $read, $clen - $read); if ($r -le 0) { break }; $read += $r } }

            if ($path -eq '/health') {
                Send-Http $stream 200 '{"status":"ok"}'
            } elseif ($path -eq '/v1/models') {
                Send-Http $stream 200 '{"object":"list","data":[{"id":"mock","object":"model","owned_by":"mock-llama-server"}]}'
            } elseif ($path -eq '/props') {
                Send-Http $stream 200 '{"model_path":"mock","default_generation_settings":{"n_ctx":4096}}'
            } elseif ($path -like '/slots*') {
                if ("$query" -like '*action=erase*') { try { [System.IO.File]::AppendAllText($eraseLog, "erase $path?$query $([DateTime]::UtcNow.ToString('o'))`n") } catch { } }
                Send-Http $stream 200 '{"id_slot":0,"status":"ok"}'
            } elseif ($path -eq '/v1/chat/completions') {
                $obj = '{"id":"mock-cmpl","object":"chat.completion","model":"mock","choices":[{"index":0,"message":{"role":"assistant","content":"PONG"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":1,"total_tokens":6},"timings":{"predicted_per_second":999.0}}'
                Send-Http $stream 200 $obj
            } else {
                Send-Http $stream 404 '{"error":"not found"}'
            }
        } catch { } finally { try { $client.Close() } catch { } }
    }
} finally { try { $listener.Stop() } catch { } }
