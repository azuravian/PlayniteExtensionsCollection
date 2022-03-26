﻿using InstallationStatusUpdater.Models;
using Playnite.SDK;
using Playnite.SDK.Events;
using Playnite.SDK.Models;
using Playnite.SDK.Plugins;
using PlayniteUtilitiesCommon;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace InstallationStatusUpdater
{
    public class InstallationStatusUpdater : GenericPlugin
    {
        private static readonly ILogger logger = LogManager.GetLogger();
        private static readonly Regex driveRegex = new Regex(@"^\w:\\", RegexOptions.Compiled);
        private static readonly Regex installDirVarRegex = new Regex(@"{InstallDir}", RegexOptions.Compiled);
        private List<FileSystemWatcher> dirWatchers = new List<FileSystemWatcher>();
        private DispatcherTimer timer;
        private Window mainWindow;
        private WindowInteropHelper windowInterop;
        private IntPtr mainWindowHandle;
        private HwndSource source;

        private InstallationStatusUpdaterSettingsViewModel settings { get; set; }

        public override Guid Id { get; } = Guid.Parse("ed9c467f-5ab5-478f-a09f-936146188ad0");

        public InstallationStatusUpdater(IPlayniteAPI api) : base(api)
        {
            settings = new InstallationStatusUpdaterSettingsViewModel(this, PlayniteApi);
            Properties = new GenericPluginProperties
            {
                HasSettings = true
            };

            SetDirWatchers();
            timer = new DispatcherTimer();
            timer.Interval = TimeSpan.FromMilliseconds(5000);
            timer.Tick += new EventHandler(Timer_Tick);
        }

        public override void OnApplicationStarted(OnApplicationStartedEventArgs args)
        {
            mainWindow = Application.Current.MainWindow;
            if (mainWindow != null)
            {
                windowInterop = new WindowInteropHelper(mainWindow);
                mainWindowHandle = windowInterop.Handle;
                source = HwndSource.FromHwnd(mainWindowHandle);
                source.AddHook(GlobalHotkeyCallback);
            }
            else
            {
                logger.Error("Could not find Playnite main window.");
            }

            if (settings.Settings.UpdateOnStartup == true)
            {
                DetectInstallationStatus(false);
            }
        }

        private const int WM_DEVICECHANGE = 0x0219;                 // device change event
        private const int DBT_DEVICEARRIVAL = 0x8000;               // system detected a new device
        private const int DBT_DEVICEREMOVEPENDING = 0x8003;         // about to remove, still available
        private const int DBT_DEVICEREMOVECOMPLETE = 0x8004;        // device is gone
        private IntPtr GlobalHotkeyCallback(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (!settings.Settings.UpdateStatusOnUsbChanges)
            {
                return IntPtr.Zero;
            }

            if (msg == WM_DEVICECHANGE)
            {
                switch (wParam.ToInt32())
                {
                    //case WM_DEVICECHANGE:
                    //    break;
                    case DBT_DEVICEARRIVAL:
                        logger.Debug("Started timer from DBT_DEVICEARRIVAL event");
                        timer.Stop();
                        timer.Start();
                        handled = true;
                        break;
                    //case DBT_DEVICEREMOVEPENDING:
                    //    break;
                    case DBT_DEVICEREMOVECOMPLETE:
                        logger.Debug("Started timer from DBT_DEVICEREMOVECOMPLETE event");
                        timer.Stop();
                        timer.Start();
                        handled = true;
                        break;
                    default:
                        break;
                }
            }

            return IntPtr.Zero;
        }

        private void Timer_Tick(object sender, EventArgs e)
        {
            // Timer is used to ensure multiple executions are not triggered
            // when there are multiple changes in bulk
            timer.Stop();
            logger.Debug("Starting detection by timer");
            DetectInstallationStatus(false);
        }

        public void SetDirWatchers()
        {
            if (dirWatchers.Count > 0)
            {
                foreach (FileSystemWatcher watcher in dirWatchers)
                {
                    watcher.Dispose();
                }
            }

            dirWatchers = new List<FileSystemWatcher>();
            if (!settings.Settings.UpdateStatusOnDirChanges || settings.Settings.DetectionDirectories.Count == 0)
            {
                return;
            }

            foreach (SelectableDirectory dir in settings.Settings.DetectionDirectories)
            {
                if (!dir.Enabled)
                {
                    continue;
                }

                if (!Directory.Exists(dir.DirectoryPath))
                {
                    logger.Warn($"Directory {dir.DirectoryPath} for watcher doesn't exist");
                    continue;
                }

                var watcher = new FileSystemWatcher(dir.DirectoryPath)
                {
                    NotifyFilter = NotifyFilters.Attributes
                                 | NotifyFilters.CreationTime
                                 | NotifyFilters.DirectoryName
                                 | NotifyFilters.FileName
                                 | NotifyFilters.LastWrite
                                 | NotifyFilters.Size,

                    Filter = "*.*"
                };

                watcher.Changed += OnChanged;
                watcher.Created += OnCreated;
                watcher.Deleted += OnDeleted;
                watcher.Renamed += OnRenamed;

                watcher.IncludeSubdirectories = dir.ScanSubDirs;
                watcher.EnableRaisingEvents = true;
                dirWatchers.Add(watcher);
            }
        }

        private void OnChanged(object sender, FileSystemEventArgs e)
        {
            WatcherEventHandler(e.FullPath);
        }

        private void OnCreated(object sender, FileSystemEventArgs e)
        {
            WatcherEventHandler(e.FullPath);
        }

        private void OnDeleted(object sender, FileSystemEventArgs e)
        {
            WatcherEventHandler(e.FullPath);
        }

        private void OnRenamed(object sender, RenamedEventArgs e)
        {
            WatcherEventHandler(e.FullPath);
        }

        public void WatcherEventHandler(string invokerPath)
        {
            logger.Info(string.Format("Watcher invoked by path {0}", invokerPath));
            timer.Stop();
            timer.Start();
        }

        public override void OnLibraryUpdated(OnLibraryUpdatedEventArgs args)
        {
            if (settings.Settings.UpdateOnLibraryUpdate == true)
            {
                DetectInstallationStatus(false);
            }
            if (settings.Settings.UpdateLocTagsOnLibUpdate == true)
            {
                UpdateInstallDirTags();
            }
            SetDirWatchers();
        }

        public override ISettings GetSettings(bool firstRunSettings)
        {
            return settings;
        }

        public override UserControl GetSettingsView(bool firstRunSettings)
        {
            return new InstallationStatusUpdaterSettingsView();
        }

        public override IEnumerable<MainMenuItem> GetMainMenuItems(GetMainMenuItemsArgs args)
        {

            return new List<MainMenuItem>
            {
                new MainMenuItem
                {
                    Description = ResourceProvider.GetString("LOCInstallation_Status_Updater_MenuItemStatusUpdaterDescription"),
                    MenuSection = "@Installation Status Updater",
                    Action = a => {
                        DetectInstallationStatus(true);
                    }
                },
                new MainMenuItem
                {
                    Description = ResourceProvider.GetString("LOCInstallation_Status_Updater_MenuAddIgnoreFeatureDescription"),
                    MenuSection = "@Installation Status Updater",
                    Action = a => {
                        AddIgnoreFeature();
                    }
                },
                new MainMenuItem
                {
                    Description = ResourceProvider.GetString("LOCInstallation_Status_Updater_MenuRemoveIgnoreFeatureDescription"),
                    MenuSection = "@Installation Status Updater",
                    Action = a => {
                        RemoveIgnoreFeature();
                    }
                },
                new MainMenuItem
                {
                    Description = ResourceProvider.GetString("LOCInstallation_Status_Updater_MenuUpdateDriveInstallTagDescription"),
                    MenuSection = "@Installation Status Updater",
                    Action = a => {
                        UpdateInstallDirTags();
                        PlayniteApi.Dialogs.ShowMessage(ResourceProvider.GetString("LOCInstallation_Status_Updater_StatusUpdaterUpdatingTagsFinishMessage"), "Installation Status Updater");
                    }
                }
            };
        }

        public override IEnumerable<InstallController> GetInstallActions(GetInstallActionsArgs args)
        {
            if (!settings.Settings.EnableInstallButtonAction || SkipGame(args.Game))
            {
                yield break;
            }

            yield return new StatusUpdaterInstallController(args.Game, IsGameInstalled(args.Game));
        }

        public static bool DetectIsRomInstalled(GameRom rom, string installDirectory)
        {
            if (string.IsNullOrEmpty(rom.Path))
            {
                return false;
            }

            if (driveRegex.IsMatch(rom.Path))
            {
                return File.Exists(rom.Path);
            }

            string romFullPath = rom.Path;
            if (!string.IsNullOrEmpty(installDirectory))
            {
                if (installDirVarRegex.IsMatch(rom.Path))
                {
                    romFullPath = rom.Path.Replace("{InstallDir}", installDirectory);
                }
                else
                {
                    romFullPath = Path.Combine(installDirectory, rom.Path);
                }
            }

            return File.Exists(romFullPath);
        }

        public bool DetectIsRomInstalled(Game game, string installDirectory)
        {
            if (game.Roms == null)
            {
                return false;
            }
            if (game.Roms.Count == 0)
            {
                return false;
            }
            if (game.Roms.Count > 1 && settings.Settings.UseOnlyFirstRomDetection == false)
            {
                foreach (GameRom rom in game.Roms)
                {
                    if (DetectIsRomInstalled(rom, installDirectory))
                    {
                        return true;
                    }
                }
            }
            else
            {
                if (game.Platforms != null && game.Platforms.Any(x => x.Name == "PC (Windows)"))
                {
                    return false;
                }
                return DetectIsRomInstalled(game.Roms[0], installDirectory);
            }
            return false;
        }

        public static bool DetectIsFileActionInstalled(GameAction gameAction, string installDirectory)
        {
            if (string.IsNullOrEmpty(gameAction.Path))
            {
                return false;
            }

            //Games added as Microsoft Store Application use explorer and arguments to launch the game
            if (gameAction.Path.Equals("explorer.exe", StringComparison.OrdinalIgnoreCase))
            {
                //If directory has been set, it can be used to detect if game is installed or not
                if (!string.IsNullOrEmpty(installDirectory))
                {
                    return Directory.Exists(installDirectory);
                }
                else
                {
                    return true;
                }
            }

            if (driveRegex.IsMatch(gameAction.Path))
            {
                return File.Exists(gameAction.Path);
            }

            var fullfilePath = gameAction.Path;
            if (!string.IsNullOrEmpty(installDirectory))
            {
                if (installDirVarRegex.IsMatch(gameAction.Path))
                {
                    fullfilePath = gameAction.Path.Replace("{InstallDir}", installDirectory);
                }
                else
                {
                    fullfilePath = Path.Combine(installDirectory, gameAction.Path);
                }
            }

            return File.Exists(fullfilePath);
        }

        public bool DetectIsAnyActionInstalled(Game game, string installDirectory)
        {
            foreach (GameAction gameAction in game.GameActions)
            {
                if (gameAction.IsPlayAction == false && settings.Settings.OnlyUsePlayActionGameActions == true)
                {
                    continue;
                }
                
                if (gameAction.Type == GameActionType.URL)
                {
                    if (settings.Settings.UrlActionIsInstalled == true)
                    {
                        return true;
                    }
                }
                else if (gameAction.Type == GameActionType.Script)
                {
                    if (settings.Settings.ScriptActionIsInstalled == true)
                    {
                        return true;
                    }
                }
                else if (gameAction.Type == GameActionType.File)
                {
                    if (DetectIsFileActionInstalled(gameAction, installDirectory))
                    {
                        return true;
                    }
                }
            }

            return false;
        }

        public void DetectInstallationStatus(bool showResultsDialog)
        {
            var gameCollection = PlayniteApi.Database.Games;
            int markedInstalled = 0;
            int markedUninstalled = 0;
            foreach (Game game in gameCollection)
            {
                if (SkipGame(game))
                {
                    continue;
                }

                var isInstalled = IsGameInstalled(game);

                if (game.IsInstalled == true && isInstalled == false)
                {
                    game.IsInstalled = false;
                    PlayniteApi.Database.Games.Update(game);
                    markedUninstalled++;
                    logger.Info(string.Format("Game: {0} marked as uninstalled", game.Name));
                }
                else if (game.IsInstalled == false && isInstalled == true)
                {
                    game.IsInstalled = true;
                    PlayniteApi.Database.Games.Update(game);
                    markedInstalled++;
                    logger.Info(string.Format("Game: {0} marked as installed", game.Name));
                }
            }

            if (showResultsDialog)
            {
                PlayniteApi.Dialogs.ShowMessage(
                    string.Format(ResourceProvider.GetString("LOCInstallation_Status_Updater_StatusUpdaterResultsMessage"), 
                    markedUninstalled.ToString(), 
                    markedInstalled.ToString()), "Installation Status Updater"
                );
            }
            else if (markedInstalled > 0 || markedUninstalled > 0)
            {
                if (File.Exists(Path.Combine(GetPluginUserDataPath(), "DisableNotifications")))
                {
                    logger.Info("Super secret \"DisableNotifications\" file detected. Notification not added.");
                    return;
                }
                
                PlayniteApi.Notifications.Add(new NotificationMessage(new Guid().ToString(),
                    string.Format(ResourceProvider.GetString("LOCInstallation_Status_Updater_NotificationMessageMarkedInstalledResults"), markedInstalled, markedUninstalled),
                    NotificationType.Info));
            }
        }

        public bool SkipGame(Game game)
        {
            if (game.IncludeLibraryPluginAction == true && settings.Settings.SkipHandledByPlugin == true && game.PluginId != Guid.Empty)
            {
                return true;
            }

            if (game.Features != null && game.Features.Any(x => x.Name == "[Status Updater] Ignore"))
            {
                return true;
            }

            if (game.Platforms !=null && game.Platforms.Any(x => x.Name != "PC (Windows)"))
            {
                return true;
            }
            
            return false;
        }

        public bool IsGameInstalled(Game game)
        {
            var isInstalled = false;
            var installDirectory = string.Empty;
            if (!string.IsNullOrEmpty(game.InstallDirectory))
            {
                installDirectory = game.InstallDirectory.ToLower();
            }

            if (game.GameActions != null && game.GameActions.Count > 0)
            {
                isInstalled = DetectIsAnyActionInstalled(game, installDirectory);
            }

            if (isInstalled == false)
            {
                isInstalled = DetectIsRomInstalled(game, installDirectory);
            }

            return isInstalled;
        }

        public void AddIgnoreFeature()
        {
            var featureAddedCount = PlayniteUtilities.AddTagToGames(PlayniteApi, PlayniteApi.MainView.SelectedGames.Distinct(), "[Status Updater] Ignore"); ;
            PlayniteApi.Dialogs.ShowMessage(
                string.Format(ResourceProvider.GetString("LOCInstallation_Status_Updater_StatusUpdaterAddIgnoreFeatureMessage"),
                featureAddedCount.ToString()), "Installation Status Updater"
            );
        }

        public void RemoveIgnoreFeature()
        {
            var featureRemovedCount = PlayniteUtilities.RemoveTagFromGames(PlayniteApi, PlayniteApi.MainView.SelectedGames.Distinct(), "[Status Updater] Ignore");
            PlayniteApi.Dialogs.ShowMessage(
                string.Format(ResourceProvider.GetString("LOCInstallation_Status_Updater_StatusUpdaterRemoveIgnoreFeatureMessage"), 
                featureRemovedCount.ToString()), "Installation Status Updater"
            );
        }

        public void UpdateInstallDirTags()
        {
            var progRes = PlayniteApi.Dialogs.ActivateGlobalProgress((a) =>
            {
                var gameDatabase = PlayniteApi.Database.Games;
                var driveTagPrefix = "[Install Drive]";
                foreach (Game game in gameDatabase)
                {
                    string tagName = string.Empty;
                    if (!string.IsNullOrEmpty(game.InstallDirectory) && game.IsInstalled == true)
                    {
                        FileInfo s = new FileInfo(game.InstallDirectory);
                        string sourceDrive = Path.GetPathRoot(s.FullName).ToUpper();
                        tagName = string.Format("{0} {1}", driveTagPrefix, sourceDrive);
                        Tag driveTag = PlayniteApi.Database.Tags.Add(tagName);
                        PlayniteUtilities.AddTagToGame(PlayniteApi, game, driveTag);
                    }

                    if (game.Tags == null)
                    {
                        continue;
                    }

                    foreach (Tag tag in game.Tags.Where(x => x.Name.StartsWith(driveTagPrefix)))
                    {
                        if (!tagName.IsNullOrEmpty())
                        {
                            if (tag.Name != tagName)
                            {
                                PlayniteUtilities.RemoveTagFromGame(PlayniteApi, game, tag);
                            }
                        }
                        else
                        {
                            PlayniteUtilities.RemoveTagFromGame(PlayniteApi, game, tag);
                        }
                    }
                }
            }, new GlobalProgressOptions(ResourceProvider.GetString("LOCInstallation_Status_Updater_StatusUpdaterUpdatingTagsProgressMessage")));
        }

    }
}