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

import Foundation

/// Aligns Markdown tables with East-Asian display width (CJK = 2 columns, ASCII = 1 column)
/// and extracts numeric/categorical data to render an instant interactive HTML chart even
/// before or alongside an AI chart request.
nonisolated enum MarkdownTableFormatter {
    
    enum ColumnAlignment: Sendable {
        case left
        case center
        case right
    }
    
    
    /// Formats all Markdown tables found inside `text` so columns align visually in monospaced fonts.
    ///
    /// - Parameter text: A selection or document string containing one or more Markdown tables.
    /// - Returns: The string with all Markdown tables aligned.
    static func formatTables(in text: String) -> String {
        
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        
        var output: [String] = []
        var index = 0
        
        while index < lines.count {
            if self.isTableRow(lines[index]) {
                var block: [String] = []
                while index < lines.count, self.isTableRow(lines[index]) {
                    block.append(lines[index])
                    index += 1
                }
                if block.count >= 2 {
                    output.append(contentsOf: self.formatTableBlock(block))
                } else {
                    output.append(contentsOf: block)
                }
            } else {
                output.append(lines[index])
                index += 1
            }
        }
        
        return output.joined(separator: "\n")
    }
    
    
    /// Checks whether `text` contains at least one Markdown table.
    static func containsMarkdownTable(_ text: String) -> Bool {
        
        let lines = text.components(separatedBy: .newlines)
        var consecutive = 0
        for line in lines {
            if self.isTableRow(line) {
                consecutive += 1
                if consecutive >= 2 { return true }
            } else {
                consecutive = 0
            }
        }
        return false
    }
    
    
    /// Builds a self-contained interactive HTML chart from a Markdown table (used as an instant preview
    /// or fallback if AI is not configured, and as the base template for interactive charts).
    static func generateInstantChartHTML(from text: String, aiInsightMarkdown: String? = nil) -> String {
        
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { self.isTableRow($0) }
        
        var rows: [[String]] = []
        for line in lines where !self.isSeparatorRow(line) {
            rows.append(self.parseCells(in: line))
        }
        
        let headers = rows.first ?? ["项目", "数值"]
        let dataRows = Array(rows.dropFirst())
        
        // Encode rows as JSON for the interactive JS chart
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
        :root {
            color-scheme: light dark;
            --bg: #ffffff;
            --card: #f7f8fa;
            --border: rgba(128,128,128,0.22);
            --text: #1d1d1f;
            --sub: #6e6e73;
            --accent: #007aff;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #1e1e1e;
                --card: #28282b;
                --border: rgba(255,255,255,0.14);
                --text: #f5f5f7;
                --sub: #98989d;
                --accent: #0a84ff;
            }
        }
        * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
        body { margin: 0; padding: 14px; background: var(--bg); color: var(--text); }
        .toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; gap: 8px; flex-wrap: wrap; }
        .tabs { display: inline-flex; background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 2px; }
        .tab { border: none; background: transparent; color: var(--sub); padding: 5px 12px; border-radius: 6px; font-size: 12px; cursor: pointer; font-weight: 500; }
        .tab.active { background: var(--accent); color: #fff; }
        .metric-select { background: var(--card); color: var(--text); border: 1px solid var(--border); border-radius: 6px; padding: 4px 8px; font-size: 12px; }
        .chart-card { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 16px; min-height: 240px; position: relative; }
        .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; font-size: 12px; }
        .bar-label { width: 110px; text-align: right; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: var(--text); font-weight: 500; }
        .bar-track { flex: 1; height: 22px; background: rgba(128,128,128,0.12); border-radius: 6px; overflow: hidden; position: relative; }
        .bar-fill { height: 100%; border-radius: 6px; transition: width 0.35s cubic-bezier(0.22,1,0.36,1); display: flex; align-items: center; padding-left: 8px; color: #fff; font-size: 11px; font-weight: 600; }
        .bar-val { width: 70px; font-variant-numeric: tabular-nums; color: var(--sub); font-size: 12px; }
        table.data-grid { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 8px; }
        table.data-grid th, table.data-grid td { padding: 7px 10px; border-bottom: 1px solid var(--border); text-align: left; }
        table.data-grid th { color: var(--sub); cursor: pointer; user-select: none; }
        table.data-grid tr:hover td { background: rgba(128,128,128,0.08); }
        svg.line-svg { width: 100%; height: 220px; overflow: visible; }
        .tooltip { position: fixed; pointer-events: none; background: rgba(20,20,24,0.92); color: #fff; padding: 6px 10px; border-radius: 6px; font-size: 11px; opacity: 0; transition: opacity 0.12s; z-index: 99; }
        </style>
        </head>
        <body>
        <div class="toolbar">
            <div class="tabs">
                <button class="tab active" onclick="setMode('bar')">柱状对比</button>
                <button class="tab" onclick="setMode('line')">趋势折线</button>
                <button class="tab" onclick="setMode('pie')">占比环图</button>
                <button class="tab" onclick="setMode('table')">交互表格</button>
            </div>
            <select id="metricSelect" class="metric-select" onchange="render()"></select>
        </div>
        <div id="canvas" class="chart-card"></div>
        <div id="tooltip" class="tooltip"></div>
        <script>
        const DATA = \(jsonString);
        const COLORS = ['#007aff','#34c759','#ff9500','#af52de','#ff2d55','#5856d6','#00c7be'];
        let mode = 'bar';
        let sortCol = -1;
        let sortAsc = true;

        function parseNum(v) {
            if (!v) return NaN;
            const cleaned = String(v).replace(/[,%$¥￥\\s]/g, '');
            const m = cleaned.match(/-?\\d+(\\.\\d+)?/);
            return m ? parseFloat(m[0]) : NaN;
        }

        function init() {
            const sel = document.getElementById('metricSelect');
            sel.innerHTML = '';
            const headers = DATA.headers || [];
            let numericCols = [];
            for (let c = 1; c < headers.length; c++) {
                const hasNum = (DATA.rows || []).some(r => !isNaN(parseNum(r[c])));
                if (hasNum) numericCols.push(c);
            }
            if (numericCols.length === 0 && headers.length > 1) numericCols.push(1);
            numericCols.forEach((c, idx) => {
                const opt = document.createElement('option');
                opt.value = c;
                opt.textContent = '指标: ' + (headers[c] || ('列 ' + c));
                sel.appendChild(opt);
            });
            render();
        }

        function setMode(m) {
            mode = m;
            document.querySelectorAll('.tab').forEach((b, i) => {
                b.classList.toggle('active', ['bar','line','pie','table'][i] === m);
            });
            render();
        }

        function showTip(e, text) {
            const t = document.getElementById('tooltip');
            t.textContent = text;
            t.style.left = (e.clientX + 12) + 'px';
            t.style.top = (e.clientY - 24) + 'px';
            t.style.opacity = 1;
        }
        function hideTip() { document.getElementById('tooltip').style.opacity = 0; }

        function render() {
            const box = document.getElementById('canvas');
            const col = parseInt(document.getElementById('metricSelect').value || '1', 10);
            const rows = DATA.rows || [];
            const items = rows.map((r, i) => ({
                label: r[0] || ('#' + (i + 1)),
                raw: r[col] || '0',
                val: isNaN(parseNum(r[col])) ? 0 : parseNum(r[col]),
                row: r
            }));
            const maxVal = Math.max(1, ...items.map(d => Math.abs(d.val)));

            if (mode === 'bar') {
                box.innerHTML = items.map((d, i) => {
                    const pct = Math.max(4, Math.round((Math.abs(d.val) / maxVal) * 100));
                    const color = COLORS[i % COLORS.length];
                    return `<div class="bar-row" onmousemove="showTip(event, '${d.label}: ${d.raw}')" onmouseleave="hideTip()">
                        <div class="bar-label" title="${d.label}">${d.label}</div>
                        <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${color}"></div></div>
                        <div class="bar-val">${d.raw}</div>
                    </div>`;
                }).join('');
            } else if (mode === 'line') {
                const w = 520, h = 190, pad = 32;
                const pts = items.map((d, i) => {
                    const x = pad + (items.length <= 1 ? (w - pad*2)/2 : (i / (items.length - 1)) * (w - pad*2));
                    const y = h - pad - (d.val / maxVal) * (h - pad*2);
                    return { x, y, d };
                });
                const poly = pts.map(p => `${p.x},${p.y}`).join(' ');
                const circles = pts.map((p, i) =>
                    `<circle cx="${p.x}" cy="${p.y}" r="5" fill="#007aff" style="cursor:pointer" onmousemove="showTip(event, '${p.d.label}: ${p.d.raw}')" onmouseleave="hideTip()"/>
                     <text x="${p.x}" y="${h - 8}" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.7">${p.d.label.slice(0,8)}</text>
                     <text x="${p.x}" y="${p.y - 10}" text-anchor="middle" font-size="10" fill="currentColor">${p.d.raw}</text>`
                ).join('');
                box.innerHTML = `<svg class="line-svg" viewBox="0 0 ${w} ${h}">
                    <polyline fill="none" stroke="#007aff" stroke-width="2.5" points="${poly}"/>
                    ${circles}
                </svg>`;
            } else if (mode === 'pie') {
                const total = Math.max(1e-6, items.reduce((s, d) => s + Math.max(0, d.val), 0));
                let acc = 0;
                const r = 70, cx = 110, cy = 100, circum = 2 * Math.PI * r;
                const arcs = items.map((d, i) => {
                    const frac = Math.max(0, d.val) / total;
                    const len = frac * circum;
                    const offset = -acc * circum;
                    acc += frac;
                    const color = COLORS[i % COLORS.length];
                    return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="transparent" stroke="${color}" stroke-width="26"
                        stroke-dasharray="${len} ${circum}" stroke-dashoffset="${offset}"
                        onmousemove="showTip(event, '${d.label}: ${d.raw} (${(frac*100).toFixed(1)}%)')" onmouseleave="hideTip()"/>`;
                }).join('');
                const legend = items.map((d, i) => {
                    const pct = ((Math.max(0, d.val) / total) * 100).toFixed(1);
                    return `<div style="display:flex;align-items:center;gap:6px;margin-bottom:6px;font-size:12px">
                        <span style="width:10px;height:10px;border-radius:3px;background:${COLORS[i % COLORS.length]};display:inline-block"></span>
                        <span style="flex:1">${d.label}</span>
                        <span style="color:var(--sub)">${d.raw} (${pct}%)</span>
                    </div>`;
                }).join('');
                box.innerHTML = `<div style="display:flex;align-items:center;gap:20px;flex-wrap:wrap">
                    <svg width="220" height="200" viewBox="0 0 220 200">${arcs}</svg>
                    <div style="flex:1;min-width:160px">${legend}</div>
                </div>`;
            } else {
                const headers = DATA.headers || [];
                let sorted = [...rows];
                if (sortCol >= 0) {
                    sorted.sort((a, b) => {
                        const na = parseNum(a[sortCol]), nb = parseNum(b[sortCol]);
                        const cmp = (!isNaN(na) && !isNaN(nb)) ? (na - nb) : String(a[sortCol]||'').localeCompare(String(b[sortCol]||''));
                        return sortAsc ? cmp : -cmp;
                    });
                }
                const ths = headers.map((h, idx) => `<th onclick="sortBy(${idx})">${h} ${sortCol===idx?(sortAsc?'↑':'↓'):''}</th>`).join('');
                const trs = sorted.map(r => `<tr>${headers.map((_, c) => `<td>${r[c] ?? ''}</td>`).join('')}</tr>`).join('');
                box.innerHTML = `<table class="data-grid"><thead><tr>${ths}</tr></thead><tbody>${trs}</tbody></table>`;
            }
        }

        function sortBy(c) {
            if (sortCol === c) sortAsc = !sortAsc;
            else { sortCol = c; sortAsc = true; }
            render();
        }
        init();
        </script>
        </body>
        </html>
        """
    }
    
    
    // MARK: Private Table Formatting Helpers
    
    private static func isTableRow(_ line: String) -> Bool {
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("|") else { return false }
        return true
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
    
    
    private static func formatTableBlock(_ lines: [String]) -> [String] {
        
        let parsedRows = lines.map { self.parseCells(in: $0) }
        let columnCount = parsedRows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return lines }
        
        // Determine alignment per column from any separator row
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
        
        // Compute max display width for each column across non-separator rows
        var widths = [Int](repeating: 3, count: columnCount)
        for (rowIndex, cells) in parsedRows.enumerated() where !self.isSeparatorRow(lines[rowIndex]) {
            for colIndex in 0..<columnCount {
                let cell = colIndex < cells.count ? cells[colIndex] : ""
                widths[colIndex] = max(widths[colIndex], self.displayWidth(of: cell))
            }
        }
        
        // Preserve leading indentation of the first line
        let leadingIndent = String(lines[0].prefix { $0 == " " || $0 == "\t" })
        
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
