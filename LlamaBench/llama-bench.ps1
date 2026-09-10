# ================================================================
# ONE CLICK NVIDIA AI BENCHMARK
# RTX 3090 vs RTX 5090
# ================================================================

$ErrorActionPreference = "Stop"

$Root      = Join-Path $PSScriptRoot "AI-GPU-Benchmark"
$BinDir    = Join-Path $Root "bin"
$ResultDir = Join-Path $Root "results"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null

$LlamaExe = Join-Path $BinDir "llama-bench.exe"

# ------------------------------------------------
# MODEL
# ------------------------------------------------

$HFRepo = "ggml-org/Qwen3.8-27B-GGUF:Q4_K_M"

# ------------------------------------------------
# SETTINGS
# ------------------------------------------------

$Repetitions = 3
$PromptSizes = "512,2048,4096"
$GenerationSizes = "128,512"

# ------------------------------------------------
# FUNCTIONS
# ------------------------------------------------

function Title($text) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Info($text) {
    Write-Host "[>] $text" -ForegroundColor Gray
}

function OK($text) {
    Write-Host "[OK] $text" -ForegroundColor Green
}

function ErrorExit($text) {
    Write-Host ""
    Write-Host "[ERROR] $text" -ForegroundColor Red
    Write-Host ""
    Read-Host "Druk Enter om af te sluiten"
    exit 1
}

Clear-Host

Title "LOCAL AI GPU BENCHMARK"

# ------------------------------------------------
# GPU
# ------------------------------------------------

Title "GPU CONTROLEREN"

if (-not (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue)) {
    ErrorExit "nvidia-smi.exe niet gevonden. Controleer je NVIDIA driver."
}

try {

    $gpu = nvidia-smi `
        --query-gpu=name,memory.total,driver_version `
        --format=csv,noheader,nounits 2>$null

    $p = $gpu.Split(",")

    $GPUName = $p[0].Trim()
    $VRAMMB  = [int]$p[1].Trim()
    $Driver  = $p[2].Trim()

    $VRAMGB = [math]::Round($VRAMMB / 1024,1)

}
catch {

    ErrorExit "NVIDIA GPU kon niet worden gelezen."
}

OK "GPU: $GPUName"
OK "VRAM: $VRAMGB GB"
OK "Driver: $Driver"

# ------------------------------------------------
# LLAMA.CPP
# ------------------------------------------------

Title "LLAMA.CPP"

if (Test-Path $LlamaExe) {

    OK "llama-bench bestaat al."

}
else {

    Info "Officiële llama.cpp CUDA build downloaden..."

    $TempZip = Join-Path $Root "llama.zip"
    $TempDir = Join-Path $Root "llama"

    #
    # Officiële actuele x64 CUDA build.
    #
    # CUDA 13.3 build werkt met moderne NVIDIA drivers
    # en ondersteunt RTX 30/40/50 series.
    #

    $URL = "https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-b10775-bin-win-cuda-13.3-x64.zip"

    #
    # Als bovenstaande release alias niet werkt,
    # gebruiken we de huidige bekende release.
    #

    try {

        Invoke-WebRequest `
            -Uri $URL `
            -OutFile $TempZip `
            -UseBasicParsing

    }
    catch {

        Info "Eerste downloadmethode mislukt."
        Info "Fallback naar CUDA 12.4 build..."

        $URL = "https://github.com/ggml-org/llama.cpp/releases/download/b10775/llama-b10775-bin-win-cuda-12.4-x64.zip"

        try {

            Invoke-WebRequest `
                -Uri $URL `
                -OutFile $TempZip `
                -UseBasicParsing

        }
        catch {

            ErrorExit "llama.cpp CUDA download mislukt."
        }
    }

    OK "llama.cpp download voltooid."

    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force
    }

    Info "Uitpakken..."

    Expand-Archive `
        -Path $TempZip `
        -DestinationPath $TempDir `
        -Force

    $Found = Get-ChildItem `
        -Path $TempDir `
        -Filter "llama-bench.exe" `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $Found) {

        Write-Host ""
        Write-Host "Gevonden bestanden:" -ForegroundColor Yellow

        Get-ChildItem `
            $TempDir `
            -Recurse |
            Select-Object FullName

        ErrorExit "llama-bench.exe niet gevonden."
    }

    #
    # Kopieer executable
    #

    Copy-Item `
        $Found.FullName `
        $LlamaExe `
        -Force

    #
    # Kopieer alle DLLs uit dezelfde map
    #

    Get-ChildItem `
        $Found.Directory.FullName `
        -Filter "*.dll" `
        -ErrorAction SilentlyContinue |
        Copy-Item `
            -Destination $BinDir `
            -Force

    Remove-Item $TempZip -Force
    Remove-Item $TempDir -Recurse -Force

    OK "llama.cpp geïnstalleerd."
}

