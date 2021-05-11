function GetGameMenuItems
{
    param(
        $menuArgs
    )

    $menuItem = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem.Description =  "Download Steam trailer video (SD quality)"
    $menuItem.FunctionName = "Get-SteamVideoSd"
    $menuItem.MenuSection = "Extra Metadata tools|Video|Trailers"
   
    $menuItem2 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem2.Description =  "Download Steam trailer video (HD quality)"
    $menuItem2.FunctionName = "Get-SteamVideoHd"
    $menuItem2.MenuSection = "Extra Metadata tools|Video|Trailers"

    $menuItem3 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem3.Description =  "Download Steam microtrailer video"
    $menuItem3.FunctionName = "Get-SteamVideoMicro"
    $menuItem3.MenuSection = "Extra Metadata tools|Video|Microtrailers"

    $menuItem4 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem4.Description =  "Set trailer video for the selected game from file"
    $menuItem4.FunctionName = "Set-VideoManuallyTrailer"
    $menuItem4.MenuSection = "Extra Metadata tools|Video|Trailers"

    $menuItem5 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem5.Description =  "Set microtrailer video for the selected game from file"
    $menuItem5.FunctionName = "Set-VideoManuallyMicroTrailer"
    $menuItem5.MenuSection = "Extra Metadata tools|Video|Microtrailers"
    
    $menuItem6 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem6.Description =  "Generate microtrailer video from configured trailer video"
    $menuItem6.FunctionName = "Get-VideoMicrotrailerFromTrailer"
    $menuItem6.MenuSection = "Extra Metadata tools|Video|Microtrailers"
    
    $menuItem7 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem7.Description =  "Delete trailer video of the selected game(s)"
    $menuItem7.FunctionName = "Remove-VideoTrailer"
    $menuItem7.MenuSection = "Extra Metadata tools|Video|Trailers"

    $menuItem8 = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $menuItem8.Description =  "Delete microtrailer video of the selected game(s)"
    $menuItem8.FunctionName = "Remove-VideoMicrotrailer"
    $menuItem8.MenuSection = "Extra Metadata tools|Video|Microtrailers"

    return $menuItem, $menuItem2, $menuItem3, $menuItem4, $menuItem5, $menuItem6, $menuItem7, $menuItem8
}

function Get-MandatorySettingsList
{
    [System.Collections.Generic.List[String]]$mandatorySettingsList = @(
        "ffmpegPath",
        "ffProbePath"
    )

    return $mandatorySettingsList
}

function Get-Settings
{
    $mandatorySettingsList = Get-MandatorySettingsList
    $settingsObject = [PSCustomObject]@{}
    
    foreach ($mandatorySetting in $mandatorySettingsList) {
        $settingsObject | Add-Member -NotePropertyName $mandatorySetting -NotePropertyValue $null
    }
    
    $settingsStoragePath = Join-Path -Path $CurrentExtensionDataPath -ChildPath 'settings.json'
    if (Test-Path $settingsStoragePath)
    {
        $savedSettings = [System.IO.File]::ReadAllLines($settingsStoragePath) | ConvertFrom-Json
        foreach ($mandatorySetting in $mandatorySettingsList) {
            if ($savedSettings.$mandatorySetting)
            {
                $settingsObject.$mandatorySetting = $savedSettings.$mandatorySetting
            }
        }
    }

    return $settingsObject
}

function Save-Settings
{
    param (
        $settingsObject
    )
    
    $settingsStoragePath = Join-Path -Path $CurrentExtensionDataPath -ChildPath 'settings.json'
    $settingsJson = $settingsObject | ConvertTo-Json
    [System.IO.File]::WriteAllLines($settingsStoragePath, $settingsJson)
}

