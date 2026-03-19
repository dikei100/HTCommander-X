/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows file picker using WinForms dialogs.
    /// </summary>
    public class WinFilePickerService : IFilePickerService
    {
        public Task<string> PickFileAsync(string title, string[] filters)
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Title = title;
                if (filters != null && filters.Length > 0)
                    dialog.Filter = string.Join("|", filters);
                return Task.FromResult(dialog.ShowDialog() == DialogResult.OK ? dialog.FileName : null);
            }
        }

        public Task<string> SaveFileAsync(string title, string defaultName, string[] filters)
        {
            using (var dialog = new SaveFileDialog())
            {
                dialog.Title = title;
                dialog.FileName = defaultName;
                if (filters != null && filters.Length > 0)
                    dialog.Filter = string.Join("|", filters);
                return Task.FromResult(dialog.ShowDialog() == DialogResult.OK ? dialog.FileName : null);
            }
        }

        public Task<string> PickFolderAsync(string title)
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = title;
                return Task.FromResult(dialog.ShowDialog() == DialogResult.OK ? dialog.SelectedPath : null);
            }
        }
    }
}