# ------------------------------------------------
# TEST LLAMA
# ------------------------------------------------

Title "CUDA TEST"

try {

    $devices = & $LlamaExe --list-devices 2>&1

}
catch {

    ErrorExit "llama-bench kan niet worden gestart."
}

Write-Host ""

foreach ($line in $devices) {
    Write-Host $line
}

Write-Host ""

# ------------------------------------------------
# BENCHMARK
# ------------------------------------------------

Title "BENCHMARK"

Write-Host ""
Write-Host "GPU:"
Write-Host "  $GPUName" -ForegroundColor Green

Write-Host ""
Write-Host "Model:"
Write-Host "  Qwen3.8-27B Q4_K_M" -ForegroundColor Green

Write-Host ""
Write-Host "Prompt:"
Write-Host "  $PromptSizes"

Write-Host ""
Write-Host "Generation:"
Write-Host "  $GenerationSizes"

Write-Host ""
Write-Host "Repetitions:"
Write-Host "  $Repetitions"

Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host ""

Info "Model wordt automatisch door llama.cpp opgehaald."
Info "Dit is ongeveer 19 GB."
Write-Host ""
Write-Host "Start over 5 seconden..." -ForegroundColor Yellow

Start-Sleep 5

# ------------------------------------------------
# RUN
# ------------------------------------------------

$Arguments = @(
    "-hf", $HFRepo,
    "-ngl", "999",
    "-r", $Repetitions,
    "-p", $PromptSizes,
    "-n", $GenerationSizes,
    "-o", "csv"
)

Info "Benchmark gestart..."
Write-Host ""

$Output = & $LlamaExe @Arguments 2>&1

$ExitCode = $LASTEXITCODE

