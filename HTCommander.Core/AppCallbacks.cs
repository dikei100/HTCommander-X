/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Static callbacks that the host application (WinForms, Avalonia, etc.) registers.
    /// Allows Core code to call back into the application without a direct dependency.
    /// </summary>
    public static class AppCallbacks
    {
        /// <summary>
        /// Called for black-box event logging. Host app should register its implementation.
        /// </summary>
        public static Action<string> BlockBoxEvent { get; set; } = (msg) => { };

        /// <summary>
        /// Called for debug logging. Host app should register its implementation.
        /// </summary>
        public static Action<string> DebugLog { get; set; } = (msg) => { };
    }
}
