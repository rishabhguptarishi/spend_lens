/** Recharts styling aligned with SpendLens dark theme */
export const chartColors = {
  grid: 'rgba(255,255,255,0.06)',
  axis: '#94a3b8',
  tooltipBg: '#0f172a',
  tooltipBorder: 'rgba(255,255,255,0.1)',
  tooltipText: '#e2e8f0',
  legend: '#cbd5e1',
}

export const chartTooltipStyle = {
  contentStyle: {
    backgroundColor: chartColors.tooltipBg,
    border: `1px solid ${chartColors.tooltipBorder}`,
    borderRadius: '12px',
    boxShadow: '0 10px 40px rgba(0,0,0,0.4)',
  },
  labelStyle: { color: chartColors.tooltipText },
  itemStyle: { color: chartColors.tooltipText },
}

export const chartAxisTick = { fill: chartColors.axis, fontSize: 12 }
export const chartLegendStyle = { color: chartColors.legend }