# ------------------------------------------------
# RAW OUTPUT
# ------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$RawFile = Join-Path `
    $ResultDir `
    "raw-$Timestamp.txt"

$Output |
    Out-File `
        $RawFile `
        -Encoding UTF8

if ($ExitCode -ne 0) {

    Write-Host ""
    Write-Host $Output
    Write-Host ""

    ErrorExit "Benchmark is mislukt."
}

# ------------------------------------------------
# CSV
# ------------------------------------------------

$CSVStart = -1

for ($i = 0; $i -lt $Output.Count; $i++) {

    if ($Output[$i] -match "build_commit") {

        $CSVStart = $i
        break
    }
}

if ($CSVStart -lt 0) {

    Write-Host $Output

    ErrorExit "CSV output niet gevonden."
}

$CSV = $Output[$CSVStart..($Output.Count - 1)]

$CSVFile = Join-Path `
    $ResultDir `
    "$($GPUName -replace '[^a-zA-Z0-9]','_')-$Timestamp.csv"

$CSV |
    Out-File `
        $CSVFile `
        -Encoding UTF8

$Data = $CSV |
    ConvertFrom-Csv

# ------------------------------------------------
# CALCULATE
# ------------------------------------------------

$PP = @(
    $Data |
    Where-Object {
        $_.test -match "^pp"
    }
)

$TG = @(
    $Data |
    Where-Object {
        $_.test -match "^tg"
    }
)

if ($PP.Count -eq 0 -or $TG.Count -eq 0) {

    Write-Host $CSV

    ErrorExit "Geen geldige benchmarkresultaten gevonden."
}

$PromptTPS = (
    $PP |
    Measure-Object `
        -Property avg_ts `
        -Average
).Average

$GenerationTPS = (
    $TG |
    Measure-Object `
        -Property avg_ts `
        -Average
).Average

$PromptTPS = [double]$PromptTPS
$GenerationTPS = [double]$GenerationTPS

# ------------------------------------------------
# SCORE
# ------------------------------------------------

$PromptScore =
    ($PromptTPS / 1500) * 300

$GenerationScore =
    ($GenerationTPS / 40) * 700

$AIScore = [math]::Round(
    $PromptScore + $GenerationScore,
    0
)

# ------------------------------------------------
# SAVE HISTORY
# ------------------------------------------------

$HistoryFile = Join-Path `
    $ResultDir `
    "history.json"

$History = @()

if (Test-Path $HistoryFile) {

    try {

        $History = @(
            Get-Content `
                $HistoryFile `
                -Raw |
            ConvertFrom-Json
        )

    }
    catch {

        $History = @()
    }
}

$Result = [PSCustomObject]@{

    Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    GPU = $GPUName

    VRAM_GB = $VRAMGB

    Driver = $Driver

    Model = $HFRepo

    Prompt_TPS = [math]::Round(
        $PromptTPS,
        2
    )

    Generation_TPS = [math]::Round(
        $GenerationTPS,
        2
    )

    AI_Score = $AIScore
}

$History += $Result

$History |
    ConvertTo-Json -Depth 5 |
    Out-File `
        $HistoryFile `
        -Encoding UTF8

# ------------------------------------------------
# COMPARE
# ------------------------------------------------

$Previous = $History |
    Where-Object {
        $_.Model -eq $HFRepo -and
        $_.GPU -ne $GPUName
    } |
    Select-Object -Last 1

$Comparison = ""

if ($Previous) {

    $ScoreDiff =
        (
            ($AIScore - $Previous.AI_Score) /
            $Previous.AI_Score
        ) * 100

    $GenDiff =
        (
            ($GenerationTPS -
            $Previous.Generation_TPS) /
            $Previous.Generation_TPS
        ) * 100

    $PPDiff =
        (
            ($PromptTPS -
            $Previous.Prompt_TPS) /
            $Previous.Prompt_TPS
        ) * 100

    $Comparison = @"

============================================================
VERGELIJKING MET VORIGE GPU
============================================================

Vorige GPU:
$($Previous.GPU)

Nieuwe GPU:
$GPUName

------------------------------------------------------------

AI SCORE

Vorige:
$($Previous.AI_Score)

Nieuwe:
$AIScore

Verschil:
$([math]::Round($ScoreDiff,1)) %

------------------------------------------------------------

GENERATION

Vorige:
$($Previous.Generation_TPS) tok/s

Nieuwe:
$([math]::Round($GenerationTPS,2)) tok/s

Verschil:
$([math]::Round($GenDiff,1)) %

------------------------------------------------------------

PROMPT PROCESSING

Vorige:
$($Previous.Prompt_TPS) tok/s

Nieuwe:
$([math]::Round($PromptTPS,2)) tok/s

Verschil:
$([math]::Round($PPDiff,1)) %

============================================================

"@
}

# ------------------------------------------------
# FINAL
# ------------------------------------------------

Clear-Host

Title "BENCHMARK RESULTAAT"

Write-Host ""
Write-Host "GPU" -ForegroundColor Gray
Write-Host $GPUName -ForegroundColor Green

Write-Host ""
Write-Host "VRAM" -ForegroundColor Gray
Write-Host "$VRAMGB GB" -ForegroundColor Green

Write-Host ""
Write-Host "MODEL" -ForegroundColor Gray
Write-Host "Qwen3.8-27B Q4_K_M" -ForegroundColor Green

Write-Host ""
Write-Host "PROMPT PROCESSING" -ForegroundColor Gray
Write-Host "$([math]::Round($PromptTPS,2)) tok/s" -ForegroundColor Cyan

Write-Host ""
Write-Host "GENERATION" -ForegroundColor Gray
Write-Host "$([math]::Round($GenerationTPS,2)) tok/s" -ForegroundColor Cyan

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "                  AI SCORE: $AIScore" -ForegroundColor Yellow
Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow

if ($Comparison) {

    Write-Host $Comparison
}

Write-Host ""
Write-Host "Resultaten:"
Write-Host $ResultDir

Write-Host ""
Write-Host "Benchmark succesvol afgerond." -ForegroundColor Green

Write-Host ""
Read-Host "Druk Enter om af te sluiten"