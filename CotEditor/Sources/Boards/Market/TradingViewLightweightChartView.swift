//
//  TradingViewLightweightChartView.swift
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

import AppKit
import SwiftUI
import WebKit

/// TradingView Lightweight Charts v5 interactive K-line / Intraday / MA / Volume surface
/// powered by the bundled offline `lightweight-charts.standalone.production.js` library.
struct TradingViewLightweightChartView: NSViewRepresentable {
    
    let instrument: MarketInstrument
    let period: MarketChartPeriod
    let bars: [MarketBar]
    let previousClose: Double
    let isDark: Bool
    let showMovingAverages: Bool
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let html = Self.chartHTMLDocument()
        context.coordinator.pendingPayloadJSON = self.buildPayloadJSON()
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        return webView
    }
    
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let json = self.buildPayloadJSON()
        guard context.coordinator.lastPushedJSON != json else { return }
        context.coordinator.pendingPayloadJSON = json
        if context.coordinator.isLoaded {
            context.coordinator.lastPushedJSON = json
            nsView.evaluateJavaScript("window.CotChartBridge && window.CotChartBridge.setData(\(json));", completionHandler: nil)
        }
    }
    
    
    private func buildPayloadJSON() -> String {
        let isIntraday = (self.period == .intraday)
        let usesTimeEpoch = (self.period == .intraday || self.period == .fiveMin)
        let tzOffset = self.instrument.market.timeZone.secondsFromGMT()
        let upHex = self.instrument.market.usesRedUpGreenDown ? "#EB4842" : "#23B873"
        let downHex = self.instrument.market.usesRedUpGreenDown ? "#23B873" : "#EB4842"
        
        var seenTimes = Set<String>()
        var candlePayloads: [[String: Any]] = []
        var linePayloads: [[String: Any]] = []
        var volPayloads: [[String: Any]] = []
        var ma5Payloads: [[String: Any]] = []
        var ma10Payloads: [[String: Any]] = []
        var ma20Payloads: [[String: Any]] = []
        
        var orderedBars: [(timeKey: String, timeValue: Any, bar: MarketBar)] = []
        for (idx, bar) in self.bars.enumerated() {
            if usesTimeEpoch {
                let rawSec = Int((bar.date?.timeIntervalSince1970 ?? (Date().timeIntervalSince1970 + Double(idx * 60)))) + tzOffset
                let key = "\(rawSec)"
                if seenTimes.insert(key).inserted {
                    orderedBars.append((key, rawSec, bar))
                }
            } else {
                let dayKey = String(bar.timeLabel.prefix(10))
                let validKey = dayKey.count == 10 ? dayKey : String(format: "2026-01-%02d", min(28, idx + 1))
                if seenTimes.insert(validKey).inserted {
                    orderedBars.append((validKey, validKey, bar))
                }
            }
        }
        
        if usesTimeEpoch {
            orderedBars.sort { (($0.timeValue as? Int) ?? 0) < (($1.timeValue as? Int) ?? 0) }
        } else {
            orderedBars.sort { $0.timeKey < $1.timeKey }
        }
        
        let closes = orderedBars.map(\.bar.close)
        let ma5 = Self.movingAverage(values: closes, period: 5)
        let ma10 = Self.movingAverage(values: closes, period: 10)
        let ma20 = Self.movingAverage(values: closes, period: 20)
        
        var runningPV = 0.0
        var runningV = 0.0
        
        for (idx, entry) in orderedBars.enumerated() {
            let b = entry.bar
            let isUp = isIntraday
                ? (self.previousClose > 0 ? b.close >= self.previousClose : true)
                : (b.close >= b.open)
            let barColor = isUp ? upHex : downHex
            let volColor = isUp ? "\(upHex)88" : "\(downHex)88"
            
            candlePayloads.append([
                "time": entry.timeValue,
                "open": b.open,
                "high": b.high,
                "low": b.low,
                "close": b.close,
            ])
            linePayloads.append([
                "time": entry.timeValue,
                "value": b.close,
            ])
            volPayloads.append([
                "time": entry.timeValue,
                "value": b.volume,
                "color": volColor,
            ])
            
            if isIntraday {
                runningPV += b.close * max(b.volume, 1)
                runningV += max(b.volume, 1)
                ma5Payloads.append([
                    "time": entry.timeValue,
                    "value": runningV > 0 ? runningPV / runningV : b.close,
                ])
            } else {
                if let v = ma5[idx] { ma5Payloads.append(["time": entry.timeValue, "value": v]) }
                if let v = ma10[idx] { ma10Payloads.append(["time": entry.timeValue, "value": v]) }
                if let v = ma20[idx] { ma20Payloads.append(["time": entry.timeValue, "value": v]) }
            }
            _ = barColor
        }
        
        let lastPrice = orderedBars.last?.bar.close ?? self.previousClose
        let lineTone = (self.previousClose > 0 && lastPrice >= self.previousClose) ? upHex : downHex
        let precision = lastPrice >= 10 ? 2 : 3
        let minMove = lastPrice >= 10 ? 0.01 : 0.001
        
        let payload: [String: Any] = [
            "symbol": self.instrument.symbol,
            "name": self.instrument.name,
            "mode": isIntraday ? "intraday" : "candles",
            "isDark": self.isDark,
            "showMA": self.showMovingAverages,
            "upColor": upHex,
            "downColor": downHex,
            "lineColor": lineTone,
            "prevClose": self.previousClose,
            "precision": precision,
            "minMove": minMove,
            "candles": candlePayloads,
            "line": linePayloads,
            "volume": volPayloads,
            "ma5": ma5Payloads,
            "ma10": ma10Payloads,
            "ma20": ma20Payloads,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
    
    
    private static func movingAverage(values: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return Array(repeating: nil, count: values.count) }
        var out: [Double?] = Array(repeating: nil, count: values.count)
        var sum = 0.0
        for idx in values.indices {
            sum += values[idx]
            if idx >= period {
                sum -= values[idx - period]
            }
            if idx >= period - 1 {
                out[idx] = sum / Double(period)
            }
        }
        return out
    }
    
    
    // MARK: - Bundled Library & HTML Shell
    
    static func bundledLibraryJS() -> String {
        if let url = Bundle.main.url(forResource: "lightweight-charts.standalone.production", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8)
        {
            return js
        }
        if let url = Bundle(for: BundleFinderToken.self).url(forResource: "lightweight-charts.standalone.production", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8)
        {
            return js
        }
        return ""
    }
    
    
    static func chartHTMLDocument(libraryJS: String? = nil) -> String {
        let js = libraryJS ?? Self.bundledLibraryJS()
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <style>
        \(Self.chartStylesCSS())
          </style>
        </head>
        <body>
          <div id="wrap">
            <div id="legend"></div>
            <div id="chart"></div>
          </div>
          <script>\(js)</script>
          <script>
            (function () {
        \(Self.chartInitScript())
        \(Self.chartBridgeScript())
            })();
          </script>
        </body>
        </html>
        """
    }
    
    
    private static func chartStylesCSS() -> String {
        """
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: transparent;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
              -webkit-font-smoothing: antialiased;
            }
            #wrap {
              position: relative;
              width: 100%;
              height: 100%;
            }
            #chart {
              width: 100%;
              height: 100%;
            }
            #legend {
              position: absolute;
              top: 6px;
              left: 10px;
              right: 72px;
              z-index: 10;
              pointer-events: none;
              display: flex;
              flex-wrap: wrap;
              align-items: center;
              gap: 10px;
              font-size: 11px;
              font-variant-numeric: tabular-nums;
              color: rgba(30, 35, 45, 0.78);
            }
            body.dark #legend {
              color: rgba(226, 232, 240, 0.80);
            }
            .tag { font-weight: 600; opacity: 0.65; margin-right: 2px; }
            .ma5 { color: #F5AD29; font-weight: 500; }
            .ma10 { color: #38B8F0; font-weight: 500; }
            .ma20 { color: #B873F0; font-weight: 500; }
        """
    }
    
    
    private static func chartInitScript() -> String {
        """
              const container = document.getElementById('chart');
              const legendEl = document.getElementById('legend');
              if (!window.LightweightCharts || !container) {
                legendEl.textContent = 'TradingView Lightweight Charts unavailable';
                return;
              }
              const LWC = window.LightweightCharts;
              const chart = LWC.createChart(container, {
                autoSize: false,
                width: Math.max(200, container.clientWidth || 600),
                height: Math.max(160, container.clientHeight || 360),
                layout: {
                  background: { type: LWC.ColorType.Solid, color: 'transparent' },
                  textColor: 'rgba(110, 118, 134, 0.9)',
                  fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                  fontSize: 11,
                },
                grid: {
                  vertLines: { color: 'rgba(128, 136, 152, 0.08)' },
                  horzLines: { color: 'rgba(128, 136, 152, 0.10)' },
                },
                crosshair: {
                  mode: LWC.CrosshairMode.Normal,
                },
                rightPriceScale: {
                  borderColor: 'rgba(128, 136, 152, 0.16)',
                  scaleMargins: { top: 0.10, bottom: 0.08 },
                },
                timeScale: {
                  borderColor: 'rgba(128, 136, 152, 0.16)',
                  timeVisible: true,
                  secondsVisible: false,
                },
                handleScroll: { mouseWheel: true, pressedMouseMove: true, horzTouchDrag: true, vertTouchDrag: false },
                handleScale: { axisPressedMouseMove: true, mouseWheel: true, pinch: true },
              });

              const candleSeries = chart.addSeries(LWC.CandlestickSeries, {
                upColor: '#EB4842',
                downColor: '#23B873',
                borderVisible: false,
                wickUpColor: '#EB4842',
                wickDownColor: '#23B873',
              });
              const ma5Series = chart.addSeries(LWC.LineSeries, {
                color: '#F5AD29', lineWidth: 1.3, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false
              });
              const ma10Series = chart.addSeries(LWC.LineSeries, {
                color: '#38B8F0', lineWidth: 1.3, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false
              });
              const ma20Series = chart.addSeries(LWC.LineSeries, {
                color: '#B873F0', lineWidth: 1.3, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false
              });
              const areaSeries = chart.addSeries(LWC.AreaSeries, {
                lineWidth: 1.8,
                topColor: 'rgba(235, 72, 66, 0.22)',
                bottomColor: 'rgba(235, 72, 66, 0.0)',
                lineColor: '#EB4842',
                priceLineVisible: false,
              });
              const vwapSeries = chart.addSeries(LWC.LineSeries, {
                color: '#F5AD29', lineWidth: 1.2, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false
              });
              const volumeSeries = chart.addSeries(LWC.HistogramSeries, {
                priceFormat: { type: 'volume' },
                priceLineVisible: false,
                lastValueVisible: false,
              }, 1);

              const panes = chart.panes ? chart.panes() : [];
              if (panes.length > 1 && panes[1].setHeight) {
                panes[1].setHeight(80);
              }
        """
    }
    
    
    private static func chartBridgeScript() -> String {
        """
              let prevCloseLine = null;
              let currentPayload = null;

              function fmtPrice(val, prec) {
                if (typeof val !== 'number' || !isFinite(val)) return '—';
                return val.toFixed(prec || 2);
              }

              function fmtVol(v) {
                if (typeof v !== 'number' || !isFinite(v)) return '0';
                if (v >= 1e8) return (v / 1e8).toFixed(2) + '亿';
                if (v >= 1e4) return (v / 1e4).toFixed(1) + '万';
                return Math.round(v).toString();
              }

              function fmtTime(t) {
                if (typeof t === 'string') return t;
                if (typeof t === 'number') {
                  const d = new Date(t * 1000);
                  const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
                  const dd = String(d.getUTCDate()).padStart(2, '0');
                  const hh = String(d.getUTCHours()).padStart(2, '0');
                  const mi = String(d.getUTCMinutes()).padStart(2, '0');
                  return `${mm}-${dd} ${hh}:${mi}`;
                }
                return '';
              }

              function renderLegend(pointTime, candleDatum, areaDatum, volDatum, ma5D, ma10D, ma20D) {
                if (!currentPayload) return;
                const prec = currentPayload.precision || 2;
                const isIntraday = currentPayload.mode === 'intraday';
                const parts = [];
                if (pointTime) {
                  parts.push(`<span><span class="tag">${fmtTime(pointTime)}</span></span>`);
                }
                if (isIntraday && areaDatum) {
                  parts.push(`<span><span class="tag">现价</span>${fmtPrice(areaDatum.value, prec)}</span>`);
                  if (ma5D && typeof ma5D.value === 'number') {
                    parts.push(`<span class="ma5">均价 ${fmtPrice(ma5D.value, prec)}</span>`);
                  }
                } else if (candleDatum) {
                  parts.push(`<span><span class="tag">O</span>${fmtPrice(candleDatum.open, prec)}</span>`);
                  parts.push(`<span><span class="tag">H</span>${fmtPrice(candleDatum.high, prec)}</span>`);
                  parts.push(`<span><span class="tag">L</span>${fmtPrice(candleDatum.low, prec)}</span>`);
                  parts.push(`<span><span class="tag">C</span>${fmtPrice(candleDatum.close, prec)}</span>`);
                  if (currentPayload.showMA) {
                    if (ma5D && typeof ma5D.value === 'number') parts.push(`<span class="ma5">MA5 ${fmtPrice(ma5D.value, prec)}</span>`);
                    if (ma10D && typeof ma10D.value === 'number') parts.push(`<span class="ma10">MA10 ${fmtPrice(ma10D.value, prec)}</span>`);
                    if (ma20D && typeof ma20D.value === 'number') parts.push(`<span class="ma20">MA20 ${fmtPrice(ma20D.value, prec)}</span>`);
                  }
                }
                if (volDatum && typeof volDatum.value === 'number') {
                  parts.push(`<span><span class="tag">Vol</span>${fmtVol(volDatum.value)}</span>`);
                }
                legendEl.innerHTML = parts.join('');
              }

              function showLatestLegend() {
                if (!currentPayload) return;
                const candles = currentPayload.candles || [];
                const line = currentPayload.line || [];
                const vols = currentPayload.volume || [];
                const ma5 = currentPayload.ma5 || [];
                const ma10 = currentPayload.ma10 || [];
                const ma20 = currentPayload.ma20 || [];
                const lastC = candles[candles.length - 1];
                const lastL = line[line.length - 1];
                const lastV = vols[vols.length - 1];
                const last5 = ma5[ma5.length - 1];
                const last10 = ma10[ma10.length - 1];
                const last20 = ma20[ma20.length - 1];
                const t = (currentPayload.mode === 'intraday' ? lastL : lastC)?.time;
                renderLegend(t, lastC, lastL, lastV, last5, last10, last20);
              }

              chart.subscribeCrosshairMove((param) => {
                if (!param || !param.time) {
                  showLatestLegend();
                  return;
                }
                renderLegend(
                  param.time,
                  param.seriesData.get(candleSeries),
                  param.seriesData.get(areaSeries),
                  param.seriesData.get(volumeSeries),
                  param.seriesData.get(ma5Series),
                  param.seriesData.get(ma10Series),
                  param.seriesData.get(ma20Series)
                );
              });

              const ro = new ResizeObserver((entries) => {
                for (const e of entries) {
                  const w = Math.max(180, Math.floor(e.contentRect.width));
                  const h = Math.max(150, Math.floor(e.contentRect.height));
                  chart.resize(w, h);
                }
              });
              ro.observe(container);

              window.CotChartBridge = {
                setData: function (payload) {
                  currentPayload = payload;
                  document.body.classList.toggle('dark', !!payload.isDark);
                  chart.applyOptions({
                    layout: {
                      textColor: payload.isDark ? 'rgba(182, 192, 208, 0.86)' : 'rgba(90, 98, 114, 0.88)',
                    },
                    grid: {
                      vertLines: { color: payload.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' },
                      horzLines: { color: payload.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)' },
                    },
                    rightPriceScale: {
                      borderColor: payload.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.10)',
                    },
                    timeScale: {
                      borderColor: payload.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.10)',
                      timeVisible: payload.mode === 'intraday' || (payload.candles && payload.candles[0] && typeof payload.candles[0].time === 'number'),
                    },
                  });

                  const isIntraday = payload.mode === 'intraday';
                  const priceFormat = { type: 'price', precision: payload.precision || 2, minMove: payload.minMove || 0.01 };

                  candleSeries.applyOptions({
                    visible: !isIntraday,
                    upColor: payload.upColor,
                    downColor: payload.downColor,
                    wickUpColor: payload.upColor,
                    wickDownColor: payload.downColor,
                    priceFormat,
                  });
                  ma5Series.applyOptions({ visible: !isIntraday && !!payload.showMA, priceFormat });
                  ma10Series.applyOptions({ visible: !isIntraday && !!payload.showMA, priceFormat });
                  ma20Series.applyOptions({ visible: !isIntraday && !!payload.showMA, priceFormat });

                  const lc = payload.lineColor || '#EB4842';
                  areaSeries.applyOptions({
                    visible: isIntraday,
                    lineColor: lc,
                    topColor: lc + '38',
                    bottomColor: lc + '00',
                    priceFormat,
                  });
                  vwapSeries.applyOptions({ visible: isIntraday, priceFormat });

                  if (prevCloseLine) {
                    try { areaSeries.removePriceLine(prevCloseLine); } catch (_) {}
                    prevCloseLine = null;
                  }
                  if (isIntraday && payload.prevClose > 0) {
                    prevCloseLine = areaSeries.createPriceLine({
                      price: payload.prevClose,
                      color: payload.isDark ? 'rgba(200,210,224,0.45)' : 'rgba(90,98,114,0.45)',
                      lineWidth: 1,
                      lineStyle: LWC.LineStyle.Dashed,
                      axisLabelVisible: true,
                      title: '昨收',
                    });
                  }

                  candleSeries.setData(isIntraday ? [] : (payload.candles || []));
                  ma5Series.setData(!isIntraday ? (payload.ma5 || []) : []);
                  ma10Series.setData(!isIntraday ? (payload.ma10 || []) : []);
                  ma20Series.setData(!isIntraday ? (payload.ma20 || []) : []);
                  areaSeries.setData(isIntraday ? (payload.line || []) : []);
                  vwapSeries.setData(isIntraday ? (payload.ma5 || []) : []);
                  volumeSeries.setData(payload.volume || []);

                  chart.timeScale().fitContent();
                  showLatestLegend();
                }
              };
        """
    }
    
    
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        
        var isLoaded = false
        var pendingPayloadJSON: String?
        var lastPushedJSON: String?
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.isLoaded = true
            if let json = self.pendingPayloadJSON {
                self.lastPushedJSON = json
                webView.evaluateJavaScript("window.CotChartBridge && window.CotChartBridge.setData(\(json));", completionHandler: nil)
            }
        }
    }
}

private final class BundleFinderToken {}
