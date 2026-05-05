import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smartqueue_rs/shared/api_client.dart';
import 'package:smartqueue_rs/shared/responsive.dart';
import 'package:smartqueue_rs/shared/session_store.dart';
import 'package:smartqueue_rs/shared/theme.dart';
import 'package:smartqueue_rs/shared/ws_client.dart';

class QueueDashboardPage extends StatefulWidget {
  const QueueDashboardPage({super.key});
  @override
  State<QueueDashboardPage> createState() => _QueueDashboardPageState();
}

class _QueueDashboardPageState extends State<QueueDashboardPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? data;
  Map<String, dynamic>? profile;
  List<dynamic> polis        = [];
  List<dynamic> doctors      = [];
  List<dynamic> visitHistory = [];
  Timer?    _pollTimer;
  WsClient? _ws;
  bool _cancelling  = false;
  int  _selectedTab = 0;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _bootstrap();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _fetchDashboard());
    _ws = WsClient(onEvent: (event) {
      final type = event['event'] as String? ?? '';
      if (['ticket_called', 'ticket_status_changed', 'ticket_created', 'ticket_cancelled']
          .contains(type)) {
        _fetchDashboard();
      }
    });
    _ws!.connect();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _pollTimer?.cancel();
    _ws?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() =>
      Future.wait([_fetchDashboard(), _fetchProfile(), _fetchPolis(), _fetchDoctors(), _fetchVisitHistory()]);

  Future<void> _fetchDashboard() async {
    final token = context.read<SessionStore>().token;
    try {
      final res = await ApiClient().getJson('/queue/dashboard', token: token);
      if (!mounted) return;
      setState(() => data = Map<String, dynamic>.from(res));
    } catch (_) {}
  }

  Future<void> _fetchProfile() async {
    final token = context.read<SessionStore>().token;
    try {
      final res = await ApiClient().getJson('/auth/profile', token: token);
      if (!mounted) return;
      setState(() => profile = Map<String, dynamic>.from(res));
    } catch (_) {}
  }

  Future<void> _fetchPolis() async {
    final token = context.read<SessionStore>().token;
    try {
      final res = await ApiClient().getJson('/queue/polis', token: token);
      if (!mounted) return;
      setState(() => polis = res as List<dynamic>);
    } catch (_) {}
  }

  Future<void> _fetchDoctors() async {
    try {
      final res = await ApiClient().getJson('/admin/doctors');
      if (!mounted) return;
      setState(() => doctors = res as List<dynamic>);
    } catch (_) {}
  }

  Future<void> _fetchVisitHistory() async {
    final token = context.read<SessionStore>().token;
    try {
      final res = await ApiClient().getJson('/history/visits', token: token);
      if (!mounted) return;
      setState(() => visitHistory = (res as List<dynamic>).take(5).toList());
    } catch (_) {}
  }

  Future<void> _cancelTicket() async {
    final ticketId = data?['ticket_id'];
    if (ticketId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? kSurfaceDark : kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Batalkan Antrian?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text(
              'Nomor antrian Anda akan dibatalkan dan tidak bisa dikembalikan.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Tidak')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Batalkan',
                  style: TextStyle(
                      color: kRed, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    setState(() => _cancelling = true);
    try {
      final token = context.read<SessionStore>().token;
      await ApiClient().postJson('/queue/cancel/$ticketId', {}, token: token);
      await _fetchDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Antrian berhasil dibatalkan'),
            backgroundColor: kOrange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: kRed));
    }
    setState(() => _cancelling = false);
  }

  Future<void> _logout() async {
    await context.read<SessionStore>().clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'called':  return kOrange;
      case 'serving': return kGreen;
      case 'done':    return kSecondaryLabel;
      default:        return kPrimary;
    }
  }

  String _statusLabel(String status) {
    const map = {
      'waiting':   'Menunggu',
      'called':    'Dipanggil!',
      'serving':   'Sedang Dilayani',
      'done':      'Selesai',
      'cancelled': 'Dibatalkan',
      'no_show':   'Tidak Hadir',
    };
    return map[status] ?? status;
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final hasTicket = data?['has_ticket'] == true;
    final status    = data?['status'] as String? ?? '';
    final canCancel = hasTicket && status == 'waiting';

    return Scaffold(
      backgroundColor: isDark ? kBackgroundDark : kBackground,
      body: data == null
          ? _buildLoading(isDark)
          : NestedScrollView(
              headerSliverBuilder: (context, _) => [_buildAppBar(isDark)],
              body: RefreshIndicator(
                onRefresh: _bootstrap,
                color: kPrimary,
                child: ResponsiveContainer(
                  maxWidth: 860,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    children: [
                      _buildGreeting(isDark),
                      const SizedBox(height: 18),
                      _buildQueueCard(isDark, hasTicket, status, canCancel),
                      const SizedBox(height: 28),
                      // Recent visit history
                      if (visitHistory.isNotEmpty) ...[
                        _buildSectionHeader('Riwayat Penyakit Terakhir', isDark),
                        const SizedBox(height: 12),
                        _buildVisitHistoryCard(isDark),
                        const SizedBox(height: 28),
                      ],
                      _buildSectionHeader('Layanan Tersedia', isDark),
                      const SizedBox(height: 12),
                      _buildTabSelector(isDark),
                      const SizedBox(height: 14),
                      if (_selectedTab == 0) _buildPoliGrid(isDark),
                      if (_selectedTab == 1) _buildDoctorList(isDark),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildLoading(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: kPrimaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: kPrimary, strokeWidth: 2.5),
          ],
        ),
      );

  SliverAppBar _buildAppBar(bool isDark) => SliverAppBar(
        floating: true,
        snap: true,
        backgroundColor: isDark ? kBackgroundDark : kBackground,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: kPrimaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  color: Colors.white, size: 17),
            ),
            const SizedBox(width: 9),
            Text(
              'SmartQueue RS',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? kLabelDark : kLabel),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.account_circle_outlined,
                size: 26,
                color: isDark ? kSecondaryLabelDark : kSecondaryLabel),
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded,
                size: 22,
                color: isDark ? kSecondaryLabelDark : kSecondaryLabel),
            onPressed: _logout,
          ),
        ],
      );

  Widget _buildGreeting(bool isDark) {
    final name      = profile?['full_name']?.toString() ?? 'Pasien';
    final firstName = name.split(' ').first;
    final hour      = DateTime.now().hour;
    final greeting  = hour < 12
        ? 'Selamat Pagi'
        : hour < 17
            ? 'Selamat Siang'
            : 'Selamat Sore';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? kSeparatorDark : kSeparator),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: kPrimary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Center(
              child: Text(
                firstName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $firstName 👋',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: isDark ? kLabelDark : kLabel,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No RM: ${profile?['medical_record_no'] ?? '-'}',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? kSecondaryLabelDark
                          : kSecondaryLabel),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/history'),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: kPrimary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.history_rounded, size: 14, color: kPrimary),
                  SizedBox(width: 5),
                  Text('Riwayat',
                      style: TextStyle(
                          fontSize: 12,
                          color: kPrimary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(
      bool isDark, bool hasTicket, String status, bool canCancel) {
    if (!hasTicket) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.queue_rounded,
                      color: Colors.white, size: 24),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: Colors.white70),
                      SizedBox(width: 5),
                      Text('Tidak ada antrian',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Belum ada antrian aktif',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 5),
            const Text(
              'Pilih poli dan ambil nomor antrian sekarang',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/queue/take')
                  .then((_) => _bootstrap()),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_rounded,
                        color: kPrimary, size: 18),
                    SizedBox(width: 8),
                    Text('Ambil Antrian',
                        style: TextStyle(
                            color: kPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final statusColor = _statusColor(status);
    final progress    = (data!['progress_percent'] as int? ?? 0) / 100;
    final isCalled    = status == 'called' || status == 'serving';
    final doctor      = data!['doctor'] as Map<String, dynamic>?;
    final poli        = data!['poli'] as Map<String, dynamic>?;
    final totalWaiting = data!['total_waiting'] as int? ?? 0;

    return Column(
      children: [
        // ── Ticket status card ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? kSurfaceDark : kSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: isDark ? kSeparatorDark : kSeparator),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                        color: kPrimary.withValues(alpha: 0.07),
                        blurRadius: 24,
                        offset: const Offset(0, 6))
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  _statusBadge(status, statusColor),
                  const Spacer(),
                  Text(
                    data!['ticket_no'].toString(),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: isDark ? kLabelDark : kLabel,
                      letterSpacing: -2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor:
                      isDark ? kSeparatorDark : kSeparator,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              const SizedBox(height: 14),

              // Info chips row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(Icons.people_outline_rounded,
                      '${data!['ahead']} di depan', isDark),
                  _infoChip(Icons.timer_outlined,
                      '~${data!['estimated_minutes']} mnt', isDark),
                  _infoChip(Icons.queue_rounded,
                      '$totalWaiting menunggu', isDark),
                ],
              ),

              // Called/serving banner
              if (isCalled) ...[
                const SizedBox(height: 16),
                ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withValues(alpha: 0.1),
                          statusColor.withValues(alpha: 0.05)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            status == 'called'
                                ? Icons.campaign_rounded
                                : Icons.medical_services_rounded,
                            color: statusColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            data!['notification'] as String,
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // QR code
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? kSurface2Dark : kBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isDark ? kSeparatorDark : kSeparator),
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: data!['checkin_qr'].toString(),
                        size: 120,
                        backgroundColor: Colors.transparent,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: isDark ? kLabelDark : kLabel,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: isDark ? kLabelDark : kLabel,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'QR Check-in Mandiri',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

              // Cancel button
              if (canCancel) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _cancelling ? null : _cancelTicket,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: kRed.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: kRed.withValues(alpha: 0.22)),
                    ),
                    child: Center(
                      child: _cancelling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kRed))
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel_outlined,
                                    size: 16, color: kRed),
                                SizedBox(width: 6),
                                Text('Batalkan Antrian',
                                    style: TextStyle(
                                        color: kRed,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Poli info card ──────────────────────────────────────────────
        if (poli != null) ...[
          const SizedBox(height: 12),
          _buildPoliInfoCard(poli, isDark),
        ],

        // ── Doctor profile card ─────────────────────────────────────────
        if (doctor != null) ...[
          const SizedBox(height: 12),
          _buildDoctorCard(doctor, isDark),
        ],
      ],
    );
  }

  Widget _buildPoliInfoCard(Map<String, dynamic> poli, bool isDark) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  color: kPrimary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poli['name']?.toString() ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? kLabelDark : kLabel),
                  ),
                  if (poli['description'] != null)
                    Text(
                      poli['description'].toString(),
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? kSecondaryLabelDark
                              : kSecondaryLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (poli['room'] != null || poli['floor'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (poli['room'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        poli['room'].toString(),
                        style: const TextStyle(
                            fontSize: 11,
                            color: kPrimary,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (poli['floor'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      poli['floor'].toString(),
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? kSecondaryLabelDark
                              : kSecondaryLabel),
                    ),
                  ],
                ],
              ),
          ],
        ),
      );

  Widget _buildDoctorCard(Map<String, dynamic> doctor, bool isDark) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 26,
                  backgroundColor: kPrimary.withValues(alpha: 0.1),
                  backgroundImage: doctor['photo_url'] != null
                      ? NetworkImage(ApiClient.resolveUrl(
                          doctor['photo_url'].toString()))
                      : null,
                  child: doctor['photo_url'] == null
                      ? Text(
                          (doctor['full_name']?.toString() ?? 'D')
                              .substring(0, 1),
                          style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 20),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor['full_name']?.toString() ?? '',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: isDark ? kLabelDark : kLabel),
                      ),
                      Text(
                        doctor['specialization']?.toString() ?? '',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel),
                      ),
                    ],
                  ),
                ),
                if (doctor['gender'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (doctor['gender'] == 'L'
                              ? const Color(0xFF3B82F6)
                              : kPurple)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      doctor['gender'] == 'L' ? '♂ Laki-laki' : '♀ Perempuan',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: doctor['gender'] == 'L'
                              ? const Color(0xFF3B82F6)
                              : kPurple),
                    ),
                  ),
              ],
            ),
            if (doctor['bio'] != null) ...[
              const SizedBox(height: 12),
              Text(
                doctor['bio'].toString(),
                style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel,
                    height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (doctor['education'] != null ||
                doctor['practice_days'] != null) ...[
              const SizedBox(height: 12),
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: isDark ? kSeparatorDark : kSeparator),
              const SizedBox(height: 12),
              if (doctor['education'] != null)
                _doctorInfoRow(
                    Icons.school_outlined,
                    doctor['education'].toString(),
                    isDark),
              if (doctor['practice_days'] != null) ...[
                const SizedBox(height: 6),
                _doctorInfoRow(
                    Icons.calendar_today_outlined,
                    'Praktik: ${doctor['practice_days']}',
                    isDark),
              ],
            ],
          ],
        ),
      );

  Widget _doctorInfoRow(IconData icon, String text, bool isDark) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 14,
              color: isDark ? kSecondaryLabelDark : kSecondaryLabel),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel,
                  height: 1.4),
            ),
          ),
        ],
      );

  Widget _statusBadge(String status, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              _statusLabel(status),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ],
        ),
      );

  Widget _infoChip(IconData icon, String label, bool isDark) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? kSurface2Dark : kBackground,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: isDark
                    ? kSecondaryLabelDark
                    : kSecondaryLabel),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildVisitHistoryCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? kSeparatorDark : kSeparator),
      ),
      child: Column(
        children: [
          ...visitHistory.asMap().entries.map((entry) {
            final i   = entry.key;
            final row = entry.value as Map<String, dynamic>;
            final isLast = i == visitHistory.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: kGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                            Icons.medical_services_rounded,
                            color: kGreen,
                            size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row['doctor_name']?.toString() ?? '',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: isDark
                                            ? kLabelDark
                                            : kLabel),
                                  ),
                                ),
                                Text(
                                  row['visit_date']?.toString() ?? '',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? kSecondaryLabelDark
                                          : kSecondaryLabel),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              row['poli_name']?.toString() ?? '',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: kPrimary,
                                  fontWeight: FontWeight.w600),
                            ),
                            if ((row['diagnosis_summary'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? kSurface2Dark
                                      : kBackground,
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.notes_rounded,
                                        size: 12,
                                        color: isDark
                                            ? kSecondaryLabelDark
                                            : kSecondaryLabel),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        row['diagnosis_summary']
                                            .toString(),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? kSecondaryLabelDark
                                                : kSecondaryLabel,
                                            fontStyle: FontStyle.italic,
                                            height: 1.4),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 66,
                      color: isDark ? kSeparatorDark : kSeparator),
              ],
            );
          }),
          // View all button
          InkWell(
            onTap: () => Navigator.pushNamed(context, '/history'),
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.04),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18)),
                border: Border(
                    top: BorderSide(
                        color: isDark ? kSeparatorDark : kSeparator,
                        width: 0.5)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Lihat Semua Riwayat',
                      style: TextStyle(
                          fontSize: 13,
                          color: kPrimary,
                          fontWeight: FontWeight.w700)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 14, color: kPrimary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) => Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? kLabelDark : kLabel,
              letterSpacing: -0.3,
            ),
          ),
        ],
      );

  Widget _buildTabSelector(bool isDark) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Row(
          children: [
            _tabItem('Poli', Icons.local_hospital_outlined, 0, isDark),
            _tabItem('Dokter', Icons.person_outlined, 1, isDark),
          ],
        ),
      );

  Widget _tabItem(String label, IconData icon, int index, bool isDark) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? kPrimaryGradient : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? Colors.white
                      : (isDark
                          ? kSecondaryLabelDark
                          : kSecondaryLabel)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : (isDark
                          ? kSecondaryLabelDark
                          : kSecondaryLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoliGrid(bool isDark) {
    if (polis.isEmpty) return const SizedBox.shrink();
    final gradients = [
      [const Color(0xFF0057FF), const Color(0xFF00C2FF)],
      [const Color(0xFF10B981), const Color(0xFF34D399)],
      [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
      [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)],
      [const Color(0xFFEF4444), const Color(0xFFF87171)],
      [const Color(0xFF0EA5E9), const Color(0xFF38BDF8)],
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: polis.length,
      itemBuilder: (_, i) {
        final poli = polis[i];
        final g    = gradients[i % gradients.length];
        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/queue/take')
              .then((_) => _bootstrap()),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: g,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: g[0].withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 5))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      color: Colors.white, size: 18),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poli['name'].toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    if (poli['room'] != null)
                      Text(
                        '${poli['room']} · ${poli['floor'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 10.5),
                      )
                    else
                      const Text('Ambil antrian →',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDoctorList(bool isDark) {
    if (doctors.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? kSeparatorDark : kSeparator),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: doctors.take(10).length,
        separatorBuilder: (_, __) => Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 70,
            color: isDark ? kSeparatorDark : kSeparator),
        itemBuilder: (_, i) {
          final doctor = doctors[i];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 23,
              backgroundColor: kPrimary.withValues(alpha: 0.1),
              backgroundImage: doctor['photo_url'] != null
                  ? NetworkImage(ApiClient.resolveUrl(
                      doctor['photo_url'].toString()))
                  : null,
              child: doctor['photo_url'] == null
                  ? Text(
                      doctor['full_name'].toString().substring(0, 1),
                      style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 17),
                    )
                  : null,
            ),
            title: Text(
              doctor['full_name'].toString(),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? kLabelDark : kLabel),
            ),
            subtitle: Text(
              doctor['specialization'].toString(),
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel),
            ),
            trailing: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chevron_right_rounded,
                  color: kPrimary, size: 18),
            ),
          );
        },
      ),
    );
  }
}
