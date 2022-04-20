﻿using Playnite.SDK;
using PluginsCommon;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;

namespace JastUsaLibrary
{
    public class JastUsaLibraryClient : LibraryClient
    {
        public override bool IsInstalled => true;
        public override string Icon => Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), @"icon.png");

        public override void Open()
        {
            ProcessStarter.StartUrl(@"https://jastusa.com/");
        }
    }
}