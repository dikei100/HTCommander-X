/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System.Threading.Tasks;

namespace HTCommander
{
    /// <summary>
    /// Abstracts file open/save dialogs.
    /// Desktop: native dialogs, Android: Storage Access Framework (SAF).
    /// </summary>
    public interface IFilePickerService
    {
        Task<string> PickFileAsync(string title, string[] filters);
        Task<string> SaveFileAsync(string title, string defaultName, string[] filters);
        Task<string> PickFolderAsync(string title);
    }
}
