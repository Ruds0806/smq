export function StatCard({ title, value }) {
  return (
    <div className="card stat-card">
      <p className="label">{title}</p>
      <h2>{value}</h2>
    </div>
  )
}
