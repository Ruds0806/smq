import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartqueue_rs/shared/api_client.dart';
import 'package:smartqueue_rs/shared/session_store.dart';
import 'package:smartqueue_rs/shared/theme.dart';

class TakeQueuePage extends StatefulWidget {
  const TakeQueuePage({super.key});
  @override
  State<TakeQueuePage> createState() => _TakeQueuePageState();
}

class _TakeQueuePageState extends State<TakeQueuePage> {
  List<dynamic> polis     = [];
  List<dynamic> doctors   = [];
  List<dynamic> schedules = [];
  int? selectedPoli;
  int? selectedDoctor;
  int? selectedSchedule;
  bool _loading = false;
  bool _taking  = false;

  @override
  void initState() {
    super.initState();
    _loadPolis();
  }

  Future<void> _loadPolis() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final data = await ApiClient().getJson('/queue/polis', token: token);
      setState(() => polis = data as List<dynamic>);
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadDoctors() async {
    if (selectedPoli == null) return;
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final data = await ApiClient()
          .getJson('/queue/doctors?poli_id=$selectedPoli', token: token);
      setState(() {
        doctors          = data as List<dynamic>;
        selectedDoctor   = null;
        selectedSchedule = null;
        schedules        = [];
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadSchedules() async {
    if (selectedDoctor == null) return;
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final data = await ApiClient()
          .getJson('/queue/schedules?doctor_id=$selectedDoctor', token: token);
      setState(() {
        schedules        = data as List<dynamic>;
        selectedSchedule = null;
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _takeQueue() async {
    final token = context.read<SessionStore>().token;
    if (selectedPoli == null ||
        selectedDoctor == null ||
        selectedSchedule == null) return;
    setState(() => _taking = true);
    try {
      final conflictRes = await ApiClient().getJson(
        '/queue/check-conflict?schedule_id=$selectedSchedule',
        token: token,
      );
      if (conflictRes['has_conflict'] == true) {
        final conflicts = conflictRes['conflicts'] as List<dynamic>;
        final proceed   = await _showConflictDialog(conflicts);
        if (!proceed) {
          setState(() => _taking = false);
          return;
        }
      }
      final res = await ApiClient().postJson('/queue/take', {
        'poli_id':     selectedPoli,
        'doctor_id':   selectedDoctor,
        'schedule_id': selectedSchedule,
      }, token: token);
      if (!mounted) return;
      await _showSuccessSheet(res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: kRed,
      ));
    }
    setState(() => _taking = false);
  }

  Future<bool> _showConflictDialog(List<dynamic> conflicts) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConflictSheet(
          conflicts: conflicts, isDark: isDark),
    );
    return result ?? false;
  }

  Future<void> _showSuccessSheet(Map<String, dynamic> res) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(res: res),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedDoctorData   = selectedDoctor != null
        ? doctors.firstWhere((d) => d['id'] == selectedDoctor,
            orElse: () => null)
        : null;
    final selectedScheduleData = selectedSchedule != null
        ? schedules.firstWhere((s) => s['id'] == selectedSchedule,
            orElse: () => null)
        : null;

    return Scaffold(
      backgroundColor: isDark ? kBackgroundDark : kBackground,
      appBar: AppBar(
        title: const Text('Ambil Antrian'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // Step indicator
          _buildStepIndicator(isDark),
          const SizedBox(height: 24),

          // Step 1
          _stepLabel('1', 'Pilih Poli', isDark),
          const SizedBox(height: 10),
          _buildSelector(
            hint: 'Pilih poli tujuan',
            icon: Icons.local_hospital_rounded,
            value: selectedPoli,
            items: polis,
            labelKey: 'name',
            isDark: isDark,
            onChanged: (v) {
              setState(() => selectedPoli = v);
              _loadDoctors();
            },
          ),
          const SizedBox(height: 22),

          // Step 2
          _stepLabel('2', 'Pilih Dokter', isDark),
          const SizedBox(height: 10),
          _buildSelector(
            hint: doctors.isEmpty
                ? 'Pilih poli terlebih dahulu'
                : 'Pilih dokter',
            icon: Icons.person_rounded,
            value: selectedDoctor,
            items: doctors,
            labelKey: 'full_name',
            isDark: isDark,
            enabled: doctors.isNotEmpty,
            onChanged: (v) {
              setState(() => selectedDoctor = v);
              _loadSchedules();
            },
          ),
          // Doctor profile card
          if (selectedDoctorData != null) ...[
            const SizedBox(height: 10),
            _buildDoctorProfileCard(selectedDoctorData, isDark),
          ],
          const SizedBox(height: 22),

          // Step 3
          _stepLabel('3', 'Pilih Jadwal', isDark),
          const SizedBox(height: 10),
          schedules.isEmpty
              ? _emptySchedule(isDark)
              : _buildScheduleList(isDark),
          const SizedBox(height: 24),

          // Summary
          if (selectedDoctorData != null &&
              selectedScheduleData != null) ...[
            _buildSummary(selectedDoctorData, selectedScheduleData, isDark),
            const SizedBox(height: 22),
          ],

          // CTA
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: selectedSchedule != null
                    ? kPrimaryGradient
                    : const LinearGradient(
                        colors: [Color(0xFFCBD5E1), Color(0xFFCBD5E1)]),
                borderRadius: BorderRadius.circular(15),
                boxShadow: selectedSchedule != null
                    ? [
                        BoxShadow(
                            color: kPrimary.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 7))
                      ]
                    : [],
              ),
              child: FilledButton(
                onPressed: (_taking || _loading || selectedSchedule == null)
                    ? null
                    : _takeQueue,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: _taking
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.confirmation_num_rounded,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Ambil Antrian',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorProfileCard(Map<String, dynamic> doctor, bool isDark) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPrimary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
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
                              fontSize: 18),
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
                            fontSize: 13.5,
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
                if (doctor['avg_serve_minutes'] != null)
                  Column(
                    children: [
                      Text(
                        '${doctor['avg_serve_minutes']}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kPrimary),
                      ),
                      Text('mnt/pasien',
                          style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? kSecondaryLabelDark
                                  : kSecondaryLabel)),
                    ],
                  ),
              ],
            ),
            if (doctor['bio'] != null) ...[
              const SizedBox(height: 10),
              Text(
                doctor['bio'].toString(),
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel,
                    height: 1.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (doctor['practice_days'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 12,
                      color: isDark
                          ? kSecondaryLabelDark
                          : kSecondaryLabel),
                  const SizedBox(width: 5),
                  Text(
                    'Praktik: ${doctor['practice_days']}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? kSecondaryLabelDark
                            : kSecondaryLabel),
                  ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _buildStepIndicator(bool isDark) {
    final steps = ['Poli', 'Dokter', 'Jadwal'];
    int current = 0;
    if (selectedPoli != null) current = 1;
    if (selectedDoctor != null) current = 2;
    if (selectedSchedule != null) current = 3;

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(
              height: 2,
              color: i ~/ 2 < current
                  ? kPrimary
                  : (isDark ? kSeparatorDark : kSeparator),
            ),
          );
        }
        final idx      = i ~/ 2;
        final done     = idx < current;
        final active   = idx == current;
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: done || active ? kPrimaryGradient : null,
            color: done || active
                ? null
                : (isDark ? kSurface2Dark : kBackground),
            shape: BoxShape.circle,
            border: Border.all(
              color: done || active
                  ? Colors.transparent
                  : (isDark ? kSeparatorDark : kSeparator),
              width: 1.5,
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded,
                    size: 16, color: Colors.white)
                : Text(
                    '${idx + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white
                          : (isDark
                              ? kSecondaryLabelDark
                              : kSecondaryLabel),
                    ),
                  ),
          ),
        );
      }),
    );
  }

  Widget _stepLabel(String num, String text, bool isDark) => Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? kLabelDark : kLabel,
            ),
          ),
        ],
      );

  Widget _buildSelector({
    required String hint,
    required IconData icon,
    required int? value,
    required List<dynamic> items,
    required String labelKey,
    required bool isDark,
    required Function(int?) onChanged,
    bool enabled = true,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            hint: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel),
                const SizedBox(width: 10),
                Text(hint,
                    style: TextStyle(
                        color: isDark
                            ? kSecondaryLabelDark
                            : kSecondaryLabel,
                        fontSize: 15)),
              ],
            ),
            icon: Icon(Icons.expand_more_rounded,
                color: isDark
                    ? kSecondaryLabelDark
                    : kSecondaryLabel),
            dropdownColor: isDark ? kSurfaceDark : kSurface,
            style: TextStyle(
                fontSize: 15,
                color: isDark ? kLabelDark : kLabel),
            items: enabled
                ? items
                    .map((e) => DropdownMenuItem<int>(
                          value: e['id'] as int,
                          child: Text(e[labelKey].toString()),
                        ))
                    .toList()
                : [],
            onChanged: enabled ? onChanged : null,
          ),
        ),
      );

  Widget _emptySchedule(bool isDark) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? kSurfaceDark : kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? kSeparatorDark : kSeparator),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 32,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel),
              const SizedBox(height: 8),
              Text(
                selectedDoctor == null
                    ? 'Pilih dokter terlebih dahulu'
                    : 'Tidak ada jadwal tersedia',
                style: TextStyle(
                    color: isDark
                        ? kSecondaryLabelDark
                        : kSecondaryLabel,
                    fontSize: 14),
              ),
            ],
          ),
        ),
      );

  Widget _buildScheduleList(bool isDark) => Column(
        children: schedules.map((s) {
          final isSelected = selectedSchedule == s['id'];
          final booked     = s['booked'] as int;
          final quota      = s['quota'] as int;
          final sisa       = quota - booked;
          return GestureDetector(
            onTap: () =>
                setState(() => selectedSchedule = s['id'] as int),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isSelected
                    ? kPrimary.withValues(alpha: 0.07)
                    : (isDark ? kSurfaceDark : kSurface),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? kPrimary
                      : (isDark ? kSeparatorDark : kSeparator),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? kPrimary.withValues(alpha: 0.12)
                          : (isDark ? kSurface2Dark : kBackground),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.calendar_today_rounded,
                        size: 18,
                        color: isSelected
                            ? kPrimary
                            : (isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['date'].toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isSelected
                                ? kPrimary
                                : (isDark ? kLabelDark : kLabel),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s['start_time']} – ${s['end_time']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? kSecondaryLabelDark
                                  : kSecondaryLabel),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: sisa > 5
                          ? kGreen.withValues(alpha: 0.1)
                          : kOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '$sisa sisa',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: sisa > 5 ? kGreen : kOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );

  Widget _buildSummary(
      Map<String, dynamic> doctor,
      Map<String, dynamic> schedule,
      bool isDark) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: kPrimary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    size: 15, color: kPrimary),
                const SizedBox(width: 6),
                const Text('Ringkasan Pendaftaran',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: kPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            _summaryRow(Icons.person_rounded,
                doctor['full_name'].toString(), isDark),
            const SizedBox(height: 7),
            _summaryRow(
                Icons.calendar_today_rounded,
                '${schedule['date']}  ${schedule['start_time']}–${schedule['end_time']}',
                isDark),
            const SizedBox(height: 7),
            _summaryRow(
                Icons.people_outline_rounded,
                'Sisa kuota: ${(schedule['quota'] as int) - (schedule['booked'] as int)}',
                isDark),
          ],
        ),
      );

  Widget _summaryRow(IconData icon, String text, bool isDark) => Row(
        children: [
          Icon(icon, size: 14, color: kPrimary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? kLabelDark : kLabel))),
        ],
      );
}

