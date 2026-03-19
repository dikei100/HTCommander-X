/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Radio connection state enumeration.
    /// </summary>
    public enum RadioState : int
    {
        Disconnected = 1, Connecting = 2, Connected = 3, MultiRadioSelect = 4,
        UnableToConnect = 5, BluetoothNotAvailable = 6, NotRadioFound = 7, AccessDenied = 8
    }
}
