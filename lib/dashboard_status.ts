import { buildRows, type DashboardData, emptyDashboardData } from './dashboard_data.ts';

const PASS_COLOR = '#2ea44f';
const FAIL_COLOR = '#d73a49';
const LABEL_COLOR = '#555555';

export type DashboardOverallStatus = 'passing' | 'failing';

export interface DashboardStatusSummary {
  status: DashboardOverallStatus;
  ok: boolean;
  label: string;
  message: string;
  color: string;
  rowCount: number;
  regressionCount: number;
  errorCount: number;
}

export function summarizeDashboardStatus(data: DashboardData): DashboardStatusSummary {
  const rows = buildRows(data);
  const regressionCount = rows.reduce((sum, row) => sum + row.regressionCount, 0);
  const errorCount = rows.reduce((sum, row) => sum + row.errorCount, 0);
  const ok = rows.length > 0 && regressionCount === 0 && errorCount === 0;

  return {
    status: ok ? 'passing' : 'failing',
    ok,
    label: 'core bench',
    message: ok ? 'passing' : 'failing',
    color: ok ? PASS_COLOR : FAIL_COLOR,
    rowCount: rows.length,
    regressionCount,
    errorCount,
  };
}

function escapeXml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function badgeTextWidth(value: string): number {
  return Math.max(44, Math.ceil(value.length * 6.8 + 10));
}

export function renderDashboardStatusSvg(summary: DashboardStatusSummary): string {
  const labelWidth = badgeTextWidth(summary.label);
  const messageWidth = badgeTextWidth(summary.message);
  const width = labelWidth + messageWidth;
  const title = `${summary.label}: ${summary.message}`;
  const detail = `${summary.regressionCount} regressions, ${summary.errorCount} errors`;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="20" role="img" aria-label="${
    escapeXml(title)
  }">
  <title>${escapeXml(`${title} (${detail})`)}</title>
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#ffffff" stop-opacity=".12"/>
    <stop offset="1" stop-opacity=".12"/>
  </linearGradient>
  <clipPath id="r">
    <rect width="${width}" height="20" rx="3" fill="#ffffff"/>
  </clipPath>
  <g clip-path="url(#r)">
    <rect width="${labelWidth}" height="20" fill="${LABEL_COLOR}"/>
    <rect x="${labelWidth}" width="${messageWidth}" height="20" fill="${summary.color}"/>
    <rect width="${width}" height="20" fill="url(#s)"/>
  </g>
  <g fill="#ffffff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    <text x="${labelWidth / 2}" y="15" fill="#010101" fill-opacity=".3">${escapeXml(summary.label)}</text>
    <text x="${labelWidth / 2}" y="14">${escapeXml(summary.label)}</text>
    <text x="${labelWidth + messageWidth / 2}" y="15" fill="#010101" fill-opacity=".3">${
    escapeXml(summary.message)
  }</text>
    <text x="${labelWidth + messageWidth / 2}" y="14">${escapeXml(summary.message)}</text>
  </g>
</svg>
`;
}

export function emptyStatusData(): DashboardData {
  return emptyDashboardData();
}
