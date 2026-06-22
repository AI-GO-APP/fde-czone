# AigoClient.ps1 - aigo 雲端 client (階段二)
# 重點: PS5.1 的 Invoke-RestMethod 對「無 charset 的 UTF-8 JSON」會解成亂碼,
#       所以一律自己用 UTF-8 decode RawContentStream, 中文(公司名/料種/操作員)才不會壞。
# 階段一(手動列印)不會用到這支; 留待接 aigo weigh 時使用。

$ErrorActionPreference = 'Stop'
$script:AigoToken = $null

function Connect-Aigo {
    param([Parameter(Mandatory)]$Cfg)
    $body = @{ email = $Cfg.email; password = $Cfg.password } | ConvertTo-Json -Compress
    $resp = Invoke-WebRequest -Method Post -Uri "$($Cfg.aigoBaseUrl)/api/v1/auth/login" `
        -Body $body -ContentType 'application/json' -UseBasicParsing
    $json = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    return $json.access_token
}

function Invoke-AigoWeigh {
    # 回傳完整信封 {status, result, error, ...} (見 PLATFORM_NOTES)。
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)]$Params)
    $uri = "$($Cfg.aigoBaseUrl)/api/v1/actions/apps/$($Cfg.appId)/run/weigh"
    $body = @{ params = $Params } | ConvertTo-Json -Compress -Depth 8
    # 重點: PS5.1 直接傳字串 body 會用非 UTF-8 編碼, 送出的中文(操作員/料種)會變 '???'。
    #       一律轉 UTF-8 bytes 再送, 並標 charset=utf-8。
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp = Invoke-WebRequest -Method Post -Uri $uri -Headers @{ Authorization = "Bearer $Token" } `
        -Body $bytes -ContentType 'application/json; charset=utf-8' -UseBasicParsing
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function Resolve-AigoWeigh {
    # 呼叫 weigh, token 過期自動重登一次; 解開信封, 成功回 .result, 失敗丟錯。
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)]$Params)
    if (-not $script:AigoToken) { $script:AigoToken = Connect-Aigo $Cfg }
    $envelope = $null
    try { $envelope = Invoke-AigoWeigh $Cfg $script:AigoToken $Params }
    catch {
        $script:AigoToken = Connect-Aigo $Cfg
        $envelope = Invoke-AigoWeigh $Cfg $script:AigoToken $Params
    }
    if ($envelope.status -ne 'success') { throw "weigh 失敗: $($envelope.error)" }
    return $envelope.result
}

function Get-AigoObjectId {
    # 由 api_slug 找 Custom Object id
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$Slug)
    $resp = Invoke-WebRequest -Method Get -Uri "$($Cfg.aigoBaseUrl)/api/v1/data/objects" `
        -Headers @{ Authorization = "Bearer $Token" } -UseBasicParsing
    $objs = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    foreach ($o in $objs) { if ($o.api_slug -eq $Slug) { return $o.id } }
    throw "找不到資料表 $Slug"
}

function Get-AigoWeighings {
    # 撈 x_czone_weighing 紀錄, 回傳陣列, 每筆 {id, data:{...}}。
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Token)
    $oid = Get-AigoObjectId $Cfg $Token 'x_czone_weighing'
    $resp = Invoke-WebRequest -Method Get -Uri "$($Cfg.aigoBaseUrl)/api/v1/data/objects/$oid/records" `
        -Headers @{ Authorization = "Bearer $Token" } -UseBasicParsing
    $j = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    if ($j -is [array]) { return $j }
    if ($j.records) { return $j.records }
    return @($j)
}

function Resolve-AigoWeighings {
    # 撈紀錄, token 過期自動重登一次。
    param([Parameter(Mandatory)]$Cfg)
    if (-not $script:AigoToken) { $script:AigoToken = Connect-Aigo $Cfg }
    try { return Get-AigoWeighings $Cfg $script:AigoToken }
    catch { $script:AigoToken = Connect-Aigo $Cfg; return Get-AigoWeighings $Cfg $script:AigoToken }
}
