import { useEffect, useMemo, useRef, useState } from 'react'
import { api, connectQueueWs, API_BASE } from '../services/api'

// ── Constants ────────────────────────────────────────────────────────────────
const roleToPanel = { console: 'console', petugas: 'petugas', display: 'display', administrator: 'admin' }
const canAccess = (role, panel) => role === 'administrator' || roleToPanel[role] === panel
const emptyQueues = { admin: [], poli: [], farmasi: [] }
const emptyLastCalled = { admin: '-', poli: '-', farmasi: '-' }

const serviceFromPoliName = (n) => {
  const t = (n || '').toLowerCase()
  if (t.includes('farmasi')) return 'farmasi'
  if (t.includes('admin')) return 'admin'
  return 'poli'
}

const STATUS_LABEL = { waiting:'Menunggu', called:'Dipanggil', serving:'Dilayani', done:'Selesai', cancelled:'Dibatalkan', no_show:'Tidak Hadir' }
const STATUS_COLOR = { waiting:'#0057FF', called:'#F59E0B', serving:'#10B981', done:'#94A3B8', cancelled:'#EF4444', no_show:'#8B5CF6' }

const mapMonitorRows = (rows) => {
  const queues = { admin: [], poli: [], farmasi: [] }
  const latestCalled = { admin: '-', poli: '-', farmasi: '-' }
  rows.forEach((row) => {
    const svc = serviceFromPoliName(row.poli_name)
    if (row.status === 'waiting') {
      queues[svc].push({ ticket: row.ticket_no, name: row.patient_name, source: row.registration_channel === 'on_site' ? 'On-site' : 'Online', service: svc, order: row.queue_position, status: row.status })
    }
    if ((row.status === 'called' || row.status === 'serving') && latestCalled[svc] === '-') latestCalled[svc] = row.ticket_no
  })
  Object.keys(queues).forEach((s) => { queues[s] = queues[s].sort((a, b) => a.order - b.order) })
  return { queues, latestCalled }
}

// ── Icons (inline SVG helpers) ────────────────────────────────────────────────
const Icon = ({ d, size = 16, color = 'currentColor' }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d={d} />
  </svg>
)

