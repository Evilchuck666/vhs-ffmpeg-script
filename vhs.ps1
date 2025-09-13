param (
    [string]$InputPath,
    [string]$JsonPath
)


# === Global Constants === #

# 🔧 General Settings
$global:sampleRate      = 48000
$global:bitDepth        = 32
$global:channels        = 2
$global:lowPassFreq     = 4000
$global:inVol           = 1.0
$global:outVol          = 0.077
$global:db              = -22.75
$global:dbVolume        = ([math]::Pow(10, $db/20))

# 🎨 VHS Filter (ffmpeg)
$global:ffmpegFilter `
    = "format=yuv420p, split=3 [a][b][c]; `
    [a] extractplanes=y [y]; `
    [b] extractplanes=u [u]; `
    [c] extractplanes=v [v]; `
    [y] scale=768:1080, scale=1920:1080 [luma_scaled]; `
    [u] scale=120:540, scale=960:540 [u_scaled]; `
    [v] scale=120:540, scale=960:540 [v_scaled]; `
    [luma_scaled][u_scaled][v_scaled] mergeplanes=0x001020:yuv420p [merged]; `
    [merged] eq=saturation=0.75, noise=alls=5:allf=t, geq='lum(X+5.5*(random(floor(Y/96))-0.5),Y)':cb='cb(X,Y)':cr='cr(X,Y)' [outv]"

# 📁 Files
$global:vhsFile         = "<<YOUR_VIDEOS_FOLDER>>\vhs.avi"
$global:wavFile         = "<<YOUR_VIDEOS_FOLDER>>\audio.wav"
$global:wavFxFile       = "<<YOUR_VIDEOS_FOLDER>>\vhs.wav"
$global:noise           = "<<YOUR_VIDEOS_FOLDER>>\noise.wav"
$global:mix             = "<<YOUR_VIDEOS_FOLDER>>\mix.wav"

# 🎞️ Codecs & formats
$global:vCodec          = "utvideo"
$global:aCodec          = "pcm_f32le"
$global:pixFmt          = "yuv420p"
$global:vidColorspace   = "bt709"


# === Global Variables === #
$global:InputVideoPath  = ""


# === Functions === #
function ProcessJsonList {
    if (-not (Test-Path $JsonPath)) {
        Write-Error "The JSON file '$JsonPath' does not exist."
        exit 1
    }

    $jsonContent = Get-Content $JsonPath -Raw | ConvertFrom-Json

    foreach ($video in $jsonContent) {
        Write-Host "#### Processing: $video ####"
        ProcessVideo -VideoPath "$video"
    }
}

function ProcessVideo {
    param (
        [string]$VideoPath
    )

    if (-not (Test-Path $VideoPath)) {
        Write-Error "#### File '$VideoPath' does not exist."
        exit 1
    }

    $global:InputVideoPath = $VideoPath

    Step0_VhsFx
    Step1_AudioFx
    Step2_MapInputs
    Step3_Clean
}

function GetInputVideoPath {
    if (-not $InputPath) {
        Write-Host "Drag the video here or type the full path"
        $InputPath = Read-Host "Video path"
    }

    $InputPath = $InputPath.Trim('"')
    $global:InputVideoPath = $InputPath

    if (-not (Test-Path $InputPath)) {
        Write-Error "File '$InputPath' does not exist."
        exit 1
    }

    $global:InputVideoPath = $InputPath
}

function Step0_VhsFx {
    Write-Host "#### Running Step 0: Applying VHS Effect to video ####"

    $args = @(
        '-i', "`"$global:InputVideoPath`"",
        '-filter_complex', "`"$ffmpegFilter`"",
        '-c:v', $vCodec,
        '-pix_fmt', $pixFmt,
        '-colorspace', $vidColorspace,
        '-color_primaries', $vidColorspace,
        '-color_trc', $vidColorspace,
        '-map', '[outv]',
        "`"$vhsFile`"",
        '-map', 'a',
        '-c:a', $aCodec,
        "`"$wavFile`"",
        '-y'
    )

    Start-Process -FilePath "ffmpeg" -ArgumentList $args -Wait -NoNewWindow
}

function Step1_AudioFx {
    Write-Host "#### Running Step 1: Applying VHS Effect to audio ####"

    # === Get duration using ffprobe === #
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ffprobe"
    $psi.Arguments = "-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 `"$global:InputVideoPath`""
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $duration = $proc.StandardOutput.ReadToEnd().Trim()
    $proc.WaitForExit()

    if (-not $duration -or $duration -eq "N/A") {
        Write-Error "Cannot get the duration from input file."
        exit 1
    }

    # 1. Brown noise
    $args1 = @(
        "-n", "-r", $sampleRate, "-b", $bitDepth, "-e", "floating-point",
        "-c", $channels, "`"$noise`"", "synth", $duration, "brownnoise", "vol", $dbVolume
    )
    Start-Process -FilePath "sox" -ArgumentList $args1 -Wait -NoNewWindow

    # 2. Mezcla
    $args2 = @(
        "-m", "-v", $inVol, "`"$wavFile`"", "-v", $outVol, "`"$noise`"", "`"$mix`""
    )
    Start-Process -FilePath "sox" -ArgumentList $args2 -Wait -NoNewWindow

    # 3. Filtro pasa bajos
    $args3 = @(
        "`"$mix`"", "`"$wavFxFile`"", "lowpass", $lowPassFreq
    )
    Start-Process -FilePath "sox" -ArgumentList $args3 -Wait -NoNewWindow
}

function Step2_MapInputs {
    Write-Host "#### Running Step 2: Mixing video and audio tracks into a single file ####"

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($global:InputVideoPath) -replace '[:*?"<>|]', '-'
    $finalPath = "<<YOUR_VIDEOS_FOLDER>>\$baseName.avi"

    $args = @(
        "-i", "`"$vhsFile`"",
        "-i", "`"$wavFxFile`"",
        "-map", "0:v",
        "-map", "1:a",
        "-c", "copy",
        "`"$finalPath`"",
        "-y"
    )

    Start-Process -FilePath "ffmpeg" -ArgumentList $args -Wait -NoNewWindow
}

function Step3_Clean {
    Remove-Item @($noise, $mix, $vhsFile, $wavFxFile, $wavFile) -ErrorAction SilentlyContinue
}

function Main {
    if ($JsonPath) {
        ProcessJsonList
    } else {
        GetInputVideoPath
        ProcessVideo -VideoPath $global:InputVideoPath
    }
}


# === Main === #
Main
