/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Platform-agnostic interface for BBS instances.
    /// The concrete implementation (BBS) lives in the platform-specific project
    /// because it depends on System.Windows.Forms.
    /// </summary>
    public interface IBBS : IDisposable
    {
        bool Enabled { get; set; }
        int DeviceId { get; }
        void ClearStats();
    }

    /// <summary>
    /// Factory interface for creating BBS instances.
    /// Registered by the platform-specific layer at startup.
    /// </summary>
    public interface IBBSFactory
    {
        IBBS Create(int deviceId);
    }
}