function Set-MandatorySettings
{
    $settings = Get-Settings

    # Setting: ffmpegPath
    if (![string]::IsNullOrEmpty($settings.ffmpegPath))
    {
        if (!(Test-Path $settings.ffmpegPath))
        {
            $__logger.Info(("ffmpeg executable not found in {0} and saved path was deleted." -f $ffmpegPath))
            $settings.ffmpegPath = $null
        }
    }

    if ($null -eq $settings.ffmpegPath)
    {
        $PlayniteApi.Dialogs.ShowMessage("Select ffmpeg executable", "Extra Metadata Tools")
        $ffmpegPath = $PlayniteApi.Dialogs.SelectFile("ffmpeg executable|ffmpeg.exe")
        if ($ffmpegPath)
        {
            $settings.ffmpegPath = $ffmpegPath
            $__logger.Info(("Saved ffmpeg path: {0}" -f $settings.ffmpegPath))
        }
    }

    # Setting: ffprobePath
    if (![string]::IsNullOrEmpty($settings.ffProbePath))
    {
        if (!(Test-Path $settings.ffProbePath))
        {
            $__logger.Info(("ffProbePath executable not found in {0} and saved path was deleted." -f $settings.ffProbePath))
            $settings.ffprobePath = $null
        }
    }

    if ($null -eq $settings.ffprobePath)
    {
        $PlayniteApi.Dialogs.ShowMessage("Select ffProbe executable", "Extra Metadata Tools")
        $ffProbePath = $PlayniteApi.Dialogs.SelectFile("ffProbe executable|ffProbe.exe")
        if ($ffProbePath)
        {
            $settings.ffProbePath = $ffProbePath
            $__logger.Info(("Saved ffprobre path: {0}" -f $settings.ffProbePath))
        }
    }

    Save-Settings $settings

    $mandatorySettingsList = Get-MandatorySettingsList
    foreach ($mandatorySetting in $mandatorySettingsList)
    {
        if ([string]::IsNullOrEmpty($settings.$mandatorySetting))
        {
            $PlayniteApi.Dialogs.ShowMessage("Please configure all requested mandatory settings to continue", "Extra Metadata Tools")
            exit
        }
    }
}