// ── Conflict Sheet ────────────────────────────────────────────────────────────
class _ConflictSheet extends StatelessWidget {
  final List<dynamic> conflicts;
  final bool isDark;
  const _ConflictSheet({required this.conflicts, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
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
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: kOrange, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Jadwal Berbenturan',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: isDark ? kLabelDark : kLabel,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Anda sudah memiliki antrian aktif pada waktu yang sama:',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel),
            ),
            const SizedBox(height: 16),
            ...conflicts.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kOrange.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: kOrange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                              Icons.confirmation_num_rounded,
                              size: 14,
                              color: kOrange),
                          const SizedBox(width: 6),
                          Text('No. ${c['ticket_no']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: kOrange)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${c['poli_name']} • ${c['doctor_name']}',
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark ? kLabelDark : kLabel,
                            fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${c['date']}  ${c['start_time']} – ${c['end_time']}',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? kSecondaryLabelDark
                                : kSecondaryLabel),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            Text(
              'Apakah Anda tetap ingin melanjutkan pendaftaran?',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: BorderSide(
                          color: isDark
                              ? kSeparatorDark
                              : kSeparator),
                      foregroundColor:
                          isDark ? kLabelDark : kLabel,
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: kOrange,
                    ),
                    child: const Text('Tetap Daftar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
}

// ── Success Sheet ─────────────────────────────────────────────────────────────
class _SuccessSheet extends StatelessWidget {
  final Map<String, dynamic> res;
  const _SuccessSheet({required this.res});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? kSeparatorDark : kSeparator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: kGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: kGreen, size: 38),
          ),
          const SizedBox(height: 16),
          const Text(
            'Antrian Berhasil Diambil!',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 6),
          Text(
            'Silakan pantau status antrian di dashboard',
            style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? kSecondaryLabelDark
                    : kSecondaryLabel),
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? kSurface2Dark : kBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Nomor', res['ticket_no'].toString(), isDark),
                _divV(isDark),
                _stat('Posisi', '#${res['queue_position']}', isDark),
                _divV(isDark),
                _stat('Estimasi',
                    '${res['estimated_minutes']} mnt', isDark),
              ],
            ),
          ),
          const SizedBox(height: 26),
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
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Lihat Dashboard'),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, bool isDark) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                  letterSpacing: -0.5)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel)),
        ],
      );

  Widget _divV(bool isDark) => Container(
      width: 0.5,
      height: 38,
      color: isDark ? kSeparatorDark : kSeparator);
}
