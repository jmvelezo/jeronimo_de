import 'package:flutter/material.dart';
import 'app_card.dart';

const Color kPrimary = Color(0xFF6D28D9);
const Color kPrimaryDark = Color(0xFF3B0764);
const Color kPrimaryMid = Color(0xFF7C3AED);
const Color kPrimarySoft = Color(0xFFA78BFA);
const Color kLavender = Color(0xFFEDE9FE);
const Color kLavender2 = Color(0xFFF5F3FF);
const Color kSoftBackground = Color(0xFFF8F5FF);
const Color kInk = Color(0xFF1F1635);
const Color kMuted = Color(0xFF6B6280);
const Color kBorder = Color(0xFFE9E2F7);
const Color kSuccess = Color(0xFF22C55E);
const Color kWarning = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);

const String kBrandNavCasa = 'assets/branding/nav_casa_manual.png';
const String kBrandNavMas = 'assets/branding/nav_mas_manual.png';
const String kBrandNavPersonal = 'assets/branding/nav_personal_manual.png';
const String kBrandNavTareas = 'assets/branding/nav_tareas_manual.png';
const String kBrandAhorro = 'assets/branding/icon_ahorro_manual.png';
const String kBrandConfigAvanzada = 'assets/branding/icon_config_avanzada_manual.png';
const String kBrandGastos = 'assets/branding/icon_gastos_manual.png';
const String kBrandHistorialCierre = 'assets/branding/icon_historial_cierre_manual.png';
const String kBrandIaHogar = 'assets/branding/icon_ia_hogar_manual.png';
const String kBrandPulsoHogar = 'assets/branding/icon_pulso_hogar_manual.png';
const String kBrandLoginHeader = 'assets/branding/login_header_manual.png';


const int kBottomNavInicioIndex = 0;
const int kBottomNavCasaIndex = 1;
const int kBottomNavPersonalIndex = 2;
const int kBottomNavTareasIndex = 3;
const int kBottomNavMasIndex = 4;

class JeronimoBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool allowSharedNavigation;

  const JeronimoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.allowSharedNavigation = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: kPrimaryDark.withOpacity(0.055),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: NavigationBar(
        elevation: 0,
        selectedIndex: currentIndex,
        onDestinationSelected: (value) {
          if (value == currentIndex) return;
          if (!allowSharedNavigation && value != kBottomNavPersonalIndex) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Entrá a un hogar compartido para usar Inicio, Casa, Tareas y Más.')),
            );
            return;
          }
          onDestinationSelected(value);
        },
        destinations: const [
          NavigationDestination(icon: _JeronimoNavIcon(assetPath: kBrandNavCasa, fallbackIcon: Icons.home_outlined), selectedIcon: _JeronimoNavIcon(assetPath: kBrandNavCasa, fallbackIcon: Icons.home_rounded, selected: true), label: 'Inicio'),
          NavigationDestination(icon: _JeronimoNavIcon(assetPath: kBrandNavCasa, fallbackIcon: Icons.roofing_outlined), selectedIcon: _JeronimoNavIcon(assetPath: kBrandNavCasa, fallbackIcon: Icons.roofing_rounded, selected: true), label: 'Casa'),
          NavigationDestination(icon: _JeronimoNavIcon(assetPath: kBrandNavPersonal, fallbackIcon: Icons.account_balance_wallet_outlined), selectedIcon: _JeronimoNavIcon(assetPath: kBrandNavPersonal, fallbackIcon: Icons.account_balance_wallet_rounded, selected: true), label: 'Personal'),
          NavigationDestination(icon: _JeronimoNavIcon(assetPath: kBrandNavTareas, fallbackIcon: Icons.task_alt_outlined), selectedIcon: _JeronimoNavIcon(assetPath: kBrandNavTareas, fallbackIcon: Icons.task_alt, selected: true), label: 'Tareas'),
          NavigationDestination(icon: _JeronimoNavIcon(assetPath: kBrandNavMas, fallbackIcon: Icons.grid_view_rounded), selectedIcon: _JeronimoNavIcon(assetPath: kBrandNavMas, fallbackIcon: Icons.dashboard_customize_rounded, selected: true), label: 'Más'),
        ],
      ),
    );
  }
}

class _JeronimoNavIcon extends StatelessWidget {
  final String assetPath;
  final IconData fallbackIcon;
  final bool selected;

  const _JeronimoNavIcon({required this.assetPath, required this.fallbackIcon, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final frame = selected ? 34.0 : 31.0;
    return BrandAssetIcon(
      assetPath: assetPath,
      fallbackIcon: fallbackIcon,
      size: frame,
      frameSize: frame,
      borderRadius: frame / 2,
      padding: 0,
      withShadow: false,
      showFrame: false,
      fit: BoxFit.cover,
      scale: selected ? 1.18 : 1.14,
      fallbackColor: selected ? kPrimary : kMuted,
    );
  }
}

class BrandAssetIcon extends StatelessWidget {
  final String assetPath;
  final IconData fallbackIcon;
  final double size;
  final double frameSize;
  final double borderRadius;
  final double padding;
  final bool withShadow;
  final bool showFrame;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color fallbackColor;
  final BoxFit fit;
  final double scale;
  final Alignment alignment;