// ── Component ────────────────────────────────────────────────────────────────
export function DashboardPage() {
  const [session, setSession] = useState(() => {
    try {
      const s = window.localStorage.getItem('sqrs-admin-session')
      if (!s) return { loggedIn: false, role: '', username: '' }
      const p = JSON.parse(s)
      if (p?.loggedIn && p?.role) return p
    } catch {}
    return { loggedIn: false, role: '', username: '' }
  })

  const [login, setLogin] = useState({ username: '', password: '' })
  const [loginError, setLoginError] = useState('')
  const [activePanel, setActivePanel] = useState(() => session.loggedIn ? roleToPanel[session.role] : 'console')
  const [queues, setQueues] = useState(emptyQueues)
  const [lastCalled, setLastCalled] = useState(emptyLastCalled)
  const [callHistory, setCallHistory] = useState([])
  const [stats, setStats] = useState({ total_tickets: 0, waiting: 0, done: 0 })
  const [isLoading, setIsLoading] = useState(false)
  const [reportRows, setReportRows] = useState([])
  const [wsConnected, setWsConnected] = useState(false)
  const [options, setOptions] = useState({ polis: [], doctors: [], schedules: [] })
  const [consoleForm, setConsoleForm] = useState({ name: '', phone: '', national_id: '', medical_record_no: '', birth_date: '', poli_id: '', doctor_id: '', schedule_id: '' })
  const [consoleSlip, setConsoleSlip] = useState(null)
  const slipRef = useRef(null)
  const [displayMediaUrl, setDisplayMediaUrl] = useState('')
  const [displayMediaTitle, setDisplayMediaTitle] = useState('Video Layar Tunggu')
  const [displayMediaObjectUrl, setDisplayMediaObjectUrl] = useState('')
  const [displayNotice, setDisplayNotice] = useState('Belum ada panggilan aktif')
  const [displayFocusService, setDisplayFocusService] = useState('poli')
  const displayStageRef = useRef(null)
  const [adminTab, setAdminTab] = useState('overview')
  const [auditLogs, setAuditLogs] = useState([])
  const [waitTimeData, setWaitTimeData] = useState([])
  const [dailyData, setDailyData] = useState([])
  const [scheduleForm, setScheduleForm] = useState({ doctor_id: '', poli_id: '', date: '', start_time: '', end_time: '', quota: 30 })
  const [newUserForm, setNewUserForm] = useState({ username: '', password: '', role: 'petugas' })
  const [adminUsers, setAdminUsers] = useState([])
  const [statusTicketNo, setStatusTicketNo] = useState('')
  const [statusTarget, setStatusTarget] = useState('serving')

  const waitingStats = useMemo(() => ({ admin: queues.admin.length, poli: queues.poli.length, farmasi: queues.farmasi.length }), [queues])
  const mergedQueue = useMemo(() => {
    return [...queues.admin.map(i => ({...i,service:'admin'})), ...queues.poli.map(i => ({...i,service:'poli'})), ...queues.farmasi.map(i => ({...i,service:'farmasi'}))].sort((a,b) => a.order - b.order)
  }, [queues])

  const pushHistory = (msg) => {
    const stamp = new Date().toLocaleTimeString('id-ID')
    setCallHistory((prev) => [`[${stamp}] ${msg}`, ...prev].slice(0, 100))
  }

  const refreshMonitor = async () => {
    const [{ data: monitor }, { data: statsData }] = await Promise.all([api.get('/admin/queue-monitor'), api.get('/admin/stats')])
    const { queues: mq, latestCalled } = mapMonitorRows(monitor)
    setQueues(mq); setLastCalled(latestCalled); setStats(statsData)
  }
  const loadOptions = async () => { const { data } = await api.get('/admin/queue-options'); setOptions(data) }
  const loadReport  = async () => { const { data } = await api.get('/admin/reports/visits'); setReportRows(data) }
  const loadAuditLogs = async () => { try { const { data } = await api.get('/admin/audit-logs'); setAuditLogs(data) } catch {} }
  const loadAnalytics = async () => {
    try {
      const [{ data: wt }, { data: daily }] = await Promise.all([api.get('/admin/analytics/wait-times'), api.get('/admin/analytics/daily')])
      setWaitTimeData(wt); setDailyData(daily)
    } catch {}
  }
  const loadAdminUsers = async () => { try { const { data } = await api.get('/admin/auth/users'); setAdminUsers(data) } catch {} }

  useEffect(() => {
    if (!session.loggedIn) return
    let disposed = false
    const init = async () => {
      try { setIsLoading(true); await Promise.all([loadOptions(), refreshMonitor(), loadReport()]) }
      catch { if (!disposed) window.alert('Gagal mengambil data dari backend.') }
      finally { if (!disposed) setIsLoading(false) }
    }
    init()
    const cleanup = connectQueueWs((event) => {
      setWsConnected(true)
      const type = event.event || ''
      if (['ticket_called','ticket_status_changed','ticket_created','ticket_cancelled'].includes(type)) {
        refreshMonitor().catch(() => {}); loadReport().catch(() => {})
        if (type === 'ticket_called') {
          pushHistory(`${event.ticket_no} dipanggil → ${event.service?.toUpperCase()} (${event.patient_name})`)
          focusDisplay(event.service, event.ticket_no, event.patient_name)
          speakAnnouncement(event.service, event.ticket_no, event.patient_name)
          setLastCalled((prev) => ({ ...prev, [event.service]: event.ticket_no }))
        }
      }
    })
    const timer = window.setInterval(() => refreshMonitor().catch(() => {}), 15000)
    return () => { disposed = true; cleanup(); window.clearInterval(timer) }
  }, [session.loggedIn])

  useEffect(() => {
    if (session.loggedIn) window.localStorage.setItem('sqrs-admin-session', JSON.stringify(session))
  }, [session])

  useEffect(() => {
    if (activePanel === 'admin') { loadAuditLogs(); loadAnalytics(); loadAdminUsers() }
  }, [activePanel])

  useEffect(() => () => { if (displayMediaObjectUrl) window.URL.revokeObjectURL(displayMediaObjectUrl) }, [displayMediaObjectUrl])

  const speakAnnouncement = (service, ticketNo, patientName) => {
    if (!window.speechSynthesis) return
    const utt = new SpeechSynthesisUtterance(`Nomor antrian ${ticketNo}. Atas nama ${patientName}. Silakan menuju layanan ${(service||'').toUpperCase()}.`)
    utt.lang = 'id-ID'; utt.rate = 0.92
    window.speechSynthesis.cancel(); window.speechSynthesis.speak(utt)
  }
  const focusDisplay = (service, ticketNo, patientName) => {
    if (!service) return
    setDisplayFocusService(service)
    setDisplayNotice(`Nomor ${ticketNo} — ${patientName} — menuju ${service.toUpperCase()}`)
  }

  const onLogin = async (e) => {
    e.preventDefault(); setLoginError('')
    try {
      const { data } = await api.post('/admin/auth/login', { username: login.username.trim(), password: login.password })
      setSession({ loggedIn: true, role: data.role, username: data.username })
      setActivePanel(roleToPanel[data.role] || 'console')
    } catch (err) { setLoginError(err?.response?.data?.detail || 'Login gagal') }
  }
  const onLogout = () => {
    setSession({ loggedIn: false, role: '', username: '' }); setLogin({ username: '', password: '' })
    setQueues(emptyQueues); setLastCalled(emptyLastCalled); setWsConnected(false)
    if (displayMediaObjectUrl) { window.URL.revokeObjectURL(displayMediaObjectUrl); setDisplayMediaObjectUrl('') }
    window.localStorage.removeItem('sqrs-admin-session')
  }
  const changePanel = (panel) => {
    if (!canAccess(session.role, panel)) { window.alert('Akses ditolak.'); return }
    setActivePanel(panel)
  }
  const callNext = async (service) => {
    try {
      const { data } = await api.post('/admin/queue-call-next', { service })
      setLastCalled((prev) => ({ ...prev, [service]: data.ticket_no }))
      pushHistory(`Panggil ${service.toUpperCase()}: ${data.ticket_no} (${data.patient_name})`)
      focusDisplay(service, data.ticket_no, data.patient_name)
      speakAnnouncement(service, data.ticket_no, data.patient_name)
      await Promise.all([refreshMonitor(), loadReport()])
    } catch (err) { window.alert(err?.response?.data?.detail || `Belum ada antrian ${service.toUpperCase()}`) }
  }
  const updateStatus = async (e) => {
    e.preventDefault(); if (!statusTicketNo.trim()) return
    try {
      const { data } = await api.post('/admin/queue-status', { ticket_no: statusTicketNo.trim(), status: statusTarget })
      pushHistory(`Status ${data.ticket_no} → ${data.status}`); setStatusTicketNo(''); await refreshMonitor()
    } catch (err) { window.alert(err?.response?.data?.detail || 'Gagal update status') }
  }
  const submitConsole = async (e) => {
    e.preventDefault()
    if (!consoleForm.name.trim() || !consoleForm.phone.trim()) { window.alert('Nama dan no HP wajib diisi.'); return }
    if (!consoleForm.poli_id || !consoleForm.doctor_id || !consoleForm.schedule_id) { window.alert('Pilih Poli, Dokter, dan Jadwal.'); return }
    try {
      const { data } = await api.post('/admin/queue-onsite', {
        full_name: consoleForm.name.trim(), phone: consoleForm.phone.trim(),
        national_id: consoleForm.national_id.trim() || undefined,
        medical_record_no: consoleForm.medical_record_no.trim() || undefined,
        birth_date: consoleForm.birth_date || undefined,
        poli_id: Number(consoleForm.poli_id), doctor_id: Number(consoleForm.doctor_id), schedule_id: Number(consoleForm.schedule_id),
      })
      pushHistory(`On-site: ${consoleForm.name.trim()} → ${data.ticket_no}`)
      setConsoleSlip(data)
      setConsoleForm({ name:'', phone:'', national_id:'', medical_record_no:'', birth_date:'', poli_id: consoleForm.poli_id, doctor_id: consoleForm.doctor_id, schedule_id: consoleForm.schedule_id })
      await Promise.all([refreshMonitor(), loadReport()])
    } catch (err) { window.alert(err?.response?.data?.detail || 'Pendaftaran gagal.') }
  }
  const printSlip = () => {
    if (!slipRef.current) return
    const win = window.open('', '_blank', 'width=400,height=600')
    win.document.write(`<html><head><title>Tiket Antrian</title><style>body{font-family:monospace;padding:20px;text-align:center}.big{font-size:64px;font-weight:bold;margin:10px 0}.line{border-top:1px dashed #000;margin:10px 0}p{margin:4px 0;font-size:14px}.label{font-size:11px;color:#555}</style></head><body>${slipRef.current.innerHTML}<script>window.onload=()=>{window.print();window.close()}<\/script></body></html>`)
    win.document.close()
  }
  const seedDemo = async () => {
    try { await api.post('/admin/seed'); pushHistory('Seed data dijalankan.'); await Promise.all([loadOptions(), refreshMonitor(), loadReport()]); window.alert('Seed data berhasil.') }
    catch { window.alert('Gagal seed data.') }
  }
  const resetQueue = async () => {
    if (!window.confirm('Reset semua antrian? Tidak bisa dibatalkan.')) return
    try { await api.post('/admin/queue-reset'); setQueues(emptyQueues); setLastCalled(emptyLastCalled); pushHistory('Reset semua antrian.'); await Promise.all([refreshMonitor(), loadReport()]) }
    catch { window.alert('Gagal reset antrian.') }
  }
  const createSchedule = async (e) => {
    e.preventDefault()
    try {
      await api.post('/admin/schedules', { ...scheduleForm, doctor_id: Number(scheduleForm.doctor_id), poli_id: Number(scheduleForm.poli_id), quota: Number(scheduleForm.quota) })
      pushHistory(`Jadwal baru: dokter ${scheduleForm.doctor_id} tgl ${scheduleForm.date}`)
      setScheduleForm({ doctor_id:'', poli_id:'', date:'', start_time:'', end_time:'', quota:30 })
      await loadOptions(); window.alert('Jadwal berhasil dibuat.')
    } catch (err) { window.alert(err?.response?.data?.detail || 'Gagal membuat jadwal.') }
  }
  const deleteSchedule = async (id) => {
    if (!window.confirm(`Hapus jadwal ID ${id}?`)) return
    try { await api.delete(`/admin/schedules/${id}`); pushHistory(`Jadwal ${id} dihapus.`); await loadOptions() }
    catch (err) { window.alert(err?.response?.data?.detail || 'Gagal hapus jadwal.') }
  }
  const createAdminUser = async (e) => {
    e.preventDefault()
    try {
      await api.post('/admin/auth/users', newUserForm)
      pushHistory(`User baru: ${newUserForm.username} (${newUserForm.role})`)
      setNewUserForm({ username:'', password:'', role:'petugas' }); await loadAdminUsers(); window.alert('User berhasil dibuat.')
    } catch (err) { window.alert(err?.response?.data?.detail || 'Gagal membuat user.') }
  }
  const playAnnouncement = (service) => {
    const t = lastCalled[service]
    if (!t || t === '-') { window.alert(`Belum ada nomor ${service.toUpperCase()} yang dipanggil.`); return }
    focusDisplay(service, t, `antrian ${service.toUpperCase()}`); speakAnnouncement(service, t, `antrian ${service.toUpperCase()}`)
  }
  const openFullscreen  = async () => { try { await displayStageRef.current?.requestFullscreen() } catch {} }
  const exitFullscreen  = async () => { try { if (document.fullscreenElement) await document.exitFullscreen() } catch {} }
  const onDisplayMediaChange = (e) => {
    const file = e.target.files?.[0]; if (!file) return
    if (displayMediaObjectUrl) window.URL.revokeObjectURL(displayMediaObjectUrl)
    const url = window.URL.createObjectURL(file)
    setDisplayMediaObjectUrl(url); setDisplayMediaUrl(url); setDisplayMediaTitle(file.name)
  }
  const downloadReport = () => window.open(`${API_BASE}/admin/reports/visits.xlsx`, '_blank', 'noopener,noreferrer')

  // ── Login Screen ─────────────────────────────────────────────────────────────
  if (!session.loggedIn) {
    return (
      <div className="login-wrap">
        <div className="login-card">
          <div className="login-logo">+</div>
          <h1>SmartQueue RS</h1>
          <p className="sub">Masuk ke dashboard manajemen antrian</p>
          <form onSubmit={onLogin} className="form-grid">
            <div className="form-field full">
              <label>Username</label>
              <input value={login.username} placeholder="Masukkan username" onChange={(e) => setLogin(p => ({...p, username: e.target.value}))} required />
            </div>
            <div className="form-field full">
              <label>Password</label>
              <input type="password" value={login.password} placeholder="Masukkan password" onChange={(e) => setLogin(p => ({...p, password: e.target.value}))} required />
            </div>
            {loginError && <p className="error-msg full">{loginError}</p>}
            <button className="btn full" type="submit">Masuk Dashboard</button>
          </form>
          <p className="hint">Demo: <strong>administrator / admin123</strong></p>
        </div>
      </div>
    )
  }

  // ── Main Dashboard ────────────────────────────────────────────────────────────
  return (
    <div className="page-shell">
      <div className="page-wrap">

        {/* Topbar */}
        <div className="topbar">
          <div className="topbar-brand">
            <div className="topbar-logo">+</div>
            <div>
              <div className="topbar-title">SmartQueue RS</div>
              <div className="topbar-sub">RSUD Serpong Utara</div>
            </div>
          </div>
          <div className="topbar-right">
            <div className="role-chip">
              {wsConnected && <span className="ws-dot" title="WebSocket terhubung" />}
              {session.role.toUpperCase()} — {session.username}
            </div>
            <button className="btn secondary" style={{padding:'7px 14px',fontSize:12}} onClick={onLogout}>Keluar</button>
          </div>
        </div>

        {/* Hero */}
        <div className="hero">
          <div className="hero-inner">
            <div className="hero-text">
              <h2>Dashboard Antrian</h2>
              <p>RSUD Serpong Utara — Sistem Manajemen Antrian Real-time</p>
            </div>
            <div className="hero-stats">
              <div className="hero-stat">
                <div className="hero-stat-val">{stats.total_tickets}</div>
                <div className="hero-stat-lbl">Total Tiket</div>
              </div>
              <div className="hero-stat">
                <div className="hero-stat-val">{stats.waiting}</div>
                <div className="hero-stat-lbl">Menunggu</div>
              </div>
              <div className="hero-stat">
                <div className="hero-stat-val">{stats.done}</div>
                <div className="hero-stat-lbl">Selesai</div>
              </div>
              <div className="hero-stat">
                <div className="hero-stat-val">{stats.total_doctors ?? '-'}</div>
                <div className="hero-stat-lbl">Dokter</div>
              </div>
              {isLoading && <div className="hero-stat"><div className="hero-stat-val" style={{fontSize:14}}>⟳</div><div className="hero-stat-lbl">Memuat</div></div>}
            </div>
          </div>
        </div>

        {/* Nav */}
        <div className="nav-grid">
          <button className={`nav-btn ${activePanel==='console'?'blue':''}`} onClick={() => changePanel('console')}>📋 Console Box</button>
          <button className={`nav-btn ${activePanel==='petugas'?'orange':''}`} onClick={() => changePanel('petugas')}>📢 Petugas Panggil</button>
          <button className={`nav-btn ${activePanel==='display'?'green':''}`} onClick={() => changePanel('display')}>🖥 Display</button>
          <button className={`nav-btn ${activePanel==='admin'?'purple':''}`} onClick={() => changePanel('admin')}>⚙️ Administrator</button>
        </div>

        <div className="content-grid">
          <div>

            {/* ── Console Panel ── */}
            {activePanel === 'console' && (
              <section className="panel-card">
                <h3>Console Box</h3>
                <p className="sub">Pendaftaran on-the-spot untuk pasien yang datang langsung ke loket.</p>

                <form className="form-grid" onSubmit={submitConsole}>
                  <div className="form-field full">
                    <label>Nama Lengkap Pasien *</label>
                    <input placeholder="Nama lengkap" value={consoleForm.name} onChange={(e) => setConsoleForm(p => ({...p, name: e.target.value}))} required />
                  </div>
                  <div className="form-field">
                    <label>No. HP *</label>
                    <input placeholder="08xxxxxxxxxx" value={consoleForm.phone} onChange={(e) => setConsoleForm(p => ({...p, phone: e.target.value}))} required />
                  </div>
                  <div className="form-field">
                    <label>NIK (opsional)</label>
                    <input placeholder="16 digit NIK" value={consoleForm.national_id} onChange={(e) => setConsoleForm(p => ({...p, national_id: e.target.value}))} />
                  </div>
                  <div className="form-field">
                    <label>No. Rekam Medis (opsional)</label>
                    <input placeholder="RM-XXXX" value={consoleForm.medical_record_no} onChange={(e) => setConsoleForm(p => ({...p, medical_record_no: e.target.value}))} />
                  </div>
                  <div className="form-field">
                    <label>Tanggal Lahir (opsional)</label>
                    <input type="date" value={consoleForm.birth_date} onChange={(e) => setConsoleForm(p => ({...p, birth_date: e.target.value}))} />
                  </div>
                  <div className="form-field full">
                    <label>Poli *</label>
                    <select value={consoleForm.poli_id} onChange={(e) => setConsoleForm(p => ({...p, poli_id: e.target.value, doctor_id:'', schedule_id:''}))} required>
                      <option value="">— Pilih Poli —</option>
                      {options.polis.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
                    </select>
                  </div>
                  <div className="form-field full">
                    <label>Dokter *</label>
                    <select value={consoleForm.doctor_id} onChange={(e) => setConsoleForm(p => ({...p, doctor_id: e.target.value, schedule_id:''}))} disabled={!consoleForm.poli_id} required>
                      <option value="">— Pilih Dokter —</option>
                      {options.doctors.filter(d => !consoleForm.poli_id || d.poli_id === Number(consoleForm.poli_id)).map(x => <option key={x.id} value={x.id}>{x.full_name} — {x.specialization}</option>)}
                    </select>
                  </div>
                  <div className="form-field full">
                    <label>Jadwal *</label>
                    <select value={consoleForm.schedule_id} onChange={(e) => setConsoleForm(p => ({...p, schedule_id: e.target.value}))} disabled={!consoleForm.doctor_id} required>
                      <option value="">— Pilih Jadwal —</option>
                      {options.schedules.filter(s => !consoleForm.doctor_id || s.doctor_id === Number(consoleForm.doctor_id)).map(s => {
                        const sisa = (s.quota ?? 0) - (s.booked ?? 0)
                        return <option key={s.id} value={s.id} disabled={sisa <= 0}>{s.date}  {s.start_time}–{s.end_time}  ({sisa} sisa kuota)</option>
                      })}
                    </select>
                  </div>
                  <button className="btn full" type="submit">Daftarkan &amp; Cetak Tiket</button>
                </form>

                {consoleSlip && (
                  <div className="slip-wrap">
                    <div className="slip-header">
                      <strong>✓ Tiket Diterbitkan</strong>
                      <button className="btn secondary" style={{padding:'5px 14px',fontSize:12}} onClick={printSlip}>🖨 Cetak</button>
                    </div>
                    <div ref={slipRef} style={{display:'none'}}>
                      <p>RSUD SERPONG UTARA</p><p className="label">SmartQueue RS — Tiket Antrian</p>
                      <div className="line"/><div className="big">{consoleSlip.ticket_no}</div><p className="label">Nomor Antrian</p>
                      <div className="line"/><p><strong>{consoleSlip.patient?.full_name}</strong></p>
                      {consoleSlip.patient?.national_id && <p className="label">NIK: {consoleSlip.patient.national_id}</p>}
                      {consoleSlip.patient?.medical_record_no && <p className="label">No RM: {consoleSlip.patient.medical_record_no}</p>}
                      <div className="line"/><p>{consoleSlip.poli_name}</p><p>{consoleSlip.doctor_name}</p>
                      <p className="label">{consoleSlip.schedule?.date}  {consoleSlip.schedule?.start_time}–{consoleSlip.schedule?.end_time}</p>
                      <div className="line"/><p className="label">Posisi: {consoleSlip.queue_position}  |  Estimasi: {consoleSlip.estimated_minutes} menit</p>
                      <p className="label">Dicetak: {new Date().toLocaleString('id-ID')}</p>
                    </div>
                    <div className="slip-number">{consoleSlip.ticket_no}</div>
                    <div className="slip-number-lbl">Nomor Antrian</div>
                    <hr className="slip-divider"/>
                    <div className="slip-row"><span>Pasien</span><strong>{consoleSlip.patient?.full_name}</strong></div>
                    {consoleSlip.patient?.medical_record_no && <div className="slip-row"><span>No RM</span><strong>{consoleSlip.patient.medical_record_no}</strong></div>}
                    <div className="slip-row"><span>Poli</span><strong>{consoleSlip.poli_name}</strong></div>
                    <div className="slip-row"><span>Dokter</span><strong>{consoleSlip.doctor_name}</strong></div>
                    <div className="slip-row"><span>Jadwal</span><strong>{consoleSlip.schedule?.date}  {consoleSlip.schedule?.start_time}–{consoleSlip.schedule?.end_time}</strong></div>
                    <hr className="slip-divider"/>
                    <div className="slip-row"><span>Posisi</span><strong>#{consoleSlip.queue_position}</strong></div>
                    <div className="slip-row"><span>Estimasi</span><strong>{consoleSlip.estimated_minutes} menit</strong></div>
                  </div>
                )}

                <div className="section-title">Update Status Tiket</div>
                <form className="form-grid" onSubmit={updateStatus}>
                  <div className="form-field">
                    <label>No. Tiket</label>
                    <input placeholder="mis. A-001" value={statusTicketNo} onChange={(e) => setStatusTicketNo(e.target.value)} required />
                  </div>
                  <div className="form-field">
                    <label>Status Baru</label>
                    <select value={statusTarget} onChange={(e) => setStatusTarget(e.target.value)}>
                      <option value="serving">Serving — sedang dilayani</option>
                      <option value="done">Done — selesai</option>
                      <option value="no_show">No Show — tidak hadir</option>
                      <option value="waiting">Waiting — kembalikan</option>
                    </select>
                  </div>
                  <button className="btn full" type="submit">Update Status</button>
                </form>

                <div className="section-title">Log Aktivitas</div>
                <div className="history-box">
                  {callHistory.length ? callHistory.map((l, i) => <div key={i}>{l}</div>) : <div style={{color:'var(--text-3)'}}>Belum ada log.</div>}
                </div>
              </section>
            )}

            {/* ── Petugas Panel ── */}
            {activePanel === 'petugas' && (
              <section className="panel-card">
                <h3>Petugas Panggil</h3>
                <p className="sub">Panggil nomor antrian berikutnya untuk setiap layanan.</p>

                <div className="stats-grid">
                  <div className="stat-box blue"><span>Admin</span><strong>{waitingStats.admin}</strong><small>menunggu</small></div>
                  <div className="stat-box orange"><span>Poli</span><strong>{waitingStats.poli}</strong><small>menunggu</small></div>
                  <div className="stat-box green"><span>Farmasi</span><strong>{waitingStats.farmasi}</strong><small>menunggu</small></div>
                </div>

                <div className="btn-grid">
                  <button className="btn" onClick={() => callNext('admin')}>📢 Panggil Admin</button>
                  <button className="btn orange" onClick={() => callNext('poli')}>📢 Panggil Poli</button>
                  <button className="btn green" onClick={() => callNext('farmasi')}>📢 Panggil Farmasi</button>
                </div>

                <div className="section-title">Update Status Tiket</div>
                <form className="form-grid" onSubmit={updateStatus}>
                  <div className="form-field">
                    <label>No. Tiket</label>
                    <input placeholder="mis. A-001" value={statusTicketNo} onChange={(e) => setStatusTicketNo(e.target.value)} required />
                  </div>
                  <div className="form-field">
                    <label>Status Baru</label>
                    <select value={statusTarget} onChange={(e) => setStatusTarget(e.target.value)}>
                      <option value="serving">Serving</option>
                      <option value="done">Done</option>
                      <option value="no_show">No Show</option>
                    </select>
                  </div>
                  <button className="btn full" type="submit">Update Status</button>
                </form>

                <div className="section-title">Antrian Aktif</div>
                <div className="queue-list">
                  {mergedQueue.length ? mergedQueue.map((item) => (
                    <div className="queue-item" key={`${item.ticket}-${item.order}`}>
                      <div>
                        <div className="queue-item-ticket">{item.ticket}</div>
                        <div className="queue-item-name">{item.name}</div>
                        <div className="meta">{item.source} · {item.service.toUpperCase()}</div>
                      </div>
                      <span className="chip" style={{color: STATUS_COLOR[item.status], borderColor: STATUS_COLOR[item.status], background: STATUS_COLOR[item.status]+'18'}}>
                        {STATUS_LABEL[item.status] || item.status}
                      </span>
                    </div>
                  )) : <div className="meta" style={{padding:'12px 0'}}>Belum ada antrian aktif.</div>}
                </div>

                <div className="section-title">Log Panggilan</div>
                <div className="history-box">
                  {callHistory.length ? callHistory.map((l, i) => <div key={i}>{l}</div>) : <div style={{color:'var(--text-3)'}}>Belum ada log.</div>}
                </div>
              </section>
            )}

            {/* ── Display Panel ── */}
            {activePanel === 'display' && (
              <section className="panel-card display-panel" ref={displayStageRef}>
                <div className="display-panel-head">
                  <div>
                    <h3>Display Nomor Panggilan</h3>
                    <p className="sub">Nomor dipanggil otomatis via WebSocket dan dibacakan suara.</p>
                  </div>
                  <div className="display-panel-actions">
                    <button className="btn secondary" style={{fontSize:12}} onClick={openFullscreen}>⛶ Layar Penuh</button>
                    <button className="btn secondary" style={{fontSize:12}} onClick={exitFullscreen}>✕ Keluar</button>
                  </div>
                </div>

                <div className="display-call-grid">
                  <button className="btn" onClick={() => callNext('admin')}>📢 Panggil Admin</button>
                  <button className="btn orange" onClick={() => callNext('poli')}>📢 Panggil Poli</button>
                  <button className="btn green" onClick={() => callNext('farmasi')}>📢 Panggil Farmasi</button>
                </div>

                <div className="display-stage">
                  <div className={`display-stage-main ${displayFocusService}`}>
                    <div className="display-stage-kicker">Panggilan Aktif</div>
                    <div className="display-stage-number">{lastCalled[displayFocusService]}</div>
                    <div className="display-stage-notice">{displayNotice}</div>
                    <div className="display-stage-subgrid">
                      {['admin','poli','farmasi'].map(svc => (
                        <div key={svc} className={`display-mini ${displayFocusService===svc?'active':''}`}>
                          <span>{svc.toUpperCase()}</span>
                          <strong>{lastCalled[svc]}</strong>
                        </div>
                      ))}
                    </div>
                  </div>

                  <div className="display-stage-side">
                    <div className="display-video-card">
                      <div className="display-video-head">
                        <strong style={{fontSize:13}}>{displayMediaTitle}</strong>
                        <span className="meta">Video layar tunggu</span>
                      </div>
                      <div className="display-video-inputs">
                        <input value={displayMediaUrl} onChange={(e) => setDisplayMediaUrl(e.target.value)} placeholder="URL video MP4/WebM" />
                        <input type="file" accept="video/*" onChange={onDisplayMediaChange} style={{fontSize:12}} />
                      </div>
                      <div className="display-video-wrap">
                        {displayMediaUrl
                          ? <video className="display-video" controls autoPlay muted loop src={displayMediaUrl} />
                          : <div className="display-video-empty">Masukkan file video atau URL untuk layar tunggu.</div>}
                      </div>
                    </div>
                    <div className="display-audio-grid">
                      <button className="btn secondary" style={{fontSize:12}} onClick={() => playAnnouncement('admin')}>🔊 Admin</button>
                      <button className="btn secondary" style={{fontSize:12}} onClick={() => playAnnouncement('poli')}>🔊 Poli</button>
                      <button className="btn secondary" style={{fontSize:12}} onClick={() => playAnnouncement('farmasi')}>🔊 Farmasi</button>
                    </div>
                  </div>
                </div>

                <div className="display-grid" style={{marginTop:16}}>
                  {['admin','poli','farmasi'].map((svc,i) => (
                    <div key={svc} className={`display-box ${['blue','orange','green'][i]} ${displayFocusService===svc?'display-box-active':''}`}>
                      <h4>{svc.toUpperCase()}</h4>
                      <div className="num">{lastCalled[svc]}</div>
                    </div>
                  ))}
                </div>

                <div className="section-title">Log Panggilan</div>
                <div className="history-box">
                  {callHistory.length ? callHistory.map((l, i) => <div key={i}>{l}</div>) : <div style={{color:'var(--text-3)'}}>Belum ada log.</div>}
                </div>
              </section>
            )}

            {/* ── Admin Panel ── */}
            {activePanel === 'admin' && (
              <section className="panel-card">
                <h3>Administrator</h3>
                <p className="sub">Kelola jadwal, pengguna, laporan, dan konfigurasi sistem.</p>

                <div className="admin-tabs">
                  {[['overview','📊 Overview'],['schedules','📅 Jadwal'],['analytics','📈 Analitik'],['users','👤 Pengguna'],['audit','🔍 Audit']].map(([tab,label]) => (
                    <button key={tab} className={`admin-tab ${adminTab===tab?'active':''}`} onClick={() => setAdminTab(tab)}>{label}</button>
                  ))}
                </div>

                {adminTab === 'overview' && (
                  <div>
                    <div className="btn-grid">
                      <button className="btn secondary" onClick={seedDemo}>🌱 Isi Data Demo</button>
                      <button className="btn danger" onClick={resetQueue}>🗑 Reset Antrian</button>
                      <button className="btn secondary" onClick={downloadReport}>⬇ Unduh XLSX</button>
                    </div>

                    <div className="section-title">Statistik Registrasi</div>
                    <div className="analytics-grid">
                      <div className="analytics-card">
                        <div className="analytics-title">Online vs On-site</div>
                        {(() => {
                          const online = stats.registration_channels?.online || 0
                          const offline = stats.registration_channels?.on_site || 0
                          const total = Math.max(online + offline, 1)
                          return (
                            <div className="bar-chart">
                              <div className="bar-row"><span>Online</span><div className="bar-track"><div className="bar-fill blue" style={{width:`${(online/total)*100}%`}}/></div><strong>{online}</strong></div>
                              <div className="bar-row"><span>On-site</span><div className="bar-track"><div className="bar-fill green" style={{width:`${(offline/total)*100}%`}}/></div><strong>{offline}</strong></div>
                            </div>
                          )
                        })()}
                      </div>
                      <div className="analytics-card">
                        <div className="analytics-title">Poli vs Farmasi</div>
                        {(() => {
                          const poli = stats.service_counts?.poli || 0
                          const farmasi = stats.service_counts?.farmasi || 0
                          const total = Math.max(poli + farmasi, 1)
                          return (
                            <div className="bar-chart">
                              <div className="bar-row"><span>Poli</span><div className="bar-track"><div className="bar-fill blue" style={{width:`${(poli/total)*100}%`}}/></div><strong>{poli}</strong></div>
                              <div className="bar-row"><span>Farmasi</span><div className="bar-track"><div className="bar-fill orange" style={{width:`${(farmasi/total)*100}%`}}/></div><strong>{farmasi}</strong></div>
                            </div>
                          )
                        })()}
                      </div>
                    </div>

                    <div className="section-title">Laporan Kunjungan</div>
                    <div className="table-wrap">
                      <table>
                        <thead><tr>{['No Tiket','Pasien','Poli','Dokter','Channel','Status','Waktu'].map(h => <th key={h}>{h}</th>)}</tr></thead>
                        <tbody>
                          {reportRows.slice(0,50).map((row,i) => (
                            <tr key={i}>
                              <td><strong>{row.ticket_no}</strong></td>
                              <td>{row.patient_name}</td>
                              <td>{row.poli_name}</td>
                              <td>{row.doctor_name}</td>
                              <td>{row.registration_channel}</td>
                              <td><span className="chip" style={{color:STATUS_COLOR[row.status]||'#475569',borderColor:STATUS_COLOR[row.status]||'#475569',background:(STATUS_COLOR[row.status]||'#475569')+'18'}}>{STATUS_LABEL[row.status]||row.status}</span></td>
                              <td style={{color:'var(--text-3)',fontSize:12}}>{row.created_at?.substring(0,16)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}

                {adminTab === 'schedules' && (
                  <div>
                    <div className="section-title">Buat Jadwal Baru</div>
                    <form className="form-grid" onSubmit={createSchedule}>
                      <div className="form-field">
                        <label>Poli</label>
                        <select value={scheduleForm.poli_id} onChange={(e) => setScheduleForm(p => ({...p, poli_id: e.target.value}))} required>
                          <option value="">Pilih Poli</option>
                          {options.polis.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
                        </select>
                      </div>
                      <div className="form-field">
                        <label>Dokter</label>
                        <select value={scheduleForm.doctor_id} onChange={(e) => setScheduleForm(p => ({...p, doctor_id: e.target.value}))} required>
                          <option value="">Pilih Dokter</option>
                          {options.doctors.filter(d => !scheduleForm.poli_id || d.poli_id === Number(scheduleForm.poli_id)).map(x => <option key={x.id} value={x.id}>{x.full_name}</option>)}
                        </select>
                      </div>
                      <div className="form-field"><label>Tanggal</label><input type="date" value={scheduleForm.date} onChange={(e) => setScheduleForm(p => ({...p, date: e.target.value}))} required /></div>
                      <div className="form-field"><label>Jam Mulai</label><input type="time" value={scheduleForm.start_time} onChange={(e) => setScheduleForm(p => ({...p, start_time: e.target.value}))} required /></div>
                      <div className="form-field"><label>Jam Selesai</label><input type="time" value={scheduleForm.end_time} onChange={(e) => setScheduleForm(p => ({...p, end_time: e.target.value}))} required /></div>
                      <div className="form-field"><label>Kuota</label><input type="number" value={scheduleForm.quota} min={1} max={200} onChange={(e) => setScheduleForm(p => ({...p, quota: e.target.value}))} required /></div>
                      <button className="btn full" type="submit">Buat Jadwal</button>
                    </form>

                    <div className="section-title">Jadwal Tersedia</div>
                    <div className="table-wrap">
                      <table>
                        <thead><tr>{['ID','Dokter','Poli','Tanggal','Jam','Kuota','Aksi'].map(h => <th key={h}>{h}</th>)}</tr></thead>
                        <tbody>
                          {options.schedules.map(s => {
                            const doc = options.doctors.find(d => d.id === s.doctor_id)
                            const poli = options.polis.find(p => p.id === s.poli_id)
                            return (
                              <tr key={s.id}>
                                <td>{s.id}</td><td>{doc?.full_name||'-'}</td><td>{poli?.name||'-'}</td>
                                <td>{s.date}</td><td>{s.start_time}–{s.end_time}</td><td>{s.quota}</td>
                                <td><button className="btn danger" style={{padding:'4px 10px',fontSize:11}} onClick={() => deleteSchedule(s.id)}>Hapus</button></td>
                              </tr>
                            )
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}

                {adminTab === 'analytics' && (
                  <div>
                    <div className="section-title">Rata-rata Waktu Layanan per Dokter</div>
                    {waitTimeData.length === 0
                      ? <p className="meta" style={{padding:'12px 0'}}>Belum ada data (butuh tiket dengan status done).</p>
                      : <div className="table-wrap"><table>
                          <thead><tr>{['Dokter','Poli','Rata-rata (mnt)','Total Dilayani'].map(h => <th key={h}>{h}</th>)}</tr></thead>
                          <tbody>{waitTimeData.map((r,i) => <tr key={i}><td>{r.doctor}</td><td>{r.poli}</td><td><strong>{r.avg_serve_minutes}</strong></td><td>{r.total_served}</td></tr>)}</tbody>
                        </table></div>}

                    <div className="section-title">Tiket per Hari (30 hari terakhir)</div>
                    {dailyData.length === 0
                      ? <p className="meta" style={{padding:'12px 0'}}>Belum ada data.</p>
                      : <div className="bar-chart" style={{marginTop:8}}>
                          {dailyData.slice(0,14).map(r => {
                            const max = Math.max(...dailyData.map(x => x.total), 1)
                            return (
                              <div key={r.date} className="bar-row">
                                <span style={{fontSize:11,color:'var(--text-3)'}}>{r.date}</span>
                                <div className="bar-track"><div className="bar-fill blue" style={{width:`${(r.total/max)*100}%`}}/></div>
                                <strong style={{fontSize:12}}>{r.total}</strong>
                              </div>
                            )
                          })}
                        </div>}
                  </div>
                )}

                {adminTab === 'users' && (
                  <div>
                    <div className="section-title">Buat User Admin Baru</div>
                    <form className="form-grid" onSubmit={createAdminUser}>
                      <div className="form-field"><label>Username</label><input placeholder="Username" value={newUserForm.username} onChange={(e) => setNewUserForm(p => ({...p, username: e.target.value}))} required /></div>
                      <div className="form-field"><label>Password</label><input type="password" placeholder="Password" value={newUserForm.password} onChange={(e) => setNewUserForm(p => ({...p, password: e.target.value}))} required /></div>
                      <div className="form-field full">
                        <label>Role</label>
                        <select value={newUserForm.role} onChange={(e) => setNewUserForm(p => ({...p, role: e.target.value}))}>
                          <option value="petugas">Petugas</option>
                          <option value="console">Console</option>
                          <option value="display">Display</option>
                          <option value="administrator">Administrator</option>
                        </select>
                      </div>
                      <button className="btn full" type="submit">Buat User</button>
                    </form>

                    <div className="section-title">Daftar User Admin</div>
                    <div className="table-wrap">
                      <table>
                        <thead><tr>{['ID','Username','Role','Aktif'].map(h => <th key={h}>{h}</th>)}</tr></thead>
                        <tbody>
                          {adminUsers.map(u => (
                            <tr key={u.id}>
                              <td>{u.id}</td>
                              <td><strong>{u.username}</strong></td>
                              <td><span className="chip" style={{color:'var(--primary)',borderColor:'var(--primary)',background:'var(--primary-glow)'}}>{u.role}</span></td>
                              <td>{u.is_active ? <span style={{color:'var(--green)',fontWeight:700}}>✓ Aktif</span> : <span style={{color:'var(--red)'}}>✗</span>}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}

                {adminTab === 'audit' && (
                  <div>
                    <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:10}}>
                      <div className="section-title" style={{margin:0}}>Audit Log (100 terbaru)</div>
                      <button className="btn secondary" style={{padding:'6px 14px',fontSize:12}} onClick={loadAuditLogs}>↻ Refresh</button>
                    </div>
                    <div className="table-wrap">
                      <table>
                        <thead><tr>{['Waktu','Actor','Aksi','Detail'].map(h => <th key={h}>{h}</th>)}</tr></thead>
                        <tbody>
                          {auditLogs.map(r => (
                            <tr key={r.id}>
                              <td style={{fontSize:11,color:'var(--text-3)'}}>{r.created_at?.substring(0,19)}</td>
                              <td>{r.actor}</td>
                              <td><strong>{r.action}</strong></td>
                              <td style={{color:'var(--text-3)',maxWidth:240,overflow:'hidden',textOverflow:'ellipsis'}}>{r.detail}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
              </section>
            )}

          </div>

          {/* ── Sidebar Monitor ── */}
          <div>
            <div className="monitor-card">
              <h4>Monitor Antrian</h4>
              {[['admin','blue'],['poli','orange'],['farmasi','green']].map(([svc, color]) => (
                <div className="monitor-service" key={svc}>
                  <div className="monitor-service-head">
                    <span className="monitor-service-name">{svc.toUpperCase()}</span>
                    <span className="monitor-queue-count">{queues[svc].length} antrian</span>
                  </div>
                  <div className={`monitor-called ${color}`}>{lastCalled[svc]}</div>
                  <div className="meta" style={{marginTop:4}}>Terakhir dipanggil</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
