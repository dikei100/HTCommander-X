import 'package:flutter/material.dart';

class SidebarDestination {
  const SidebarDestination({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

const List<SidebarDestination> sidebarDestinations = [
  SidebarDestination(icon: Icons.forum, label: 'Communication'),
  SidebarDestination(icon: Icons.person_search, label: 'Contacts'),
  SidebarDestination(icon: Icons.settings_input_antenna, label: 'Packets'),
  SidebarDestination(icon: Icons.terminal, label: 'Terminal'),
  SidebarDestination(icon: Icons.dns, label: 'BBS'),
  SidebarDestination(icon: Icons.mail_outline, label: 'Mail'),
  SidebarDestination(icon: Icons.download, label: 'Torrent'),
  SidebarDestination(icon: Icons.map_outlined, label: 'APRS'),
];

class SidebarNav extends StatelessWidget {
  const SidebarNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.onSettingsTap,
    this.onPowerTap,
    this.vfoAFrequency = 0,
    this.callSign = 'N0CALL',
    this.isConnected = false,
    this.batteryPercent = 0,
    this.rssi = 0,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onPowerTap;
  final double vfoAFrequency;
  final String callSign;
  final bool isConnected;
  final int batteryPercent;
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 220,
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding + status icons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Text(
                  'HTCommander-X',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.signal_cellular_alt,
                  size: 14,
                  color: isConnected ? colors.tertiary : colors.outline,
                ),
                const SizedBox(width: 6),
                Icon(
                  batteryPercent > 60
                      ? Icons.battery_full
                      : batteryPercent > 20
                          ? Icons.battery_3_bar
                          : Icons.battery_1_bar,
                  size: 14,
                  color: isConnected ? colors.onSurfaceVariant : colors.outline,
                ),
              ],
            ),
          ),

          // Frequency display
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              vfoAFrequency > 0
                  ? '${vfoAFrequency.toStringAsFixed(3)} MHz'
                  : '--- . --- MHz',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.primary,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: colors.primary.withAlpha(40),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),

          // Callsign / operator
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.person,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      callSign,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      isConnected ? 'SYSTEM ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isConnected ? colors.tertiary : colors.outline,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // Navigation items
          Expanded(
            child: ListView.builder(
              itemCount: sidebarDestinations.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final dest = sidebarDestinations[index];
                final isSelected = index == selectedIndex;

                return _NavItem(
                  icon: dest.icon,
                  label: dest.label,
                  isSelected: isSelected,
                  onTap: () => onDestinationSelected(index),
                );
              },
            ),
          ),

          // Bottom section
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _NavItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  isSelected: false,
                  onTap: onSettingsTap,
                ),
                _NavItem(
                  icon: Icons.power_settings_new,
                  label: isConnected ? 'Disconnect' : 'Connect',
                  isSelected: false,
                  onTap: onPowerTap,
                  iconColor: isConnected ? colors.error : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? colors.primaryContainer.withAlpha(51)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                icon,
                size: 20,
                color: iconColor ??
                    (isSelected ? colors.primary : colors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
