/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Mapsui;
using Mapsui.Extensions;
using Mapsui.Layers;
using Mapsui.Projections;
using Mapsui.Styles;
using Mapsui.Tiling;

namespace HTCommander.Desktop.TabControls
{
    public partial class MapTabControl : UserControl
    {
        private DataBrokerClient broker;
        private WritableLayer stationsLayer;
        private WritableLayer positionsLayer;

        public MapTabControl()
        {
            InitializeComponent();
            InitializeMap();

            broker = new DataBrokerClient();
            broker.Subscribe(DataBroker.AllDevices, "Position", OnPositionChanged);
            broker.Subscribe(1, "AprsFrame", OnAprsFrame);
        }

        private void InitializeMap()
        {
            var map = MapControl.Map;

            // Add OpenStreetMap tile layer
            map.Layers.Add(OpenStreetMap.CreateTileLayer());

            // Add writable layers for markers
            stationsLayer = new WritableLayer { Name = "Stations", Style = null };
            positionsLayer = new WritableLayer { Name = "Positions", Style = null };
            map.Layers.Add(stationsLayer);
            map.Layers.Add(positionsLayer);

            // Default view: center of continental US
            var center = SphericalMercator.FromLonLat(-98.5795, 39.8283);
            map.Navigator.CenterOnAndZoomTo(new MPoint(center.x, center.y), map.Navigator.Resolutions[5]);
        }

        private void OnPositionChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                // Extract lat/lon from position data via reflection (RadioPosition is in Core)
                if (data == null) return;
                var type = data.GetType();
                var latField = type.GetField("latitude");
                var lonField = type.GetField("longitude");
                if (latField == null || lonField == null) return;

                double lat = Convert.ToDouble(latField.GetValue(data));
                double lon = Convert.ToDouble(lonField.GetValue(data));
                if (lat == 0 && lon == 0) return;

                var coords = SphericalMercator.FromLonLat(lon, lat);
                var point = new MPoint(coords.x, coords.y);
                var feature = new PointFeature(point);
                feature.Styles.Add(new SymbolStyle
                {
                    SymbolScale = 0.5,
                    Fill = new Brush(Color.FromArgb(255, 0, 120, 215))
                });

                positionsLayer.Clear();
                positionsLayer.Add(feature);
                MapControl.Map.Navigator.CenterOn(point);
                MapControl.Refresh();
            });
        }

        private void OnAprsFrame(int deviceId, string name, object data)
        {
            // TODO: Parse APRS position data and add markers to stationsLayer
        }

        private void CenterButton_Click(object sender, RoutedEventArgs e)
        {
            var extent = positionsLayer.Extent;
            if (extent != null)
            {
                MapControl.Map.Navigator.CenterOn(extent.Centroid);
                MapControl.Refresh();
            }
        }

        private void ShowAirplanes_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Toggle airplane layer visibility
        }

        private void ShowAprs_Click(object sender, RoutedEventArgs e)
        {
            stationsLayer.IsMapInfoLayer = ShowAprsCheck.IsChecked == true;
            MapControl.Refresh();
        }
    }
}
