//
//  MarkdownTableFormatter.swift
//
//  CotEditor
//  https://coteditor.com
//
//  ---------------------------------------------------------------------------
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreGraphics
import Foundation

/// Aligns Markdown pipe tables & Tab-delimited plain tables (with live font-exact metrics when available)
/// and extracts tabular/key-value datasets into a polished, zero-latency Apple-native interactive
/// table & chart studio (`WKWebView`).
nonisolated enum MarkdownTableFormatter {
    
    enum ColumnAlignment: Sendable {
        case left
        case center
        case right
    }
    
    struct ExtractedTable: Equatable, Sendable {
        let headers: [String]
        let rows: [[String]]
    }
    
    
    // MARK: Table Formatting (Markdown Pipe Tables & Tab-Separated Plain Tables)
    
    /// Formats all Markdown pipe tables AND Tab-separated plain tables found inside `text`.
    ///
    /// - Parameters:
    ///   - text: A selection or document string containing one or more tables.
    ///   - metrics: Optional live editor font/tab metrics. When supplied, Markdown `|` pipes align accurately
    ///     even in proportional fonts and Tab-separated tables align to exact `NSLayoutManager` Tab stops.
    /// - Returns: The string with all detected tables aligned.
    static func formatTables(
        in text: String,
        metrics: AIDocumentTextCleaner.TableLayoutMetrics? = nil
    ) -> String {
        
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        
        var output: [String] = []
        var index = 0
        
        while index < lines.count {
            // 1. Markdown pipe table block (2+ consecutive pipe-table rows)
            if self.isMarkdownPipeTableRow(lines[index]) {
                var block: [String] = []
                while index < lines.count, self.isMarkdownPipeTableRow(lines[index]) {
                    block.append(lines[index])
                    index += 1
                }
                if block.count >= 2 {
                    output.append(contentsOf: self.formatMarkdownTableBlock(block, metrics: metrics))
                } else {
                    output.append(contentsOf: block)
                }
                continue
            }
            
            // 2. Tab-separated plain table block (2+ consecutive rows with >= 2 Tab-delimited columns)
            if self.isTabTableRow(lines[index]) {
                let start = index
                let leadingTabs = String(lines[index].prefix { $0 == "\t" })
                var block: [String] = []
                while index < lines.count,
                      self.isTabTableRow(lines[index]),
                      String(lines[index].prefix { $0 == "\t" }) == leadingTabs
                {
                    block.append(lines[index])
                    index += 1
                }
                if block.count >= 2 {
                    let parsed = block.map { self.parseTabCells(in: $0, strippingLeading: leadingTabs) }
                    let colCounts = Set(parsed.map(\.count))
                    let maxCols = parsed.map(\.count).max() ?? 0
                    // Align when rows form a coherent tabular grid (matching or nearly-matching >= 2 columns)
                    if maxCols >= 2, colCounts.count <= 2 {
                        let effectiveMetrics = metrics ?? .defaultMonospace
                        let aligned = AIDocumentTextCleaner.formatStructuredTableRows(
                            parsed,
                            leadingPrefix: leadingTabs,
                            allowKeyValueFlatten: false,
                            metrics: effectiveMetrics
                        )
                        output.append(contentsOf: aligned)
                    } else {
                        output.append(contentsOf: block)
                    }
                } else {
                    output.append(lines[start])
                }
                continue
            }
            
            output.append(lines[index])
            index += 1
        }
        
        return output.joined(separator: "\n")
    }
    
    
    /// Checks whether `text` contains at least one Markdown pipe table.
    static func containsMarkdownTable(_ text: String) -> Bool {
        
        let lines = text.components(separatedBy: .newlines)
        var consecutive = 0
        for line in lines {
            if self.isMarkdownPipeTableRow(line) {
                consecutive += 1
                if consecutive >= 2 { return true }
            } else {
                consecutive = 0
            }
        }
        return false
    }
    
    
    /// Checks whether `text` contains either a Markdown pipe table or a Tab-delimited plain table.
    static func containsAnyTable(_ text: String) -> Bool {
        
        if self.containsMarkdownTable(text) {
            return true
        }
        return self.extractTable(from: text) != nil
    }
    
    
    // MARK: Multi-Format Dataset Extraction (Markdown Pipe / Tab-Delimited / Key-Value Lists)
    
    /// Extracts the primary structured table from Markdown pipe tables, Tab-separated plain tables,
    /// or structured Key: Value lines, stripping Markdown inline decoration from cells.
    static func extractTable(from text: String) -> ExtractedTable? {
        
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        
        // 1. Prefer the first valid Markdown pipe table block (with >= 1 data row)
        var i = 0
        while i < lines.count {
            if self.isMarkdownPipeTableRow(lines[i]) {
                var block: [String] = []
                while i < lines.count, self.isMarkdownPipeTableRow(lines[i]) {
                    block.append(lines[i])
                    i += 1
                }
                let dataLines = block.filter { !self.isSeparatorRow($0) }
                if dataLines.count >= 2 {
                    let parsed = dataLines.map { self.parseCells(in: $0).map { self.cleanCellText($0) } }
                    let headers = parsed[0]
                    let rows = Array(parsed.dropFirst())
                    if headers.count >= 2, !rows.isEmpty {
                        return ExtractedTable(headers: headers, rows: rows)
                    }
                }
            } else {
                i += 1
            }
        }
        
        // 2. Fallback: Tab-separated plain table (e.g. produced by `清洗规整` or copied from spreadsheets)
        var bestTabTable: ExtractedTable?
        var bestTabScore = 0
        i = 0
        while i < lines.count {
            if self.isTabTableRow(lines[i]) {
                let leadingTabs = String(lines[i].prefix { $0 == "\t" })
                var block: [String] = []
                while i < lines.count,
                      self.isTabTableRow(lines[i]),
                      String(lines[i].prefix { $0 == "\t" }) == leadingTabs
                {
                    block.append(lines[i])
                    i += 1
                }
                if block.count >= 2 {
                    let parsed = block.map {
                        self.parseTabCells(in: $0, strippingLeading: leadingTabs).map { self.cleanCellText($0) }
                    }
                    let colCount = parsed.first?.count ?? 0
                    if colCount >= 2, parsed.allSatisfy({ abs($0.count - colCount) <= 1 }) {
                        let normalized = parsed.map { row -> [String] in
                            row.count >= colCount ? Array(row.prefix(colCount)) : row + Array(repeating: "", count: colCount - row.count)
                        }
                        let score = normalized.count * colCount
                        if score > bestTabScore {
                            bestTabScore = score
                            bestTabTable = ExtractedTable(headers: normalized[0], rows: Array(normalized.dropFirst()))
                        }
                    }
                }
            } else {
                i += 1
            }
        }
        if let bestTabTable, !bestTabTable.rows.isEmpty {
            return bestTabTable
        }
        
        // 3. Fallback: Structured Key-Value items (`- 名称：数值` or `周一: 1800字`)
        var kvRows: [[String]] = []
        for raw in lines {
            var trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            for prefix in ["- ", "* ", "• ", "+ "] where trimmed.hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            let sepRange = trimmed.range(of: "：") ?? trimmed.range(of: ": ")
            if let sepRange {
                let key = self.cleanCellText(String(trimmed[..<sepRange.lowerBound]))
                let val = self.cleanCellText(String(trimmed[sepRange.upperBound...]))
                if !key.isEmpty, !val.isEmpty, key.count <= 40 {
                    kvRows.append([key, val])
                }
            }
        }
        if kvRows.count >= 2 {
            return ExtractedTable(
                headers: [AppLanguage.text("项目", en: "Item"), AppLanguage.text("内容", en: "Value")],
                rows: kvRows
            )
        }
        
        return nil
    }
    
    
    // MARK: Apple-Native Interactive Table & Chart Studio HTML
    
    /// Builds a refined, zero-latency interactive Table + Chart studio HTML document with
    /// sticky sortable/searchable table, inline numeric bars, click-to-copy cells, and crisp
    /// Bar / Line / Donut charts adapting cleanly to Light & Dark mode.
    static func generateInstantChartHTML(from text: String, aiInsightMarkdown: String? = nil) -> String {
        
        let extracted = self.extractTable(from: text)
        let headers = extracted?.headers ?? []
        let dataRows = extracted?.rows ?? []
        
        let payload: [String: Any] = [
            "headers": headers,
            "rows": dataRows,
            "insight": aiInsightMarkdown ?? "",
        ]
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(Self.interactiveStudioCSS)
        </style>
        </head>
        <body>
        \(Self.interactiveStudioBodyHTML)
        <script>
        const DATA = \(jsonString);
        \(Self.interactiveStudioScript)
        </script>
        </body>
        </html>
        """
    }
    
    
    private static let interactiveStudioCSS: String = """
        :root {
            color-scheme: light dark;
            --bg: #ffffff;
            --surface: #f5f6f8;
            --surface-2: #eceef2;
            --hover: rgba(15, 23, 42, 0.04);
            --border: rgba(15, 23, 42, 0.09);
            --border-strong: rgba(15, 23, 42, 0.15);
            --ink: #151922;
            --ink-2: #525b6d;
            --ink-3: #838c9e;
            --accent: #2f7cf6;
            --accent-soft: rgba(47, 124, 246, 0.10);
            --green: #16a34a;
            --green-soft: rgba(22, 163, 74, 0.11);
            --amber: #d97706;
            --amber-soft: rgba(217, 119, 6, 0.11);
            --shadow-seg: 0 1px 2px rgba(0,0,0,0.08), 0 0 0 0.5px rgba(0,0,0,0.06);
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #1c1e24;
                --surface: #242730;
                --surface-2: #2c303b;
                --hover: rgba(255, 255, 255, 0.045);
                --border: rgba(255, 255, 255, 0.09);
                --border-strong: rgba(255, 255, 255, 0.16);
                --ink: #eef1f7;
                --ink-2: #9ba3b5;
                --ink-3: #6c7588;
                --accent: #519afd;
                --accent-soft: rgba(81, 154, 253, 0.16);
                --green: #4cc38a;
                --green-soft: rgba(76, 195, 138, 0.16);
                --amber: #f59e0b;
                --amber-soft: rgba(245, 158, 11, 0.16);
                --shadow-seg: 0 1px 3px rgba(0,0,0,0.34), 0 0 0 0.5px rgba(255,255,255,0.08);
            }
        }
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
            -webkit-font-smoothing: antialiased;
        }
        html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: var(--bg);
            color: var(--ink);
            font-size: 12.5px;
        }
        .shell {
            display: flex;
            flex-direction: column;
            width: 100%;
            height: 100%;
            padding: 10px 12px 10px;
            gap: 9px;
        }
        .topbar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 8px;
            flex-shrink: 0;
        }
        .segmented {
            display: inline-flex;
            align-items: center;
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 2px;
            gap: 2px;
        }
        .seg-btn {
            border: none;
            background: transparent;
            color: var(--ink-2);
            padding: 4px 10px;
            border-radius: 6px;
            font-size: 11.5px;
            font-weight: 500;
            cursor: pointer;
            transition: background 140ms ease, color 140ms ease;
            white-space: nowrap;
        }
        .seg-btn:hover { color: var(--ink); }
        .seg-btn.active {
            background: var(--bg);
            color: var(--ink);
            font-weight: 600;
            box-shadow: var(--shadow-seg);
        }
        .seg-btn:disabled {
            opacity: 0.36;
            cursor: default;
        }
        .tools {
            display: flex;
            align-items: center;
            gap: 6px;
            min-width: 0;
        }
        .metric-select, .filter-input, .tool-btn {
            height: 26px;
            border-radius: 7px;
            border: 1px solid var(--border);
            background: var(--surface);
            color: var(--ink);
            font-size: 11.5px;
            outline: none;
            transition: border-color 120ms ease, background 120ms ease;
        }
        .metric-select {
            padding: 0 8px;
            cursor: pointer;
            font-weight: 500;
        }
        .filter-input {
            width: 124px;
            padding: 0 8px;
        }
        .filter-input::placeholder { color: var(--ink-3); }
        .filter-input:focus { border-color: var(--border-strong); background: var(--bg); }
        .tool-btn {
            padding: 0 9px;
            cursor: pointer;
            font-weight: 500;
            color: var(--ink-2);
            white-space: nowrap;
        }
        .tool-btn:hover { color: var(--ink); background: var(--surface-2); }
        .meta-pill {
            font-size: 11px;
            color: var(--ink-3);
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
            padding: 0 2px;
        }
        .stage {
            flex: 1;
            min-height: 0;
            overflow: auto;
            border: 1px solid var(--border);
            border-radius: 10px;
            background: var(--bg);
            position: relative;
        }
        .stage::-webkit-scrollbar { width: 6px; height: 6px; }
        .stage::-webkit-scrollbar-track { background: transparent; }
        .stage::-webkit-scrollbar-thumb { background: var(--border-strong); border-radius: 999px; }

        /* Interactive Table */
        table.studio-grid {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12.5px;
        }
        table.studio-grid thead th {
            position: sticky;
            top: 0;
            z-index: 2;
            background: var(--surface);
            color: var(--ink-2);
            font-size: 11.5px;
            font-weight: 600;
            padding: 8px 12px;
            text-align: left;
            border-bottom: 1px solid var(--border);
            cursor: pointer;
            user-select: none;
            white-space: nowrap;
            transition: color 120ms ease, background 120ms ease;
        }
        table.studio-grid thead th:hover { color: var(--ink); background: var(--surface-2); }
        table.studio-grid thead th.num, table.studio-grid tbody td.num {
            text-align: right;
            font-variant-numeric: tabular-nums;
        }
        table.studio-grid tbody td {
            padding: 8px 12px;
            border-bottom: 1px solid var(--border);
            color: var(--ink);
            vertical-align: middle;
            position: relative;
            cursor: pointer;
            transition: background 100ms ease;
        }
        table.studio-grid tbody tr:last-child td { border-bottom: none; }
        table.studio-grid tbody tr:hover td { background: var(--hover); }
        table.studio-grid tbody td.lead { font-weight: 550; color: var(--ink); }
        .cell-bar-wrap {
            position: relative;
            display: inline-flex;
            align-items: center;
            justify-content: flex-end;
            width: 100%;
        }
        .cell-bar {
            position: absolute;
            right: -4px;
            top: -2px;
            bottom: -2px;
            border-radius: 4px;
            background: var(--accent-soft);
            pointer-events: none;
            z-index: 0;
        }
        .cell-val { position: relative; z-index: 1; }
        .status-chip {
            display: inline-block;
            padding: 1.5px 7px;
            border-radius: 999px;
            font-size: 11px;
            font-weight: 550;
            background: var(--surface);
            color: var(--ink-2);
            border: 1px solid var(--border);
        }
        .status-chip.ok { background: var(--green-soft); color: var(--green); border-color: transparent; }
        .status-chip.warn { background: var(--amber-soft); color: var(--amber); border-color: transparent; }

        /* Chart Views */
        .chart-pad {
            padding: 14px 16px;
            height: 100%;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        .bar-list { display: flex; flex-direction: column; gap: 11px; }
        .bar-row {
            display: grid;
            grid-template-columns: minmax(90px, 140px) 1fr auto;
            align-items: center;
            gap: 12px;
        }
        .bar-label {
            font-size: 12px;
            font-weight: 500;
            color: var(--ink);
            text-align: right;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .bar-track {
            height: 22px;
            background: var(--surface);
            border-radius: 6px;
            overflow: hidden;
            position: relative;
        }
        .bar-fill {
            height: 100%;
            border-radius: 6px;
            transition: width 260ms cubic-bezier(0.22, 1, 0.36, 1);
        }
        .bar-val {
            font-size: 12px;
            font-weight: 550;
            font-variant-numeric: tabular-nums;
            color: var(--ink-2);
            min-width: 72px;
            text-align: right;
        }
        .donut-wrap {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 28px;
            height: 100%;
        }
        .donut-legend {
            display: flex;
            flex-direction: column;
            gap: 7px;
            min-width: 170px;
            max-width: 260px;
        }
        .legend-row {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 12px;
        }
        .legend-dot {
            width: 8px;
            height: 8px;
            border-radius: 2.5px;
            flex-shrink: 0;
        }
        .legend-name {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            color: var(--ink);
        }
        .legend-val {
            color: var(--ink-2);
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
        }
        .empty-state {
            height: 100%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--ink-3);
            font-size: 12.5px;
        }
        .tooltip, .toast {
            position: fixed;
            pointer-events: none;
            background: rgba(21, 25, 34, 0.92);
            color: #f8fafc;
            padding: 5px 9px;
            border-radius: 6px;
            font-size: 11px;
            font-variant-numeric: tabular-nums;
            opacity: 0;
            transition: opacity 110ms ease;
            z-index: 99;
            white-space: nowrap;
        }
        .toast {
            left: 50%;
            bottom: 14px;
            transform: translateX(-50%);
        }
        """
    
    
    private static let interactiveStudioBodyHTML: String = """
        <div class="shell">
            <div class="topbar">
                <div class="segmented" id="modeTabs">
                    <button class="seg-btn" data-mode="table" onclick="setMode('table')">交互表格</button>
                    <button class="seg-btn" data-mode="bar" onclick="setMode('bar')">柱状对比</button>
                    <button class="seg-btn" data-mode="line" onclick="setMode('line')">趋势折线</button>
                    <button class="seg-btn" data-mode="pie" onclick="setMode('pie')">占比环图</button>
                </div>
                <div class="tools" id="toolsBar">
                    <input id="filterInput" class="filter-input" type="text" placeholder="筛选" oninput="render()" style="display:none" />
                    <select id="metricSelect" class="metric-select" onchange="render()" style="display:none"></select>
                    <span id="metaPill" class="meta-pill"></span>
                    <button id="copyBtn" class="tool-btn" onclick="copyCSV()" style="display:none">复制 CSV</button>
                </div>
            </div>
            <div id="stage" class="stage"></div>
        </div>
        <div id="tooltip" class="tooltip"></div>
        <div id="toast" class="toast">已复制</div>
        """
    
    
    private static let interactiveStudioScript: String = """
        const COLORS = ['#2f7cf6','#5a95f8','#27a579','#e08a2d','#7c6ef0','#d95b7a','#1ea5b8'];
        let mode = 'table';
        let sortCol = -1;
        let sortAsc = true;
        let numericCols = [];
        let toastTimer = null;

        function esc(s) {
            return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
        }

        function parseNum(v) {
            if (v === null || v === undefined) return NaN;
            const raw = String(v).trim();
            if (!raw || /^\\d{1,2}:\\d{2}(:\\d{2})?$/.test(raw)) return NaN;
            const cleaned = raw.replace(/[,%$¥￥\\s]/g, '');
            const m = cleaned.match(/^-?\\d+(\\.\\d+)?/);
            if (!m) return NaN;
            let n = parseFloat(m[0]);
            if (raw.includes('亿')) n *= 1e8;
            else if (raw.includes('万')) n *= 1e4;
            return n;
        }

        function isNumericCol(c) {
            const rows = DATA.rows || [];
            if (!rows.length) return false;
            let ok = 0;
            for (const r of rows) {
                if (!isNaN(parseNum(r[c]))) ok++;
            }
            return ok > 0 && ok >= Math.ceil(rows.length * 0.6);
        }

        function showToast(msg) {
            const t = document.getElementById('toast');
            t.textContent = msg;
            t.style.opacity = '1';
            clearTimeout(toastTimer);
            toastTimer = setTimeout(() => { t.style.opacity = '0'; }, 1100);
        }

        function copyText(str, label) {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(str).then(() => showToast(label || '已复制')).catch(() => {});
            } else {
                const ta = document.createElement('textarea');
                ta.value = str;
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
                showToast(label || '已复制');
            }
        }

        function copyCSV() {
            const headers = DATA.headers || [];
            const rows = DATA.rows || [];
            const escCSV = v => {
                const s = String(v ?? '');
                return (s.includes(',') || s.includes('"') || s.includes('\\n')) ? '"' + s.replace(/"/g, '""') + '"' : s;
            };
            const csv = [headers.map(escCSV).join(','), ...rows.map(r => headers.map((_, c) => escCSV(r[c])).join(','))].join('\\n');
            copyText(csv, '已复制 CSV');
        }

        function showTip(e, text) {
            const t = document.getElementById('tooltip');
            t.textContent = text;
            const x = Math.min(window.innerWidth - 160, e.clientX + 12);
            const y = Math.max(8, e.clientY - 28);
            t.style.left = x + 'px';
            t.style.top = y + 'px';
            t.style.opacity = '1';
        }
        function hideTip() { document.getElementById('tooltip').style.opacity = '0'; }

        function init() {
            const headers = DATA.headers || [];
            const rows = DATA.rows || [];
            const sel = document.getElementById('metricSelect');
            sel.innerHTML = '';
            numericCols = [];
            let bestMetricCol = -1;
            let bestScore = -1;

            for (let c = 1; c < headers.length; c++) {
                if (isNumericCol(c)) {
                    numericCols.push(c);
                    const vals = rows.map(r => Math.abs(parseNum(r[c]) || 0));
                    const maxV = Math.max(0, ...vals);
                    const score = maxV > 0 ? (vals.filter(v => v > 0).length * 10 + (new Set(vals).size > 1 ? 5 : 1)) : 0;
                    if (score > bestScore) {
                        bestScore = score;
                        bestMetricCol = c;
                    }
                }
            }

            numericCols.forEach(c => {
                const opt = document.createElement('option');
                opt.value = c;
                opt.textContent = headers[c] || ('列 ' + (c + 1));
                sel.appendChild(opt);
            });
            if (bestMetricCol >= 0) sel.value = String(bestMetricCol);

            const hasCharts = rows.length > 0 && numericCols.length > 0;
            document.querySelectorAll('.seg-btn').forEach(btn => {
                const m = btn.dataset.mode;
                if (m !== 'table') btn.disabled = !hasCharts;
            });

            mode = (hasCharts && bestScore >= 5 && headers.length >= 3) ? 'bar' : 'table';
            updateTabUI();
            render();
        }

        function updateTabUI() {
            document.querySelectorAll('.seg-btn').forEach(b => {
                b.classList.toggle('active', b.dataset.mode === mode);
            });
            const hasRows = (DATA.rows || []).length > 0;
            document.getElementById('filterInput').style.display = (mode === 'table' && hasRows) ? 'block' : 'none';
            document.getElementById('copyBtn').style.display = (mode === 'table' && hasRows) ? 'inline-flex' : 'none';
            document.getElementById('metricSelect').style.display = (mode !== 'table' && numericCols.length > 0) ? 'block' : 'none';
        }

        function setMode(m) {
            if (m !== 'table' && numericCols.length === 0) return;
            mode = m;
            updateTabUI();
            render();
        }

        function sortBy(c) {
            if (sortCol === c) sortAsc = !sortAsc;
            else { sortCol = c; sortAsc = true; }
            render();
        }

        function formatCellHTML(val, colIdx, colMax) {
            const text = String(val ?? '');
            const lower = text.trim().toLowerCase();
            if (colIdx > 0 && (lower === 'noop' || lower === '无' || lower === 'ok' || lower === '完整' || lower === '正常' || lower === 'pass')) {
                return `<span class="status-chip ok">${esc(text)}</span>`;
            }
            if (colIdx > 0 && (lower === 'error' || lower === 'failed' || lower === '异常' || lower === '缺失')) {
                return `<span class="status-chip warn">${esc(text)}</span>`;
            }
            if (colMax > 0) {
                const n = parseNum(text);
                if (!isNaN(n) && n > 0) {
                    const pct = Math.max(4, Math.min(100, Math.round((Math.abs(n) / colMax) * 100)));
                    return `<div class="cell-bar-wrap"><span class="cell-bar" style="width:${pct}%"></span><span class="cell-val">${esc(text)}</span></div>`;
                }
            }
            return esc(text);
        }

        function render() {
            const stage = document.getElementById('stage');
            const headers = DATA.headers || [];
            const allRows = DATA.rows || [];
            const meta = document.getElementById('metaPill');

            if (!headers.length || !allRows.length) {
                meta.textContent = '';
                stage.innerHTML = '<div class="empty-state">未识别到表格数据</div>';
                return;
            }

            if (mode === 'table') {
                const q = (document.getElementById('filterInput').value || '').trim().toLowerCase();
                let rows = q ? allRows.filter(r => r.some(cell => String(cell ?? '').toLowerCase().includes(q))) : [...allRows];
                if (sortCol >= 0) {
                    rows.sort((a, b) => {
                        const na = parseNum(a[sortCol]), nb = parseNum(b[sortCol]);
                        const cmp = (!isNaN(na) && !isNaN(nb)) ? (na - nb) : String(a[sortCol] || '').localeCompare(String(b[sortCol] || ''), 'zh-CN');
                        return sortAsc ? cmp : -cmp;
                    });
                }
                meta.textContent = rows.length + ' 行 · ' + headers.length + ' 列';
                const colMaxes = headers.map((_, c) => {
                    if (c === 0 || !numericCols.includes(c)) return 0;
                    return Math.max(0, ...allRows.map(r => Math.abs(parseNum(r[c]) || 0)));
                });
                const ths = headers.map((h, idx) => {
                    const cls = numericCols.includes(idx) ? 'num' : '';
                    const arrow = sortCol === idx ? (sortAsc ? ' ↑' : ' ↓') : '';
                    return `<th class="${cls}" onclick="sortBy(${idx})">${esc(h)}${arrow}</th>`;
                }).join('');
                const trs = rows.map(r => {
                    const tds = headers.map((_, c) => {
                        const isNum = numericCols.includes(c);
                        const cls = c === 0 ? 'lead' : (isNum ? 'num' : '');
                        const cellVal = r[c] ?? '';
                        return `<td class="${cls}" data-copy="${esc(cellVal)}" onclick="copyText(this.dataset.copy)">${formatCellHTML(cellVal, c, colMaxes[c])}</td>`;
                    }).join('');
                    return `<tr>${tds}</tr>`;
                }).join('');
                stage.innerHTML = `<table class="studio-grid"><thead><tr>${ths}</tr></thead><tbody>${trs}</tbody></table>`;
                return;
            }

            const col = parseInt(document.getElementById('metricSelect').value || String(numericCols[0] ?? 1), 10);
            const items = allRows.map((r, i) => ({
                label: String(r[0] || ('#' + (i + 1))),
                raw: String(r[col] ?? '0'),
                val: isNaN(parseNum(r[col])) ? 0 : parseNum(r[col])
            }));
            const maxVal = Math.max(1e-6, ...items.map(d => Math.abs(d.val)));
            meta.textContent = items.length + ' 项';

            if (mode === 'bar') {
                const html = items.map((d, i) => {
                    const pct = d.val === 0 ? 1.5 : Math.max(4, Math.round((Math.abs(d.val) / maxVal) * 100));
                    const color = COLORS[i % COLORS.length];
                    const tip = esc(d.label + '：' + d.raw);
                    return `<div class="bar-row" data-tip="${tip}" onmousemove="showTip(event, this.dataset.tip)" onmouseleave="hideTip()">
                        <div class="bar-label" title="${esc(d.label)}">${esc(d.label)}</div>
                        <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${color}"></div></div>
                        <div class="bar-val">${esc(d.raw)}</div>
                    </div>`;
                }).join('');
                stage.innerHTML = `<div class="chart-pad"><div class="bar-list">${html}</div></div>`;
            } else if (mode === 'line') {
                const w = 580, h = 220, padX = 44, padTop = 26, padBot = 32;
                const plotW = w - padX * 2, plotH = h - padTop - padBot;
                const pts = items.map((d, i) => {
                    const x = padX + (items.length <= 1 ? plotW / 2 : (i / (items.length - 1)) * plotW);
                    const y = padTop + plotH - (Math.max(0, d.val) / maxVal) * plotH;
                    return { x, y, d };
                });
                const poly = pts.map(p => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
                const area = `${pts[0].x.toFixed(1)},${(padTop + plotH).toFixed(1)} ${poly} ${pts[pts.length - 1].x.toFixed(1)},${(padTop + plotH).toFixed(1)}`;
                const grids = [0, 0.5, 1].map(f => {
                    const gy = padTop + plotH * (1 - f);
                    return `<line x1="${padX}" y1="${gy}" x2="${w - padX}" y2="${gy}" stroke="var(--border)" stroke-width="1" stroke-dasharray="3 3"/>`;
                }).join('');
                const nodes = pts.map(p => {
                    const tip = esc(p.d.label + '：' + p.d.raw);
                    return `<circle cx="${p.x}" cy="${p.y}" r="4.5" fill="var(--bg)" stroke="var(--accent)" stroke-width="2.2" style="cursor:pointer" data-tip="${tip}" onmousemove="showTip(event, this.dataset.tip)" onmouseleave="hideTip()"/>
                        <text x="${p.x}" y="${h - 10}" text-anchor="middle" font-size="10.5" fill="var(--ink-2)">${esc(p.d.label.slice(0, 12))}</text>
                        <text x="${p.x}" y="${p.y - 10}" text-anchor="middle" font-size="10.5" font-weight="600" fill="var(--ink)">${esc(p.d.raw)}</text>`;
                }).join('');
                stage.innerHTML = `<div class="chart-pad"><svg width="100%" height="100%" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">
                    <defs><linearGradient id="ag" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="var(--accent)" stop-opacity="0.22"/><stop offset="100%" stop-color="var(--accent)" stop-opacity="0.01"/></linearGradient></defs>
                    ${grids}
                    <polygon points="${area}" fill="url(#ag)"/>
                    <polyline fill="none" stroke="var(--accent)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" points="${poly}"/>
                    ${nodes}
                </svg></div>`;
            } else {
                const total = Math.max(1e-6, items.reduce((s, d) => s + Math.max(0, d.val), 0));
                let acc = 0;
                const r = 68, cx = 104, cy = 104, circum = 2 * Math.PI * r;
                const arcs = items.map((d, i) => {
                    const frac = Math.max(0, d.val) / total;
                    const len = frac * circum;
                    const offset = -acc * circum;
                    acc += frac;
                    const color = COLORS[i % COLORS.length];
                    const tip = esc(d.label + '：' + d.raw + ' (' + (frac * 100).toFixed(1) + '%)');
                    return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="transparent" stroke="${color}" stroke-width="22"
                        stroke-dasharray="${len.toFixed(2)} ${circum.toFixed(2)}" stroke-dashoffset="${offset.toFixed(2)}"
                        transform="rotate(-90 ${cx} ${cy})"
                        data-tip="${tip}" onmousemove="showTip(event, this.dataset.tip)" onmouseleave="hideTip()"/>`;
                }).join('');
                const legend = items.map((d, i) => {
                    const pct = ((Math.max(0, d.val) / total) * 100).toFixed(1);
                    return `<div class="legend-row">
                        <span class="legend-dot" style="background:${COLORS[i % COLORS.length]}"></span>
                        <span class="legend-name" title="${esc(d.label)}">${esc(d.label)}</span>
                        <span class="legend-val">${esc(d.raw)} · ${pct}%</span>
                    </div>`;
                }).join('');
                stage.innerHTML = `<div class="chart-pad"><div class="donut-wrap">
                    <svg width="208" height="208" viewBox="0 0 208 208">
                        <circle cx="${cx}" cy="${cy}" r="${r}" fill="transparent" stroke="var(--surface)" stroke-width="22"/>
                        ${arcs}
                    </svg>
                    <div class="donut-legend">${legend}</div>
                </div></div>`;
            }
        }
        init();
        """
    
    
    // MARK: Private Table Parsing & Formatting Helpers
    
    private static func isMarkdownPipeTableRow(_ line: String) -> Bool {
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("|"), !trimmed.hasPrefix("```") else { return false }
        return self.parseCells(in: trimmed).count >= 2
    }
    
    
    private static func isTabTableRow(_ line: String) -> Bool {
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("```"), !trimmed.hasPrefix("- "), !trimmed.hasPrefix("* ") else {
            return false
        }
        // Must contain at least one internal Tab separating two non-empty cells (ignoring leading indent Tabs)
        let afterLeading = line.drop { $0 == "\t" }
        guard afterLeading.contains("\t") else { return false }
        let parts = afterLeading.split(separator: "\t", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.count >= 2
    }
    
    
    private static func parseTabCells(in line: String, strippingLeading leadingTabs: String) -> [String] {
        
        let body = line.hasPrefix(leadingTabs) ? String(line.dropFirst(leadingTabs.count)) : line
        return body
            .split(separator: "\t", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    
    private static func isSeparatorRow(_ line: String) -> Bool {
        
        let cells = self.parseCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { return false }
            return stripped.allSatisfy { $0 == "-" || $0 == ":" } && stripped.contains("-")
        }
    }
    
    
    private static func parseCells(in line: String) -> [String] {
        
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    
    private static func cleanCellText(_ raw: String) -> String {
        
        AIDocumentTextCleaner.cleanStructuredPlainText(raw)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    
    
    private static func formatMarkdownTableBlock(
        _ lines: [String],
        metrics: AIDocumentTextCleaner.TableLayoutMetrics?
    ) -> [String] {
        
        let parsedRows = lines.map { self.parseCells(in: $0) }
        let columnCount = parsedRows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return lines }
        
        var alignments = [ColumnAlignment](repeating: .left, count: columnCount)
        for (rowIndex, line) in lines.enumerated() where self.isSeparatorRow(line) {
            let cells = parsedRows[rowIndex]
            for (colIndex, cell) in cells.enumerated() where colIndex < columnCount {
                let stripped = cell.trimmingCharacters(in: .whitespaces)
                if stripped.hasPrefix(":"), stripped.hasSuffix(":") {
                    alignments[colIndex] = .center
                } else if stripped.hasSuffix(":") {
                    alignments[colIndex] = .right
                } else {
                    alignments[colIndex] = .left
                }
            }
        }
        
        let leadingIndent = String(lines[0].prefix { $0 == " " || $0 == "\t" })
        
        if let metrics {
            let spaceW = max(1.0, metrics.spaceWidth)
            let hyphenW = max(1.0, metrics.hyphenWidth)
            var maxWidths = [CGFloat](repeating: hyphenW * 3, count: columnCount)
            for (rowIndex, cells) in parsedRows.enumerated() where !self.isSeparatorRow(lines[rowIndex]) {
                for colIndex in 0..<columnCount {
                    let cell = colIndex < cells.count ? cells[colIndex] : ""
                    maxWidths[colIndex] = max(maxWidths[colIndex], metrics.measureWidth(cell))
                }
            }
            
            return lines.enumerated().map { rowIndex, originalLine in
                let cells = parsedRows[rowIndex]
                if self.isSeparatorRow(originalLine) {
                    let sepCells = (0..<columnCount).map { colIndex -> String in
                        let dashCount = max(3, Int((maxWidths[colIndex] / hyphenW).rounded()))
                        switch alignments[colIndex] {
                            case .left:
                                return String(repeating: "-", count: dashCount)
                            case .center:
                                return ":" + String(repeating: "-", count: max(1, dashCount - 2)) + ":"
                            case .right:
                                return String(repeating: "-", count: max(1, dashCount - 1)) + ":"
                        }
                    }
                    return leadingIndent + "| " + sepCells.joined(separator: " | ") + " |"
                } else {
                    let formattedCells = (0..<columnCount).map { colIndex -> String in
                        let cell = colIndex < cells.count ? cells[colIndex] : ""
                        let cellW = metrics.measureWidth(cell)
                        let pad = max(0, Int(((maxWidths[colIndex] - cellW) / spaceW).rounded()))
                        switch alignments[colIndex] {
                            case .left:
                                return cell + String(repeating: " ", count: pad)
                            case .right:
                                return String(repeating: " ", count: pad) + cell
                            case .center:
                                let leftPad = pad / 2
                                let rightPad = pad - leftPad
                                return String(repeating: " ", count: leftPad) + cell + String(repeating: " ", count: rightPad)
                        }
                    }
                    return leadingIndent + "| " + formattedCells.joined(separator: " | ") + " |"
                }
            }
        }
        
        // Headless East-Asian monospace display width alignment
        var widths = [Int](repeating: 3, count: columnCount)
        for (rowIndex, cells) in parsedRows.enumerated() where !self.isSeparatorRow(lines[rowIndex]) {
            for colIndex in 0..<columnCount {
                let cell = colIndex < cells.count ? cells[colIndex] : ""
                widths[colIndex] = max(widths[colIndex], self.displayWidth(of: cell))
            }
        }
        
        return lines.enumerated().map { rowIndex, originalLine in
            let cells = parsedRows[rowIndex]
            if self.isSeparatorRow(originalLine) {
                let sepCells = (0..<columnCount).map { colIndex -> String in
                    let colWidth = max(3, widths[colIndex])
                    switch alignments[colIndex] {
                        case .left:
                            return String(repeating: "-", count: colWidth)
                        case .center:
                            return ":" + String(repeating: "-", count: max(1, colWidth - 2)) + ":"
                        case .right:
                            return String(repeating: "-", count: max(1, colWidth - 1)) + ":"
                    }
                }
                return leadingIndent + "| " + sepCells.joined(separator: " | ") + " |"
            } else {
                let formattedCells = (0..<columnCount).map { colIndex -> String in
                    let cell = colIndex < cells.count ? cells[colIndex] : ""
                    let pad = max(0, widths[colIndex] - self.displayWidth(of: cell))
                    switch alignments[colIndex] {
                        case .left:
                            return cell + String(repeating: " ", count: pad)
                        case .right:
                            return String(repeating: " ", count: pad) + cell
                        case .center:
                            let leftPad = pad / 2
                            let rightPad = pad - leftPad
                            return String(repeating: " ", count: leftPad) + cell + String(repeating: " ", count: rightPad)
                    }
                }
                return leadingIndent + "| " + formattedCells.joined(separator: " | ") + " |"
            }
        }
    }
    
    
    /// Monospace display width of a string, counting East-Asian full-width / CJK / emoji characters as 2 columns.
    static func displayWidth(of string: String) -> Int {
        
        var total = 0
        for scalar in string.unicodeScalars {
            if scalar.isZeroWidthScalar {
                continue
            } else if scalar.isEastAsianWide {
                total += 2
            } else {
                total += 1
            }
        }
        return total
    }
}


private extension Unicode.Scalar {
    
    var isZeroWidthScalar: Bool {
        let val = self.value
        return (0x0300...0x036F).contains(val)
            || (0x200B...0x200D).contains(val)
            || val == 0xFEFF
            || (0xFE00...0xFE0F).contains(val)
    }
    
    var isEastAsianWide: Bool {
        let val = self.value
        return (0x1100...0x115F).contains(val)
            || (0x2E80...0xA4CF).contains(val)
            || (0xAC00...0xD7A3).contains(val)
            || (0xF900...0xFAFF).contains(val)
            || (0xFE10...0xFE6F).contains(val)
            || (0xFF00...0xFF60).contains(val)
            || (0xFFE0...0xFFE6).contains(val)
            || (0x1F300...0x1FAFF).contains(val)
            || (0x20000...0x3FFFD).contains(val)
    }
}
