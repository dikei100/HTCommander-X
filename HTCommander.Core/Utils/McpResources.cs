/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// MCP resource definitions for HTCommander.
// Resources provide read-only state about the radio and application.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Text.Json;

namespace HTCommander
{
    /// <summary>
    /// Implements MCP resources for exposing radio and application state.
    /// All resources are read-only and backed by DataBroker values.
    /// </summary>
    public class McpResources
    {
        private readonly DataBrokerClient broker;

        public McpResources(DataBrokerClient broker)
        {
            this.broker = broker;
        }

        /// <summary>
        /// Returns all resource definitions for the resources/list response.
        /// Dynamically includes per-radio resources based on connected radios.
        /// </summary>
        public List<McpResourceDefinition> GetResourceDefinitions()
        {
            var resources = new List<McpResourceDefinition>();

            // Static app-level resources
            resources.Add(new McpResourceDefinition
            {
                Uri = "htcommander://app/settings",
                Name = "Application Settings",
                Description = "All application settings stored on device 0",
                MimeType = "application/json"
            });

            resources.Add(new McpResourceDefinition
            {
                Uri = "htcommander://app/logs",
                Name = "Application Logs",
                Description = "Recent application log entries (up to 500)",
                MimeType = "text/plain"
            });

            // Dynamic per-radio resources
            var radioIds = GetConnectedRadioIds();
            foreach (int radioId in radioIds)
            {
                resources.Add(new McpResourceDefinition
                {
                    Uri = "htcommander://radio/" + radioId + "/info",
                    Name = "Radio " + radioId + " Info",
                    Description = "Device information for radio " + radioId,
                    MimeType = "application/json"
                });

                resources.Add(new McpResourceDefinition
                {
                    Uri = "htcommander://radio/" + radioId + "/settings",
                    Name = "Radio " + radioId + " Settings",
                    Description = "Current settings for radio " + radioId,
                    MimeType = "application/json"
                });

                resources.Add(new McpResourceDefinition
                {
                    Uri = "htcommander://radio/" + radioId + "/channels",
                    Name = "Radio " + radioId + " Channels",
                    Description = "Channel list for radio " + radioId,
                    MimeType = "application/json"
                });

                resources.Add(new McpResourceDefinition
                {
                    Uri = "htcommander://radio/" + radioId + "/status",
                    Name = "Radio " + radioId + " Status",
                    Description = "Composite status (battery, volume, state, audio) for radio " + radioId,
                    MimeType = "application/json"
                });
            }

            return resources;
        }

        /// <summary>
        /// Reads a resource by URI and returns the MCP result.
        /// </summary>
        public object ReadResource(string uri)
        {
            // Parse URI: htcommander://app/settings, htcommander://radio/{id}/info, etc.
            if (uri.StartsWith("htcommander://app/"))
            {
                string path = uri.Substring("htcommander://app/".Length);
                switch (path)
                {
                    case "settings": return ReadAppSettings();
                    case "logs": return ReadAppLogs();
                }
            }
            else if (uri.StartsWith("htcommander://radio/"))
            {
                // Parse: htcommander://radio/{deviceId}/{resource}
                string remainder = uri.Substring("htcommander://radio/".Length);
                int slashIdx = remainder.IndexOf('/');
                if (slashIdx > 0)
                {
                    string deviceIdStr = remainder.Substring(0, slashIdx);
                    string resource = remainder.Substring(slashIdx + 1);
                    if (int.TryParse(deviceIdStr, out int deviceId))
                    {
                        switch (resource)
                        {
                            case "info": return ReadRadioInfo(deviceId);
                            case "settings": return ReadRadioSettings(deviceId);
                            case "channels": return ReadRadioChannels(deviceId);
                            case "status": return ReadRadioStatus(deviceId);
                        }
                    }
                }
            }

            return new
            {
                contents = new[] { new McpResourceContent { Uri = uri, Text = "Resource not found: " + uri } }
            };
        }

        private object ReadAppSettings()
        {
            var values = DataBroker.GetDeviceValues(0);
            var result = new Dictionary<string, string>();
            foreach (var kvp in values)
            {
                try
                {
                    if (kvp.Value is byte[])
                        result[kvp.Key] = "[binary data]";
                    else if (kvp.Value != null)
                        result[kvp.Key] = kvp.Value.ToString();
                    else
                        result[kvp.Key] = "null";
                }
                catch
                {
                    result[kvp.Key] = kvp.Value?.GetType().Name ?? "null";
                }
            }

            string json = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
            return new
            {
                contents = new[] { new McpResourceContent { Uri = "htcommander://app/settings", MimeType = "application/json", Text = json } }
            };
        }

