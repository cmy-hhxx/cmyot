//
//  FlowPresentationRenderer.swift
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

/// Pure HTML/CSS/JS renderer producing a Keynote-grade interactive flow presentation canvas
/// with zero external dependencies and strictly zero tiny explanatory prose.
nonisolated enum FlowPresentationRenderer {
    
    static func renderHTML(
        blueprint: FlowPresentationBlueprint,
        initialTheme: FlowPresentationTheme = .keynoteLight
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let jsonData = (try? encoder.encode(blueprint)) ?? Data("{}".utf8)
        let blueprintJSON = (String(data: jsonData, encoding: .utf8) ?? "{}")
            .replacingOccurrences(of: "</", with: "<\\/")
        return """
        <!doctype html>
        <html lang="zh-CN" data-theme="\(initialTheme.rawValue)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(Self.escapeHTML(blueprint.title))</title>
        <style>\(Self.cssStyles())</style>
        </head>
        <body>
        \(Self.bodyTemplate())
        <script>
        window.__INITIAL_BLUEPRINT__ = \(blueprintJSON);
        \(Self.jsRenderSection())
        \(Self.jsEventsSection())
        </script>
        </body>
        </html>
        """
    }
    
    
    private static func escapeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    
    private static func cssStyles() -> String {
        """
        :root {
          --bg: #f7f8fa; --surface: #ffffff; --inset: #f0f2f6; --ink: #111827; --ink2: #4b5563; --ink3: #6b7280;
          --line: rgba(17,24,39,0.09); --line-strong: rgba(17,24,39,0.20); --accent: #2563eb;
          --blue: #2563eb; --teal: #0d9488; --violet: #7c3aed; --amber: #d97706; --slate: #475569;
          --shadow: 0 10px 30px rgba(15,23,42,0.06);
        }
        html[data-theme="studioDark"] {
          --bg: #0f1117; --surface: #181c24; --inset: #222733; --ink: #f3f4f6; --ink2: #cbd5e1; --ink3: #94a3b8;
          --line: rgba(255,255,255,0.09); --line-strong: rgba(255,255,255,0.22); --accent: #60a5fa;
          --blue: #60a5fa; --teal: #2dd4bf; --violet: #a78bfa; --amber: #fbbf24; --slate: #94a3b8;
          --shadow: 0 12px 32px rgba(0,0,0,0.38);
        }
        html[data-theme="editorialPaper"] {
          --bg: #f5f1e8; --surface: #fcfaf4; --inset: #ebe4d5; --ink: #1f1b16; --ink2: #574f44; --ink3: #786e60;
          --line: rgba(31,27,22,0.10); --line-strong: rgba(31,27,22,0.22); --accent: #b45309;
          --blue: #1d4ed8; --teal: #0f766e; --violet: #6d28d9; --amber: #b45309; --slate: #57534e;
          --shadow: 0 10px 28px rgba(52,38,18,0.07);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", sans-serif;
          background: var(--bg); color: var(--ink); min-height: 100vh; padding: 20px 28px 28px;
          -webkit-font-smoothing: antialiased; user-select: none;
        }
        .topbar {
          display: flex; align-items: center; justify-content: space-between; gap: 16px;
          padding-bottom: 18px; border-bottom: 1px solid var(--line); margin-bottom: 24px;
        }
        .title-wrap { display: flex; align-items: center; gap: 12px; min-width: 0; }
        .doc-title { font-size: 22px; font-weight: 700; letter-spacing: -0.02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .layout-pill { font-size: 12px; font-weight: 600; color: var(--ink2); background: var(--inset); padding: 4px 10px; border-radius: 999px; }
        .toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .seg { display: inline-flex; background: var(--inset); padding: 3px; border-radius: 9px; gap: 2px; }
        .btn {
          border: none; background: transparent; color: var(--ink2); font-size: 12.5px; font-weight: 500;
          padding: 5px 11px; border-radius: 7px; cursor: pointer; transition: background 140ms, color 140ms;
        }
        .btn:hover { color: var(--ink); background: rgba(128,128,128,0.12); }
        .btn.active { background: var(--surface); color: var(--ink); box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
        .action-btn {
          border: 1px solid var(--line); background: var(--surface); color: var(--ink); font-size: 12.5px; font-weight: 500;
          padding: 6px 12px; border-radius: 8px; cursor: pointer;
        }
        .action-btn:hover { border-color: var(--line-strong); }
        .dots { display: flex; align-items: center; gap: 6px; margin-bottom: 20px; }
        .dot-btn {
          border: 1px solid var(--line); background: var(--surface); color: var(--ink2); font-size: 12px; font-weight: 600;
          font-variant-numeric: tabular-nums; padding: 4px 10px; border-radius: 999px; cursor: pointer;
        }
        .dot-btn.active { background: var(--ink); color: var(--surface); border-color: var(--ink); }
        .stage { display: flex; flex-direction: column; gap: 22px; max-width: 1280px; margin: 0 auto; }
        .steps-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; position: relative; }
        .step-card {
          position: relative; background: var(--surface); border: 1.5px solid var(--line); border-radius: 16px;
          padding: 18px 18px 16px; box-shadow: var(--shadow); cursor: pointer; transition: border-color 160ms, opacity 160ms;
          display: flex; flex-direction: column; gap: 10px;
        }
        .step-card:hover { border-color: var(--line-strong); }
        .step-card.dimmed { opacity: 0.32; }
        .step-card.focused { border-color: var(--accent); }
        .step-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        .step-idx {
          font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; padding: 3px 9px;
          border-radius: 7px; background: var(--inset); color: var(--ink);
        }
        .step-badge { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 12px; font-weight: 600; color: var(--ink2); }
        .step-title { font-size: 17px; font-weight: 650; line-height: 1.35; letter-spacing: -0.01em; }
        .step-summary { font-size: 13.5px; line-height: 1.55; color: var(--ink2); }
        .step-links { display: flex; flex-wrap: wrap; gap: 6px; margin-top: auto; padding-top: 4px; }
        .link-chip { font-family: ui-monospace, monospace; font-size: 12px; padding: 3px 8px; border-radius: 6px; background: var(--inset); color: var(--ink2); }
        .section-label { font-size: 13px; font-weight: 650; color: var(--ink2); letter-spacing: 0.02em; margin-bottom: 10px; }
        .artifacts-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 14px; }
        .art-card {
          background: var(--surface); border: 1.5px solid var(--line); border-radius: 14px; padding: 15px 16px;
          cursor: pointer; transition: border-color 160ms, opacity 160ms; display: flex; flex-direction: column; gap: 8px;
        }
        .art-card:hover { border-color: var(--line-strong); }
        .art-card.dimmed { opacity: 0.32; }
        .art-card.focused { border-color: var(--accent); }
        .art-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        .art-role { font-size: 14.5px; font-weight: 600; color: var(--ink); }
        .copy-btn {
          border: 1px solid var(--line); background: var(--inset); color: var(--ink2); font-size: 12px;
          padding: 3px 9px; border-radius: 6px; cursor: pointer;
        }
        .copy-btn:hover { color: var(--ink); border-color: var(--line-strong); }
        .art-path {
          font-family: ui-monospace, SFMono-Regular, monospace; font-size: 12.5px; color: var(--ink2);
          background: var(--inset); padding: 8px 10px; border-radius: 8px; word-break: break-all; user-select: text;
        }
        .branch-card {
          border: 1.5px dashed var(--line-strong); background: var(--surface); border-radius: 14px;
          padding: 15px 18px; display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap;
        }
        .branch-meta { display: flex; flex-direction: column; gap: 5px; min-width: 240px; flex: 1; }
        .branch-head { display: flex; align-items: center; gap: 8px; }
        .branch-tag { font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 6px; background: var(--inset); color: var(--ink2); }
        .takeaway {
          background: var(--inset); border-radius: 12px; padding: 14px 18px; font-size: 15px; font-weight: 550; color: var(--ink);
        }
        """
    }
    
    
    private static func bodyTemplate() -> String {
        """
        <header class="topbar">
          <div class="title-wrap">
            <h1 id="docTitle" class="doc-title"></h1>
            <span id="layoutPill" class="layout-pill"></span>
          </div>
          <div class="toolbar">
            <div class="seg" id="themeSeg">
              <button class="btn" data-theme="keynoteLight">纯净白板</button>
              <button class="btn" data-theme="studioDark">深邃画布</button>
              <button class="btn" data-theme="editorialPaper">暖纸简报</button>
            </div>
            <button class="action-btn" id="btnFullscreen">全屏</button>
            <button class="action-btn" id="btnExportPNG">导出 PNG</button>
            <button class="action-btn" id="btnExportHTML">导出 HTML</button>
          </div>
        </header>
        <main class="stage">
          <div class="dots" id="stepDots"></div>
          <section id="stepsSection">
            <div class="steps-row" id="stepsRow"></div>
          </section>
          <section id="artifactsSection">
            <div class="section-label">核心数据路径</div>
            <div class="artifacts-grid" id="artifactsGrid"></div>
          </section>
          <section id="branchesSection"></section>
          <section id="takeawaySection"></section>
        </main>
        """
    }
    
    
    private static func jsRenderSection() -> String {
        """
        let bp = window.__INITIAL_BLUEPRINT__;
        let activeStepId = null;
        let activeArtId = null;
        const post = (payload) => window.webkit?.messageHandlers?.cotFlowPre?.postMessage(payload);

        function setTheme(theme) {
          document.documentElement.setAttribute("data-theme", theme);
          document.querySelectorAll("#themeSeg .btn").forEach(b => b.classList.toggle("active", b.dataset.theme === theme));
        }

        function render() {
          document.getElementById("docTitle").textContent = bp.title || "流程概览";
          const layoutNames = { pipeline: "主链路", architecture: "分层架构", comparison: "对比视图", topology: "拓扑关系" };
          document.getElementById("layoutPill").textContent = layoutNames[bp.layout] || "主链路";

          const dots = document.getElementById("stepDots");
          dots.innerHTML = "";
          const allBtn = document.createElement("button");
          allBtn.className = "dot-btn" + (!activeStepId && !activeArtId ? " active" : "");
          allBtn.textContent = "全部";
          allBtn.onclick = () => { activeStepId = null; activeArtId = null; render(); };
          dots.appendChild(allBtn);

          (bp.steps || []).forEach(s => {
            const b = document.createElement("button");
            b.className = "dot-btn" + (activeStepId === s.id ? " active" : "");
            b.textContent = s.indexLabel;
            b.onclick = () => { activeArtId = null; activeStepId = activeStepId === s.id ? null : s.id; render(); };
            dots.appendChild(b);
          });

          const activeArt = (bp.artifacts || []).find(a => a.id === activeArtId);
          const activeStep = (bp.steps || []).find(s => s.id === activeStepId);

          const stepsRow = document.getElementById("stepsRow");
          stepsRow.innerHTML = "";
          (bp.steps || []).forEach(s => {
            const isFocus = activeStepId === s.id || (activeArt && (activeArt.linkedStepIDs || []).includes(s.id));
            const isDim = (activeStepId || activeArtId) && !isFocus;
            const card = document.createElement("div");
            card.className = "step-card" + (isFocus ? " focused" : "") + (isDim ? " dimmed" : "");
            card.onclick = () => { activeArtId = null; activeStepId = activeStepId === s.id ? null : s.id; render(); };
            const linkedNames = (s.linkedArtifactIDs || []).map(id => (bp.artifacts || []).find(a => a.id === id)?.label).filter(Boolean);
            card.innerHTML = `
              <div class="step-head">
                <span class="step-idx">${s.indexLabel}</span>
                ${s.badge ? `<span class="step-badge">${s.badge}</span>` : ""}
              </div>
              <div class="step-title">${s.title}</div>
              <div class="step-summary">${s.summary}</div>
              ${linkedNames.length ? `<div class="step-links">${linkedNames.map(n => `<span class="link-chip">${n}</span>`).join("")}</div>` : ""}
            `;
            stepsRow.appendChild(card);
          });
          renderArtifactsAndBranches(activeStep);
        }
        """
    }
    
    
    private static func jsEventsSection() -> String {
        """
        function renderArtifactsAndBranches(activeStep) {
          const artSec = document.getElementById("artifactsSection");
          const artGrid = document.getElementById("artifactsGrid");
          artSec.style.display = (bp.artifacts && bp.artifacts.length) ? "block" : "none";
          artGrid.innerHTML = "";
          (bp.artifacts || []).forEach(a => {
            const isFocus = activeArtId === a.id || (activeStep && (activeStep.linkedArtifactIDs || []).includes(a.id));
            const isDim = (activeStepId || activeArtId) && !isFocus;
            const card = document.createElement("div");
            card.className = "art-card" + (isFocus ? " focused" : "") + (isDim ? " dimmed" : "");
            card.onclick = () => { activeStepId = null; activeArtId = activeArtId === a.id ? null : a.id; render(); };
            card.innerHTML = `
              <div class="art-top">
                <span class="art-role">${a.role}</span>
                <button class="copy-btn" type="button">复制</button>
              </div>
              <div class="art-path">${a.path}</div>
            `;
            card.querySelector(".copy-btn").onclick = (e) => {
              e.stopPropagation();
              post({ action: "copyPath", path: a.path });
              e.target.textContent = "已复制";
              setTimeout(() => { e.target.textContent = "复制"; }, 1200);
            };
            artGrid.appendChild(card);
          });

          const brSec = document.getElementById("branchesSection");
          brSec.innerHTML = "";
          (bp.branches || []).forEach(br => {
            const div = document.createElement("div");
            div.className = "branch-card";
            div.innerHTML = `
              <div class="branch-meta">
                <div class="branch-head">
                  <span style="font-size:15px;font-weight:650;">${br.title}</span>
                  <span class="branch-tag">${br.relationLabel || br.tag}</span>
                </div>
                <div style="font-size:13.5px;color:var(--ink2);">${br.summary}</div>
              </div>
              <div class="art-path" style="max-width:460px;">${br.path}</div>
              <button class="copy-btn" type="button">复制</button>
            `;
            div.querySelector(".copy-btn").onclick = (e) => {
              post({ action: "copyPath", path: br.path });
              e.target.textContent = "已复制";
              setTimeout(() => { e.target.textContent = "复制"; }, 1200);
            };
            brSec.appendChild(div);
          });

          const tkSec = document.getElementById("takeawaySection");
          tkSec.innerHTML = bp.coreTakeaway ? `<div class="takeaway">${bp.coreTakeaway}</div>` : "";
        }

        window.setBlueprint = (next) => { bp = next; render(); };
        document.querySelectorAll("#themeSeg .btn").forEach(b => b.onclick = () => setTheme(b.dataset.theme));
        document.getElementById("btnFullscreen").onclick = () => post({ action: "toggleFullscreen" });
        document.getElementById("btnExportPNG").onclick = () => post({ action: "exportPNG" });
        document.getElementById("btnExportHTML").onclick = () => post({ action: "exportHTML", html: document.documentElement.outerHTML });

        window.addEventListener("keydown", (e) => {
          const steps = bp.steps || [];
          if (!steps.length) return;
          if (e.key === "ArrowRight" || e.key === " ") {
            e.preventDefault();
            const idx = steps.findIndex(s => s.id === activeStepId);
            activeArtId = null;
            activeStepId = idx < 0 ? steps[0].id : (idx + 1 < steps.length ? steps[idx + 1].id : null);
            render();
          } else if (e.key === "ArrowLeft") {
            e.preventDefault();
            const idx = steps.findIndex(s => s.id === activeStepId);
            activeArtId = null;
            activeStepId = idx <= 0 ? (idx === 0 ? null : steps[steps.length - 1].id) : steps[idx - 1].id;
            render();
          } else if (e.key === "Escape") {
            activeStepId = null; activeArtId = null; render();
          }
        });

        setTheme(document.documentElement.getAttribute("data-theme") || "keynoteLight");
        render();
        """
    }
}
