import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartqueue_rs/shared/api_client.dart';
import 'package:smartqueue_rs/shared/session_store.dart';
import 'package:smartqueue_rs/shared/theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      final res = await ApiClient().getJson('/auth/profile', token: token);
      if (!mounted) return;
      setState(() => profile = Map<String, dynamic>.from(res));
    } catch (_) {}
  }

  Future<void> _logout() async {
    await context.read<SessionStore>().clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final members  = (profile?['family_members'] as List<dynamic>? ?? []);

    return Scaffold(
      backgroundColor: isDark ? kBackgroundDark : kBackground,
      appBar: AppBar(
        title: const Text('Profil Saya'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: profile == null
          ? const Center(
              child: CircularProgressIndicator(
                  color: kPrimary, strokeWidth: 2.5))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // ── Avatar card ──────────────────────────────────────────
                _buildAvatarCard(isDark),
                const SizedBox(height: 22),

                // ── Patient info ─────────────────────────────────────────
                _sectionLabel('Informasi Pasien', isDark),
                const SizedBox(height: 10),
                _buildInfoCard(isDark),
                const SizedBox(height: 22),

                // ── Family members ───────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                        child: _sectionLabel('Anggota Keluarga', isDark)),
                    GestureDetector(
                      onTap: _showAddFamilySheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: kPrimary.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                size: 15, color: kPrimary),
                            SizedBox(width: 4),
                            Text('Tambah',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: kPrimary,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildFamilyCard(members, isDark),
                const SizedBox(height: 32),

                // ── Logout ───────────────────────────────────────────────
                GestureDetector(
                  onTap: _logout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: kRed.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: kRed.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded,
                            size: 18, color: kRed),
                        SizedBox(width: 8),
                        Text('Keluar',
                            style: TextStyle(
                                color: kRed,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAvatarCard(bool isDark) {
    final name = profile!['full_name']?.toString() ?? 'Pasien';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: kPrimaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: kPrimary.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4),
                ),
                const SizedBox(height: 4),
                Text(
                  profile!['phone']?.toString() ?? '',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13.5),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'RM: ${profile!['medical_record_no'] ?? '-'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) => Container(
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Column(
          children: [
            _infoRow('NIK',
                profile!['national_id']?.toString() ?? '-',
                Icons.badge_outlined, isDark,
                isFirst: true),
            _divider(isDark),
            _infoRow('No. Rekam Medis',
                profile!['medical_record_no']?.toString() ?? '-',
                Icons.folder_outlined, isDark),
            _divider(isDark),
            _infoRow('No. Telepon',
                profile!['phone']?.toString() ?? '-',
                Icons.phone_outlined, isDark,
                isLast: true),
          ],
        ),
      );

  Widget _buildFamilyCard(List<dynamic> members, bool isDark) {
    if (members.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.group_outlined,
                  size: 32,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel),
              const SizedBox(height: 8),
              Text('Belum ada anggota keluarga',
                  style: TextStyle(
                      color: isDark
                          ? kSecondaryLabelDark
                          : kSecondaryLabel,
                      fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? kSeparatorDark : kSeparator),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: members.length,
        separatorBuilder: (_, __) => Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 68,
            color: isDark ? kSeparatorDark : kSeparator),
        itemBuilder: (_, i) {
          final m = members[i];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              radius: 21,
              backgroundColor: kPrimary.withValues(alpha: 0.1),
              child: Text(
                m['full_name'].toString().substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: kPrimary, fontWeight: FontWeight.w800),
              ),
            ),
            title: Text(m['full_name'].toString(),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark ? kLabelDark : kLabel)),
            subtitle: Text(m['relationship_name'].toString(),
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel)),
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text, bool isDark) => Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? kSecondaryLabelDark : kSecondaryLabel,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );

  Widget _infoRow(String label, String value, IconData icon, bool isDark,
      {bool isFirst = false, bool isLast = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: kPrimary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? kSecondaryLabelDark
                              : kSecondaryLabel,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? kLabelDark : kLabel)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _divider(bool isDark) => Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 65,
      color: isDark ? kSeparatorDark : kSeparator);

  void _showAddFamilySheet() {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    final relCtrl  = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? kSurfaceDark : kSurface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? kSeparatorDark : kSeparator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: kPrimaryGradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Tambah Anggota Keluarga',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: isDark ? kLabelDark : kLabel)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Nama lengkap',
                  prefixIcon: Icon(Icons.person_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: relCtrl,
                decoration: const InputDecoration(
                  hintText: 'Hubungan (misal: Anak, Istri)',
                  prefixIcon: Icon(Icons.group_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: kPrimaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: kPrimary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: FilledButton(
                    onPressed: () async {
                      final token =
                          context.read<SessionStore>().token;
                      await ApiClient().postJson('/auth/family', {
                        'full_name': nameCtrl.text.trim(),
                        'relationship_name':
                            relCtrl.text.trim().isEmpty
                                ? 'Keluarga'
                                : relCtrl.text.trim(),
                        'birth_date': '2000-01-01',
                      }, token: token);
                      if (!mounted) return;
                      Navigator.pop(context);
                      _load();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Simpan'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
