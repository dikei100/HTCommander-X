/// Represents a decoded GPS position fix, combining data from NMEA sentences
/// (RMC and GGA). Dispatched on the Data Broker as device 1, key "GpsData".
///
/// Port of HTCommander.Core/Gps/GpsData.cs
class GpsData {
  /// Latitude in decimal degrees. Negative values indicate South.
  double latitude = 0;

  /// Longitude in decimal degrees. Negative values indicate West.
  double longitude = 0;

  /// Altitude above mean sea level in metres (from GGA).
  double altitude = 0;

  /// Speed over ground in knots (from RMC).
  double speed = 0;

  /// Track angle / heading in degrees true (from RMC).
  double heading = 0;

  /// GPS fix quality indicator from GGA sentence.
  /// 0 = invalid, 1 = GPS fix, 2 = DGPS fix.
  int fixQuality = 0;

  /// Number of satellites in use (from GGA).
  int satellites = 0;

  /// True when the RMC sentence status field is 'A' (active / valid fix).
  bool isFixed = false;

  /// UTC date and time of the fix (from RMC).
  DateTime gpsTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  String toString() =>
      'GpsData(lat=$latitude, lon=$longitude, alt=$altitude, '
      'spd=$speed, hdg=$heading, fix=$fixQuality, sats=$satellites, '
      'fixed=$isFixed, time=$gpsTime)';
}