        private object ReadAppLogs()
        {
            var logStore = DataBroker.GetDataHandler<LogStore>("LogStore");
            string text;
            if (logStore != null)
            {
                var logs = logStore.GetLogs();
                var lines = new List<string>();
                foreach (var entry in logs)
                {
                    lines.Add(entry.ToString());
                }
                text = string.Join("\n", lines);
            }
            else
            {
                text = "LogStore not available";
            }

            return new
            {
                contents = new[] { new McpResourceContent { Uri = "htcommander://app/logs", MimeType = "text/plain", Text = text } }
            };
        }

        private object ReadRadioInfo(int deviceId)
        {
            var info = broker.GetValue<object>(deviceId, "Info", null);
            string json;
            if (info != null)
            {
                var result = new Dictionary<string, object>();
                foreach (var field in info.GetType().GetFields())
                {
                    if (field.Name == "raw") continue;
                    result[field.Name] = field.GetValue(info);
                }
                json = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
            }
            else
            {
                json = "{\"error\": \"No info available\"}";
            }

            return new
            {
                contents = new[] { new McpResourceContent { Uri = "htcommander://radio/" + deviceId + "/info", MimeType = "application/json", Text = json } }
            };
        }

        private object ReadRadioSettings(int deviceId)
        {
            var settings = broker.GetValue<object>(deviceId, "Settings", null);
            string json;
            if (settings != null)
            {
                var result = new Dictionary<string, object>();
                foreach (var field in settings.GetType().GetFields())
                {
                    if (field.Name == "raw") continue;
                    result[field.Name] = field.GetValue(settings);
                }
                json = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
            }
            else
            {
                json = "{\"error\": \"No settings available\"}";
            }

            return new
            {
                contents = new[] { new McpResourceContent { Uri = "htcommander://radio/" + deviceId + "/settings", MimeType = "application/json", Text = json } }
            };
        }

        private object ReadRadioChannels(int deviceId)
        {
            var channels = broker.GetValue<object>(deviceId, "Channels", null);
            string json;
            if (channels is RadioChannelInfo[] channelArray)
            {
                var channelList = new List<Dictionary<string, object>>();
                for (int i = 0; i < channelArray.Length; i++)
                {
                    var ch = channelArray[i];
                    if (ch == null) continue;
                    channelList.Add(new Dictionary<string, object>
                    {
                        ["index"] = i,
                        ["name"] = ch.name_str,
                        ["rx_freq"] = ch.rx_freq,
                        ["rx_freq_mhz"] = ch.rx_freq / 1000000.0,
                        ["tx_freq"] = ch.tx_freq,
                        ["tx_freq_mhz"] = ch.tx_freq / 1000000.0,
                        ["bandwidth"] = ch.bandwidth == 0 ? "narrow" : "wide",
                        ["tx_at_max_power"] = ch.tx_at_max_power
                    });
                }
                json = JsonSerializer.Serialize(channelList, new JsonSerializerOptions { WriteIndented = true });
            }
            else
            {
                json = "{\"error\": \"No channel data available\"}";
            }

            return new
            {
                contents = new[] { new McpResourceContent { Uri = "htcommander://radio/" + deviceId + "/channels", MimeType = "application/json", Text = json } }
            };
        }

        private object ReadRadioStatus(int deviceId)
        {
            var status = new Dictionary<string, object>
            {
                ["state"] = broker.GetValue<string>(deviceId, "State", "Unknown"),
                ["battery_percent"] = broker.GetValue<int>(deviceId, "BatteryAsPercentage", -1),
                ["volume"] = broker.GetValue<int>(deviceId, "Volume", -1),
                ["audio_state"] = broker.GetValue<object>(deviceId, "AudioState", null)?.ToString() ?? "Unknown",
                ["friendly_name"] = broker.GetValue<string>(deviceId, "FriendlyName", "")
            };

            string json = JsonSerializer.Serialize(status, new JsonSerializerOptions { WriteIndented = true });
            return new
            {
                contents = new[] { new McpResourceContent { Uri = "htcommander://radio/" + deviceId + "/status", MimeType = "application/json", Text = json } }
            };
        }

        private List<int> GetConnectedRadioIds()
        {
            var ids = new List<int>();
            var radios = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (radios is IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var prop = item.GetType().GetProperty("DeviceId");
                    if (prop != null)
                    {
                        object val = prop.GetValue(item);
                        if (val is int id && id > 0) ids.Add(id);
                    }
                }
            }
            return ids;
        }
    }
}
