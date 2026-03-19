/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Avalonia;

namespace HTCommander.Desktop
{
    internal static class Program
    {
        public static IPlatformServices PlatformServices { get; private set; }

        [STAThread]
        static void Main(string[] args)
        {
            bool multiInstance = false;
            foreach (string arg in args)
            {
                if (string.Compare(arg, "-multiinstance", true) == 0) { multiInstance = true; }
            }

            if (!multiInstance)
            {
                string mutexName = "HtCommander-DB346020-4700-4026-A8D1-E05AE4F62A05";
                bool isNewInstance;
                using (Mutex mutex = new Mutex(true, mutexName, out isNewInstance))
                {
                    if (isNewInstance)
                    {
                        StartApp(args);
                    }
                }
            }
            else
            {
                StartApp(args);
            }
        }

        private static void StartApp(string[] args)
        {
            // Create platform services based on OS
            PlatformServices = CreatePlatformServices();

            // Initialize the global data broker with platform-specific settings
            DataBroker.Initialize(PlatformServices.Settings);

            // Wire up app callbacks for Core code
            AppCallbacks.BlockBoxEvent = (msg) => Debug(msg);
            AppCallbacks.DebugLog = Debug;

            // Set up unhandled exception handlers
            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            {
                Debug("--- HTCommander Unhandled Exception ---\r\n" + DateTime.Now +
                      "\r\nException: " + ((Exception)e.ExceptionObject).ToString());
            };
            TaskScheduler.UnobservedTaskException += (s, e) =>
            {
                Debug("--- HTCommander Unhandled Task Exception ---\r\n" + DateTime.Now +
                      "\r\nException:\r\n" + e.Exception.ToString());
                e.SetObserved();
            };

            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }

        public static AppBuilder BuildAvaloniaApp()
            => AppBuilder.Configure<App>()
                .UsePlatformDetect()
                .WithInterFont()
                .LogToTrace();

        private static IPlatformServices CreatePlatformServices()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                // Use reflection to avoid compile-time dependency on Windows-only project on Linux
                var asm = System.Reflection.Assembly.Load("HTCommander.Platform.Windows");
                var type = asm.GetType("HTCommander.Platform.Windows.WinPlatformServices");
                return (IPlatformServices)Activator.CreateInstance(type, "HTCommander");
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                var asm = System.Reflection.Assembly.Load("HTCommander.Platform.Linux");
                var type = asm.GetType("HTCommander.Platform.Linux.LinuxPlatformServices");
                return (IPlatformServices)Activator.CreateInstance(type);
            }
            else
            {
                throw new PlatformNotSupportedException("This platform is not currently supported.");
            }
        }

        public static void Debug(string msg)
        {
            try { File.AppendAllText("debug.log", msg + "\r\n"); } catch (Exception) { }
        }
    }
}
