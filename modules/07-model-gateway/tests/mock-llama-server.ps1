#requires -Version 7.0
# Mock llama-server for model.gateway OFF-MACHINE (no-GPU) tests. It ignores the llama.cpp arguments the
# gateway passes (-m/-ngl/-c/--host/--no-warmup), reads --port, and serves:
#   GET  /health               -> 200 {"status":"ok"}
#   POST /v1/chat/completions  -> 200 canned OpenAI-style reply (content "PONG", finish_reason "stop")
# It runs until killed, so a warm/resident server started by one gateway invocation is reachable by the next.
$ErrorActionPreference = 'Stop'
# Read the RAW process command line so llama.cpp-style dash args never hit PowerShell param binding.
$raw = [Environment]::GetCommandLineArgs()
$port = 0
for ($i = 0; $i -lt $raw.Count; $i++) {
    if ($raw[$i] -eq '--port' -and ($i + 1) -lt $raw.Count) { $port = [int]$raw[$i + 1]; break }
}
if ($port -le 0) { [Console]::Error.WriteLine('mock-llama-server: no --port in args'); exit 2 }
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try { $listener.Start() } catch { [Console]::Error.WriteLine("mock-llama-server: listener start failed on ${port}: $($_.Exception.Message)"); exit 3 }
[Console]::Error.WriteLine("mock-llama-server listening on $port pid=$PID")
$utf8 = [System.Text.UTF8Encoding]::new($false)
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request; $resp = $ctx.Response
        $path = $req.Url.AbsolutePath
        if ($path -eq '/health') {
            $bodyStr = '{"status":"ok"}'; $resp.StatusCode = 200
        } elseif ($path -eq '/v1/models') {
            # provenance endpoint the pool manager confirms after a load (Stage-1)
            $bodyStr = '{"object":"list","data":[{"id":"mock","object":"model","owned_by":"mock-llama-server"}]}'; $resp.StatusCode = 200
        } elseif ($path -eq '/props') {
            $bodyStr = '{"model_path":"mock","default_generation_settings":{"n_ctx":4096}}'; $resp.StatusCode = 200
        } elseif ($path -like '/slots*') {
            # prefix-cache slot ops (e.g. ?action=erase at a session boundary); ack so the gateway does not warn
            try { $sr = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding); [void]$sr.ReadToEnd(); $sr.Dispose() } catch { }
            $bodyStr = '{"id_slot":0,"status":"ok"}'; $resp.StatusCode = 200
        } elseif ($path -eq '/v1/chat/completions') {
            try { $sr = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding); [void]$sr.ReadToEnd(); $sr.Dispose() } catch { }
            $obj = [ordered]@{
                id = 'mock-cmpl'; object = 'chat.completion'; model = 'mock'
                choices = @(@{ index = 0; message = @{ role = 'assistant'; content = 'PONG' }; finish_reason = 'stop' })
                usage = @{ prompt_tokens = 5; completion_tokens = 1; total_tokens = 6 }
                timings = @{ predicted_per_second = 999.0 }
            }
            $bodyStr = ($obj | ConvertTo-Json -Depth 8 -Compress); $resp.StatusCode = 200
        } else {
            $bodyStr = '{"error":"not found"}'; $resp.StatusCode = 404
        }
        $buf = $utf8.GetBytes($bodyStr)
        $resp.ContentType = 'application/json'
        $resp.ContentLength64 = $buf.Length
        $resp.OutputStream.Write($buf, 0, $buf.Length)
        $resp.OutputStream.Close()
    }
} finally { try { $listener.Stop() } catch { } }
