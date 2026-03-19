/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.Threading.Tasks;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux file picker using zenity or kdialog.
    /// When used with Avalonia, the Avalonia file picker will be preferred.
    /// This serves as a fallback.
    /// </summary>
    public class LinuxFilePickerService : IFilePickerService
    {
        public Task<string> PickFileAsync(string title, string[] filters)
        {
            return RunZenity($"--file-selection --title=\"{EscapeArg(title)}\"");
        }

        public Task<string> SaveFileAsync(string title, string defaultName, string[] filters)
        {
            string args = $"--file-selection --save --title=\"{EscapeArg(title)}\"";
            if (!string.IsNullOrEmpty(defaultName))
                args += $" --filename=\"{EscapeArg(defaultName)}\"";
            return RunZenity(args);
        }

        public Task<string> PickFolderAsync(string title)
        {
            return RunZenity($"--file-selection --directory --title=\"{EscapeArg(title)}\"");
        }

        private static async Task<string> RunZenity(string args)
        {
            try
            {
                var psi = new ProcessStartInfo("zenity", args)
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var process = Process.Start(psi);
                string result = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                if (process.ExitCode == 0)
                    return result?.Trim();
            }
            catch (Exception)
            {
                // zenity not available, try kdialog
                try
                {
                    string kdArgs = args.Replace("--file-selection", "--getopenfilename .")
                        .Replace("--save", "--getsavefilename .")
                        .Replace("--directory", "--getexistingdirectory .");

                    var psi = new ProcessStartInfo("kdialog", kdArgs)
                    {
                        RedirectStandardOutput = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };

                    using var process = Process.Start(psi);
                    string result = await process.StandardOutput.ReadToEndAsync();
                    await process.WaitForExitAsync();

                    if (process.ExitCode == 0)
                        return result?.Trim();
                }
                catch (Exception) { }
            }

            return null;
        }

        private static string EscapeArg(string arg)
        {
            return arg?.Replace("\"", "\\\"") ?? "";
        }
    }
}
