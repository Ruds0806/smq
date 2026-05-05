import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartqueue_rs/shared/api_client.dart';
import 'package:smartqueue_rs/shared/session_store.dart';
import 'package:smartqueue_rs/shared/theme.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> queueHistory = [];
  List<dynamic> visitHistory = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final queues = await ApiClient()
          .getJson('/history/queues', token: token) as List<dynamic>;
      final visits = await ApiClient()
          .getJson('/history/visits', token: token) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        queueHistory = queues;
        visitHistory = visits;
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'done':      return kGreen;
      case 'cancelled': return kRed;
      case 'no_show':   return kOrange;
      case 'serving':   return kPrimary;
      case 'called':    return kOrange;
      default:          return kSecondaryLabel;
    }
  }

  String _statusLabel(String status) {
    const map = {
      'waiting':   'Menunggu',
      'called':    'Dipanggil',
      'serving':   'Dilayani',
      'done':      'Selesai',
      'cancelled': 'Dibatalkan',
      'no_show':   'Tidak Hadir',
    };
    return map[status] ?? status;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kBackgroundDark : kBackground,
      appBar: AppBar(
        title: const Text('Riwayat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.confirmation_num_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('Antrian'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medical_services_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('Kunjungan'),
                ],
              ),
            ),
          ],
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: kPrimary, strokeWidth: 2.5))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildQueueTab(isDark),
                _buildVisitTab(isDark),
              ],
            ),
    );
  }

  Widget _buildQueueTab(bool isDark) {
    if (queueHistory.isEmpty) {
      return _emptyState(
          'Belum ada riwayat antrian',
          Icons.confirmation_num_outlined,
          isDark);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        itemCount: queueHistory.length,
        itemBuilder: (_, i) {
          final row    = queueHistory[i];
          final status = row['status'] as String? ?? '';
          final color  = _statusColor(status);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
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
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.confirmation_num_rounded,
                      color: color, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            row['ticket_no'].toString(),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isDark ? kLabelDark : kLabel),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(_statusLabel(status),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: color,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${row['poli_name'] ?? ''} • ${row['doctor_name'] ?? ''}',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row['created_at']
                                ?.toString()
                                .substring(0, 10) ??
                            '',
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel),
                      ),
                    ],
                  ),
                ),
                if (row['actual_serve_minutes'] != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${row['actual_serve_minutes']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: isDark ? kLabelDark : kLabel),
                      ),
                      Text('menit',
                          style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? kSecondaryLabelDark
                                  : kSecondaryLabel)),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVisitTab(bool isDark) {
    if (visitHistory.isEmpty) {
      return _emptyState(
          'Belum ada riwayat kunjungan',
          Icons.local_hospital_outlined,
          isDark);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        itemCount: visitHistory.length,
        itemBuilder: (_, i) {
          final row = visitHistory[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? kSurfaceDark : kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark ? kSeparatorDark : kSeparator),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: kGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.medical_services_rounded,
                      color: kGreen, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['doctor_name'].toString(),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isDark ? kLabelDark : kLabel),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row['poli_name'].toString(),
                        style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel),
                      ),
                      if ((row['diagnosis_summary'] as String? ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: isDark
                                ? kSurface2Dark
                                : kBackground,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: isDark
                                    ? kSeparatorDark
                                    : kSeparator),
                          ),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                  Icons.medical_information_outlined,
                                  size: 13,
                                  color: kGreen),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  row['diagnosis_summary'].toString(),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? kSecondaryLabelDark
                                          : kSecondaryLabel,
                                      fontStyle: FontStyle.italic,
                                      height: 1.4),
                                  maxLines: 3,
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
                const SizedBox(width: 8),
                Text(
                  row['visit_date'].toString(),
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? kSecondaryLabelDark
                          : kSecondaryLabel),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(String text, IconData icon, bool isDark) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? kSurface2Dark : kSurface,
                shape: BoxShape.circle,
                border: Border.all(
                    color: isDark ? kSeparatorDark : kSeparator),
              ),
              child: Icon(icon,
                  size: 34,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel),
            ),
            const SizedBox(height: 14),
            Text(text,
                style: TextStyle(
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