function Set-GameDirectory
{
    param (
        $game
    )

    $directory = [System.IO.Path]::Combine($PlayniteApi.Paths.ConfigurationPath, "ExtraMetadata", "games", $game.Id) 
    if(!(Test-Path $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    return $directory
}

function Get-RequestStatusCode
{
    param (
        $url
    )
    
    try {
        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        return $response.StatusCode
    } catch {
        $statusCode = $_.Exception.InnerException.Response.StatusCode
        $errorMessage = $_.Exception.Message
        $__logger.Info("Error connecting to server. Error: $errorMessage")
        if ($statusCode -ne 'NotFound')
        {
            $PlayniteApi.Dialogs.ShowMessage("Error connecting to server. Error: $errorMessage");
        }
        return $statusCode
    }
}

function Get-DownloadString
{
    param (
        [string]$url
    )
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $DownloadedString = $webClient.DownloadString($url)
        $webClient.Dispose()
        return $DownloadedString
    } catch {
        $webClient.Dispose()
        $errorMessage = $_.Exception.Message
        $__logger.Info("Error downloading file `"$url`". Error: $errorMessage")
        $PlayniteApi.Dialogs.ShowMessage("Error downloading file `"$url`". Error: $errorMessage") | Out-Null
        return
    }
}

function Get-DownloadFile
{
    param (
        [string]$url,
        [string]$destinationPath
    )

    try {
        $webClient = [System.Net.WebClient]::new()
        $webClient.DownloadFile($url, $destinationPath)
        $webClient.Dispose()

        # In case an empty file was downloaded
        # Steam has video urls that don't exist but have 'OK' status code
        if ((Get-Item $destinationPath).length -eq 0)
        {
            $__logger.Info(("Downloaded file had 0 lenght: {0}." -f $url, $errorMessage))
            try {
                Remove-Item $destinationPath
            } catch {}
            return $false
        }

        $__logger.Info(("Downloaded {0} to {1}" -f $url, $destinationPath))
        return $true
    } catch {
        $webClient.Dispose()
        $errorMessage = $_.Exception.Message
        $__logger.Info(("Error downloading file: {0}. ErrorMessage: {1}" -f $url, $errorMessage))
        return $false
    }
}

function Get-SteamAppList
{
    param (
        $appListPath
    )

    $uri = 'https://api.steampowered.com/ISteamApps/GetAppList/v2/'
    $steamAppList = Get-DownloadString $uri
    if ($null -ne $steamAppList)
    {
        [array]$appListContent = ($steamAppList | ConvertFrom-Json).applist.apps
        foreach ($steamApp in $appListContent) {
            $steamApp.name = $steamApp.name.ToLower() -replace '[^\p{L}\p{Nd}]', ''
        }
        ConvertTo-Json $appListContent -Depth 2 -Compress | Out-File -Encoding 'UTF8' -FilePath $appListPath
        $__logger.Info("Downloaded AppList")
        $global:appListDownloaded = $true
    }
    else
    {
        exit
    }
}

function Set-GlobalAppList
{
    param (
        [bool]$forceDownload
    )
    
    # Get Steam AppList
    $appListPath = Join-Path -Path $CurrentExtensionDataPath -ChildPath 'AppList.json'
    if (!(Test-Path $appListPath) -or ($forceDownload -eq $true))
    {
        Get-SteamAppList -AppListPath $appListPath
    }
    $global:appList = @{}
    [object]$appListJson = [System.IO.File]::ReadAllLines($appListPath) | ConvertFrom-Json
    foreach ($steamApp in $appListJson) {
        # Use a try block in case multple apps use the same name
        try {
            $appList.add($steamApp.name, $steamApp.appid)
        } catch {}
    }

    $__logger.Info(("Global applist set from {0}" -f $appListPath))
}

function Get-SteamAppId
{
    param (
        $game
    )

    $gamePlugin = [Playnite.SDK.BuiltinExtensions]::GetExtensionFromId($game.PluginId).ToString()
    $__logger.Info(("Get-SteammAppId start. Game: {0}, Plugin: {1}" -f $game.Name, $gamePlugin))

    # Use GameId for Steam games
    if ($gamePlugin -eq "SteamLibrary")
    {
        $__logger.Info(("Game: {0}, appId {1} found via pluginId" -f $game.Name, $game.GameId))
        return $game.GameId
    }
    elseif ($null -ne $game.Links)
    {
        # Look for Steam Store URL in links for other games
        foreach ($link in $game.Links) {
            if ($link.Url -match "https?://store.steampowered.com/app/(\d+)/?")
            {
                $__logger.Info(("Game: {0}, appId {1} found via links" -f $game.Name, $link.Url))
                return $matches[1]
            }
        }
    }

    $gameName = $game.Name.ToLower() -replace '[^\p{L}\p{Nd}]', ''
    if ($null -ne $appList[$gameName])
    {
        $appId = $appList[$gameName].ToString()
        $__logger.Info(("Game: {0}, appId {1} found via AppList" -f $game.Name, $appId))
        return $appId
    }
    
    if ((!$appId) -and ($appListDownloaded -eq $false))
    {
        # Download Steam AppList if game was not found in local Steam AppList database and local Steam AppList database is older than 2 days
        $appListPath = Join-Path -Path $CurrentExtensionDataPath -ChildPath 'AppList.json'
        $AppListLastWrite = (Get-Item $appListPath).LastWriteTime
        $timeSpan = New-Timespan -days 2
        if (((Get-date) - $AppListLastWrite) -gt $timeSpan)
        {
            Set-GlobalAppList $true
            if ($null -ne $appList[$gameName])
            {
                $appId = $appList[$gameName].ToString()
                $__logger.Info(("Game: {0}, appId {1} found via AppList" -f $game.Name, $appId))
                return $appId
            }
            return $null
        }
    }
}

function Get-SteamVideoUrl
{
    param (
        $game,
        $videoQuality
    )

    $appId = Get-SteamAppId $game

    if ($null -eq $appId)
    {
        $__logger.Info(("Couldn't obtain appId. Game: {0}" -f $game.Name))
        return $null
    }
    
    # Set Steam API url and download json file
    Start-Sleep -Milliseconds 1300
    $steamApiUrl = "https://store.steampowered.com/api/appdetails?appids={0}" -f $appId
    try {
        $json = Get-DownloadString $steamApiUrl | ConvertFrom-Json
    } catch {
        $ErrorMessage = $_.Exception.Message
        $PlayniteApi.Dialogs.ShowMessage("Couldn't download game information. Error: $ErrorMessage") | Out-Null
        exit
    }

    # Check if json has 'movie' information
    if ($json.$appId.data.movies)
    {
        $videoId = $json.$AppId.data.movies[0].id
        if (($videoQuality -eq "480") -or ($videoQuality -eq "max"))
        {
            $videoUrl = $json.$AppId.data.movies[0].mp4.$VideoQuality -replace "\?t=\d+"
        }
        else
        {
            $videoUrl = "https://steamcdn-a.akamaihd.net/steam/apps/{0}/microtrailer.mp4" -f $videoId
        }
        
        $__logger.Info(("Obtained video Url: {0}" -f $videoUrl))
        return $videoUrl
    }
    else
    {
        $__logger.Info(("No movie data. Url: {0}" -f $steamApiUrl))
        return $null
    }
}

function Set-SteamVideo
{
    param (
        [string]$videoQuality
    )
    
    $settings = Get-Settings
    Set-GlobalAppList $false
    $gameDatabase = $PlayniteApi.MainView.SelectedGames
    $global:appListDownloaded = $false
    $videoSetCount = 0

    switch ($videoQuality) {
        "max" {$videoName = "VideoTrailer.mp4"}
        "480" {$videoName = "VideoTrailer.mp4"}
        "micro" {$videoName = "VideoMicrotrailer.mp4"}
        default {$videoName = "VideoTrailer.mp4"}
    }

    foreach ($game in $gameDatabase)
    {
        $extraMetadataDirectory = Set-GameDirectory $game
        $videoPath = Join-Path $extraMetadataDirectory -ChildPath $videoName
        $videoTempPath = Join-Path $extraMetadataDirectory -ChildPath "VideoTemp.mp4"
        if (Test-Path $videoTempPath)
        {
            try {
                Remove-Item $videoTempPath -Force
            } catch {}
        }

        if (Test-Path $videoPath)
        {
            continue
        }

        $videoUrl = Get-SteamVideoUrl -Game $game -VideoQuality $videoQuality
        if ($null -eq $videoUrl)
        {
            continue
        }
        $downloadSuccess = Get-DownloadFile $videoUrl $videoTempPath
        if ($downloadSuccess -eq $true)
        {
            $isConversionNeeded = Get-IsConversionNeeded $videoTempPath
            if ($isConversionNeeded -eq $true)
            {
                $arguments = @("-y", "-i", $videoTempPath, "-c:v", "libx264", "-c:a", "mp3", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p", $videoPath)
                $__logger.Info(("Starting ffmpeg with arguments {0}" -f ($arguments -join ", ")))
                Start-Process -FilePath $settings.ffmpegPath -ArgumentList $arguments -Wait -WindowStyle Hidden
            }
            else
            {
                Move-Item $videoTempPath $videoPath -Force
                $__logger.Info(("Conversion is not needed for video and moved to {0}" -f $videoPath))
            }
            try {
                Remove-Item $videoTempPath -Force
            } catch {}
            if (Test-Path $videoPath)
            {
                $videoSetCount++
            }
        }
    }
    $PlayniteApi.Dialogs.ShowMessage(("Done.`n`nSet video to {0} game(s)" -f $videoSetCount.ToString()), "Extra Metadata Tools")
}

function Get-IsConversionNeeded
{
    param (
        $videoPath
    )
    
    if ([System.IO.Path]::GetExtension($videoPath) -ne ".mp4")
    {
        $__logger.Info(("Conversion is needed for video {0}, extension is not mp4" -f $videoTempPath))
        return $true
    }
    $videoInformation = Get-VideoInformation $videoPath

    if ($null -eq $videoInformation)
    {
        $__logger.Info(("Conversion is needed for video {0}, could not obtain video information" -f $videoTempPath))
        return $true
    }
    if ($videoInformation.ColorEncoding -eq "yuv444p")
    {
        $__logger.Info(("Conversion is needed for video {0}, color encoding is yuv444p" -f $videoTempPath))
        return $true
    }
    return $false
}

function Get-VideoInformation
{
    param (
        [string]$videoPath
    )

    $settings = Get-Settings
    $arguments = @("-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height, codec_name, pix_fmt, duration", "-of", "json", $videoPath)
    $output = &$settings.ffProbePath $arguments | ConvertFrom-Json
    if ($null -ne $output)
    {
        $videoInformation = [PSCustomObject]@{
            Codec = $output.streams.codec_name
            VideoWidth = $output.streams.width
            VideoHeight = $output.streams.height
            ColorEncoding = $output.streams.pix_fmt
            VideoDurationSeconds = $output.streams.duration
        }

        # Log video Properties
        $propertiesString = @(
            "Video Path: $videoPath"
        )
        foreach ($property in $videoInformation.PSObject.Properties)
        {
            $propertiesString += ("{0}: {1}" -f $property.Name, $property.Value)
        }

        $__logger.Info(($propertiesString -join ", "))

        return $videoInformation
    }
    return $null
}

function Get-VideoMicrotrailerFromVideo
{
    param (
        [string]$videoSourcePath,
        [string]$videoDestinationPath
    )

    $settings = Get-Settings
    $videoInformation = Get-VideoInformation $videoSourcePath

    if ([System.Double]::Parse($videoInformation.VideoDurationSeconds) -le 14)
    {
        $isConversionNeeded = Get-IsConversionNeeded $videoSourcePath
        if ($isConversionNeeded -eq $true)
        {
            # Convert
            $arguments = @("-y", "-i", $videoSourcePath, "-c:v", "libx264", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p", "-an", $videoDestinationPath)
            $__logger.Info(("Starting ffmpeg with arguments {0}" -f ($arguments -join ", ")))
            Start-Process -FilePath $settings.ffmpegPath -ArgumentList $arguments -Wait -WindowStyle Hidden
        }
        else
        {
            # Just copy stream without audio
            $arguments = @("-y", "-i", $videoSourcePath, "-c:v", "copy", "-an", $videoDestinationPath)
            $__logger.Info(("Starting ffmpeg with arguments {0}" -f ($arguments -join ", ")))
            Start-Process -FilePath $settings.ffmpegPath -ArgumentList $arguments -Wait -WindowStyle Hidden
        }
    }
    else
    {
        $rangeString = @()
        $clipStartsecondList = @()
        $clipDuration = 1
        $startPercentageVideo = @(
            15,
            25,
            35,
            45,
            55,
            65
        )
        foreach ($percentage in $startPercentageVideo) {
            $startSecond = ($percentage * $videoInformation.VideoDurationSeconds) / 100
            $clipStartsecondList += ("{0:n2}" -f $startSecond) 
        }

        foreach ($clipStartSecond in $clipStartsecondList) {
            $clipStart = [System.Double]::Parse($clipStartsecond)
            $clipEnd = [System.Double]::Parse($clipStartsecond) + $clipDuration
            $rangeString += ("between(t,{0},{1})" -f $clipStart, $clipEnd)
        }
        
        # Convert
        $selectString = "`"select='" + ($rangeString -join "+") + "', setpts=N/FRAME_RATE/TB" + ", scale=trunc(iw/2)*2:trunc(ih/2)*2`""
        $arguments = @("-y", "-i", $videoSourcePath, "-vf", $selectString, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", $videoDestinationPath)
        $__logger.Info(("Starting ffmpeg with arguments {0}" -f ($arguments -join ", ")))
        Start-Process -FilePath $settings.ffmpegPath -ArgumentList $arguments -Wait -WindowStyle Hidden
    }
    return
}

function Get-VideoMicrotrailerFromTrailer
{
    Set-MandatorySettings
    $gameDatabase = $PlayniteApi.MainView.SelectedGames

    $microtrailersCreated = 0
    foreach ($game in $gameDatabase)
    {
        $extraMetadataDirectory = Set-GameDirectory $game
        $videoPath = Join-Path $extraMetadataDirectory -ChildPath "VideoTrailer.mp4"
        $videoMicrotrailerPath = Join-Path $extraMetadataDirectory -ChildPath "VideoMicrotrailer.mp4"
        if (!(Test-Path $videoPath))
        {
            continue
        }
        if (Test-Path $videoMicrotrailerPath)
        {
            continue
        }

        Get-VideoMicrotrailerFromVideo $videoPath $videoMicrotrailerPath
        if (Test-Path $videoMicrotrailerPath)
        {
            $microtrailersCreated++
        }
    }
    $PlayniteApi.Dialogs.ShowMessage(("Done.`n`nCreated {0} microtrailers from video trailers." -f $microtrailersCreated), "Extra Metadata Tools")
}

function Set-VideoManually
{
    param (
        [string]$videoQuality
    )
    
    $settings = Get-Settings
    
    # Set GameDatabase
    $gameDatabase = $PlayniteApi.MainView.SelectedGames
    if ($gameDatabase.count -ne 1)
    {
        $PlayniteApi.Dialogs.ShowMessage("More than one game is selected, please select only one game.", "Extra Metadata tools");
        return
    }

    switch ($videoQuality) {
        "max" {$videoName = "VideoTrailer.mp4"}
        "480" {$videoName = "VideoTrailer.mp4"}
        "micro" {$videoName = "VideoMicroTrailer.mp4"}
        default {$videoName = "VideoTrailer.mp4"}
    }
    $game = $PlayniteApi.MainView.SelectedGames[0]

    $extraMetadataDirectory = Set-GameDirectory $game
    $videoPath = Join-Path $extraMetadataDirectory -ChildPath $videoName
    $videoTempPath = $PlayniteApi.Dialogs.SelectFile("Video file|*")
    if ([string]::IsNullOrEmpty($videoTempPath))
    {
        return
    }
    
    if (Test-Path $videoPath)
    {
        try {
            Remove-Item $videoPath -Force
        } catch {
            $errorMessage = $_.Exception.Message
            $PlayniteApi.Dialogs.ShowMessage((("Game: {0}`nError deleting video: {1}`nError: {2}" + 
            "`n`nThe error could have been caused by the file being in use or currently playing on Playnite." +
            "`n`nThe game extra metadata directory will be opened, please delete the file manually when the video file is not in use" +
            "") -f $game.Name, $videoPath, $errorMessage),
            "Extra Metadata Tools")
            Start-Process $extraMetadataDirectory
            continue
        }
    }
    $isConversionNeeded = Get-IsConversionNeeded $videoTempPath
    if ($isConversionNeeded -eq $true)
    {
        $arguments = @("-y", "-i", $videoTempPath, "-c:v", "libx264", "-c:a", "mp3", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p", $videoPath)
        $__logger.Info(("Starting ffmpeg with arguments {0}" -f ($arguments -join ", ")))
        Start-Process -FilePath $settings.ffmpegPath -ArgumentList $arguments -Wait -WindowStyle Hidden
    }
    else
    {
        Move-Item $videoTempPath $videoPath -Force
        $__logger.Info(("Conversion is not needed for video and moved to {0}" -f $videoPath))
    }
    if (Test-Path $videoPath)
    {
        $PlayniteApi.Dialogs.ShowMessage("Finished.", "Extra Metadata tools")
    }
    else
    {
        $PlayniteApi.Dialogs.ShowMessage("Selected file could not be processed.", "Extra Metadata tools")
    }
}

function Remove-DownloadedVideos
{ 
    param (
        [string]$videoQuality
    )
    
    switch ($videoQuality) {
        "max" {$videoName = "VideoTrailer.mp4"}
        "480" {$videoName = "VideoTrailer.mp4"}
        "micro" {$videoName = "VideoMicroTrailer.mp4"}
        default {$videoName = "VideoTrailer.mp4"}
    }
    
    $gameDatabase = $PlayniteApi.MainView.SelectedGames
    $deletedVideos = 0
    foreach ($game in $gameDatabase)
    {
        $extraMetadataDirectory = Set-GameDirectory $game
        $videoPath = Join-Path $extraMetadataDirectory -ChildPath $videoName
        if (Test-Path $videoPath)
        {
            try {
                Remove-Item $videoPath -Force
                $deletedVideos++
            } catch {
                $errorMessage = $_.Exception.Message
                $PlayniteApi.Dialogs.ShowMessage((("Game: {0}`nError deleting video: {1}`nError: {2}" + 
                "`n`nThe error could have been caused by the file being in use or currently playing on Playnite." +
                "`n`nThe game extra metadata directory will be opened, please delete the file manually when the video file is not in use" +
                "") -f $game.Name, $videoPath, $errorMessage),
                "Extra Metadata Tools")
                Start-Process $extraMetadataDirectory
                continue
            }
        }
    }
    $PlayniteApi.Dialogs.ShowMessage(("Done.`n`nDeleted videos: {0}" -f $deletedVideos.ToString()), "Extra Metadata Tools")
}

function Remove-VideoTrailer
{
    Set-MandatorySettings
    Remove-DownloadedVideos "max"
}

function Remove-VideoMicrotrailer
{
    Set-MandatorySettings
    Remove-DownloadedVideos "micro"
}

function Set-VideoManuallyTrailer
{
    Set-MandatorySettings
    Set-VideoManually "max"
}

function Set-VideoManuallyMicrotrailer
{
    Set-MandatorySettings
    Set-VideoManually "micro"
}

function Get-SteamVideoSd
{
    Set-MandatorySettings
    Set-SteamVideo "480"
}

function Get-SteamVideoHd
{
    Set-MandatorySettings
    Set-SteamVideo "max"
}

function Get-SteamVideoMicro
{
    Set-MandatorySettings
    Set-SteamVideo "micro"
}