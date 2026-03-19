/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using Mapsui;
using Mapsui.Layers;
using Mapsui.Projections;
using Mapsui.Styles;

namespace HTCommander.Desktop.Controls
{
    /// <summary>
    /// Creates Mapsui features for airplane markers on the map.
    /// Replaces GMap.NET AirplaneMarker with Mapsui-compatible rendering.
    /// </summary>
    public static class AirplaneMapFeature
    {
        /// <summary>
        /// Create a map feature for an airplane at the given position.
        /// </summary>
        /// <param name="latitude">Latitude in degrees</param>
        /// <param name="longitude">Longitude in degrees</param>
        /// <param name="track">Heading in degrees (0=north, clockwise)</param>
        /// <param name="altitude">Altitude in feet (-1 = unknown)</param>
        /// <param name="callsign">Aircraft callsign/identifier</param>
        /// <returns>A PointFeature for the airplane</returns>
        public static PointFeature Create(double latitude, double longitude, float track, int altitude, string callsign)
        {
            var coords = SphericalMercator.FromLonLat(longitude, latitude);
            var point = new MPoint(coords.x, coords.y);
            var feature = new PointFeature(point);

            // Color based on altitude
            Color color = GetAltitudeColor(altitude);

            feature.Styles.Add(new SymbolStyle
            {
                SymbolScale = 0.4,
                SymbolType = SymbolType.Triangle,
                SymbolRotation = track,
                Fill = new Brush(color),
                Outline = new Pen(Color.Black, 1)
            });

            // Add callsign label
            if (!string.IsNullOrEmpty(callsign))
            {
                feature.Styles.Add(new LabelStyle
                {
                    Text = callsign,
                    Font = new Font { Size = 10 },
                    ForeColor = Color.Black,
                    BackColor = new Brush(new Color(255, 255, 255, 180)),
                    Offset = new Offset(0, -20),
                    HorizontalAlignment = LabelStyle.HorizontalAlignmentEnum.Center
                });
            }

            return feature;
        }

        /// <summary>
        /// Get color based on altitude (matches original WinForms implementation).
        /// </summary>
        private static Color GetAltitudeColor(int altitude)
        {
            if (altitude < 0) return new Color(128, 128, 128); // Unknown = gray
            if (altitude < 1000) return new Color(0, 128, 0); // Ground level = green
            if (altitude < 5000) return new Color(0, 200, 0); // Low = light green
            if (altitude < 10000) return new Color(255, 200, 0); // Medium = yellow
            if (altitude < 20000) return new Color(255, 128, 0); // High = orange
            if (altitude < 35000) return new Color(255, 0, 0); // Very high = red
            return new Color(128, 0, 128); // Extreme = purple
        }
    }
}
