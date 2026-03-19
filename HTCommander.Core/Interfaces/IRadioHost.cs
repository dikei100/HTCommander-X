/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Interface for the radio host that Bluetooth transports call back into.
    /// Allows platform transport implementations to communicate with Radio without
    /// a circular dependency.
    /// </summary>
    public interface IRadioHost
    {
        string MacAddress { get; }
        void Debug(string msg);
        void Disconnect(string msg, RadioState newState);
    }
}