  const BrandAssetIcon({
    super.key,
    required this.assetPath,
    required this.fallbackIcon,
    this.size = 32,
    this.frameSize = 46,
    this.borderRadius = 18,
    this.padding = 5,
    this.withShadow = true,
    this.showFrame = true,
    this.backgroundColor,
    this.borderColor,
    this.fallbackColor = kPrimary,
    this.fit = BoxFit.contain,
    this.scale = 1.0,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final safePadding = padding.clamp(0.0, frameSize / 3).toDouble();
    final innerRadius = (borderRadius - safePadding).clamp(6.0, borderRadius).toDouble();
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(innerRadius),
      child: Transform.scale(
        scale: scale,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: fit,
          alignment: alignment,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(fallbackIcon, color: fallbackColor, size: size * 0.72),
          ),
        ),
      ),
    );

    return Container(
      width: frameSize,
      height: frameSize,
      padding: EdgeInsets.all(safePadding),
      decoration: showFrame
          ? BoxDecoration(
              color: backgroundColor ?? Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor ?? kBorder.withOpacity(0.85)),
              boxShadow: withShadow
                  ? [
                      BoxShadow(
                        color: kPrimaryDark.withOpacity(0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            )
          : null,
      child: Center(child: image),
    );
  }
}

class AppGradientBackground extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppGradientBackground({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 24),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBF8FF), Color(0xFFF4EFFF), Color(0xFFEDE9FE)],
        ),
      ),
      child: SafeArea(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppHeroHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? assetIconPath;
  final Widget? trailing;

  const AppHeroHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.assetIconPath,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7C3AED), Color(0xFF5B21B6), Color(0xFF3B0764)],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -42,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 42,
            bottom: -56,
            child: Container(
              width: 148,
              height: 148,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Row(
            children: [
              assetIconPath == null
                  ? Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.17),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withOpacity(0.20)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 31),
                    )
                  : BrandAssetIcon(
                      assetPath: assetIconPath!,
                      fallbackIcon: icon,
                      size: 46,
                      frameSize: 58,
                      borderRadius: 22,
                      padding: 4,
                      backgroundColor: Colors.white.withOpacity(0.94),
                      borderColor: Colors.white.withOpacity(0.24),
                      fallbackColor: kPrimary,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow.toUpperCase(), style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    const SizedBox(height: 5),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.86), height: 1.25, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  const SectionTitle({super.key, required this.title, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: kLavender, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: kPrimary, size: 20),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kInk, letterSpacing: -0.2)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: const TextStyle(color: kMuted, height: 1.25, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BigActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool outlined;

  const BigActionButton({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: outlined ? kLavender : Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (subtitle != null) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: outlined ? kMuted : Colors.white.withOpacity(0.86), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );

    if (outlined) {
      return OutlinedButton(onPressed: onPressed, child: child);
    }
    return ElevatedButton(onPressed: onPressed, child: child);
  }
}

class SoftActionTile extends StatelessWidget {
  final IconData icon;
  final String? assetIconPath;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color color;

  const SoftActionTile({super.key, required this.icon, this.assetIconPath, required this.title, required this.subtitle, this.onTap, this.color = kPrimary});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.09),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              assetIconPath == null
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.74),
                        borderRadius: BorderRadius.circular(17),
                        boxShadow: [
                          BoxShadow(color: color.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 7)),
                        ],
                      ),
                      child: Icon(icon, color: color),
                    )
                  : BrandAssetIcon(
                      assetPath: assetIconPath!,
                      fallbackIcon: icon,
                      size: 34,
                      frameSize: 42,
                      borderRadius: 17,
                      padding: 3,
                      withShadow: false,
                      backgroundColor: Colors.white.withOpacity(0.86),
                      borderColor: color.withOpacity(0.12),
                      fallbackColor: color,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const MetricTile({super.key, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 20),
          ),
          const Spacer(),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.3)),
        ],
      ),
    );
  }
}

class FriendlyError extends StatelessWidget {
  final String message;
  const FriendlyError({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: const Color(0xFFFFF1F2),
      border: Border.all(color: const Color(0xFFFDA4AF)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE11D48)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF9F1239), fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String? assetIconPath;
  final String title;
  final String message;

  const EmptyState({super.key, required this.icon, this.assetIconPath, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Colors.white.withOpacity(0.88),
      border: Border.all(color: kBorder),
      child: Column(
        children: [
          assetIconPath == null
              ? Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: kLavender, borderRadius: BorderRadius.circular(24)),
                  child: Icon(icon, color: kPrimary, size: 34),
                )
              : BrandAssetIcon(
                  assetPath: assetIconPath!,
                  fallbackIcon: icon,
                  size: 50,
                  frameSize: 64,
                  borderRadius: 24,
                  padding: 5,
                  backgroundColor: Colors.white.withOpacity(0.88),
                  borderColor: kBorder,
                  fallbackColor: kPrimary,
                ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kInk)),
          const SizedBox(height: 5),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, height: 1.3, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
