// lib/widgets/bottom_nav.dart
import 'package:flutter/material.dart';

const _kPrimary      = Color(0xFFC0392B);
const _kPrimaryLight = Color(0xFFEDD9D7);
const _kBorder       = Color(0xFFE8E4E1);
const _kTextMuted    = Color(0xFFAA9E98);

class BottomNav extends StatelessWidget {
  final String currentScreen;
  final void Function(String) onTab;

  const BottomNav({
    super.key,
    required this.currentScreen,
    required this.onTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _kBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            iconSelected: Icons.home_rounded,
            label: 'Home',
            isSelected: currentScreen == 'home',
            onTap: () => onTab('home'),
          ),
          _NavItem(
            icon: Icons.map_outlined,
            iconSelected: Icons.map_rounded,
            label: 'Peta',
            isSelected: currentScreen == 'map',
            onTap: () => onTab('map'),
          ),
          _NavItem(
            icon: Icons.receipt_long_outlined,
            iconSelected: Icons.receipt_long_rounded,
            label: 'Riwayat',
            isSelected: currentScreen == 'history',
            onTap: () => onTab('history'),
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            iconSelected: Icons.person_rounded,
            label: 'Menu',
            isSelected: currentScreen == 'menu',
            onTap: () => onTab('menu'),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData iconSelected;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.iconSelected,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSelected ? iconSelected : icon,
                key: ValueKey(isSelected),
                size: 22,
                color: isSelected ? _kPrimary : _kTextMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? _kPrimary : _kTextMuted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}