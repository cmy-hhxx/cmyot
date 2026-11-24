import { memo, type ReactNode } from "react";
import CodeBlock from "./CodeBlock";
import { postToNative } from "../bridge";

/* ─────────────────────────────────────────────────────────
 * Zero-dependency, streaming-safe GFM Markdown Renderer
 * Renders borderless editorial prose on --page using Beautiful UI CodeBlock.
 * ───────────────────────────────────────────────────────── */

type Block =
  | { type: "heading"; level: number; text: string }
  | { type: "paragraph"; text: string }
  | { type: "code"; lang: string; code: string }
  | { type: "quote"; text: string }
  | { type: "ul"; items: string[] }
  | { type: "ol"; items: string[] }
  | { type: "table"; headers: string[]; rows: string[][] }
  | { type: "hr" };

function isTableSep(line: string): boolean {
  const t = line.trim();
  return t.includes("|") && t.includes("-") && /^[\s|:\-]+$/.test(t);
}

function splitTableRow(line: string): string[] {
  let row = line.trim();
  if (row.startsWith("|")) row = row.slice(1);
  if (row.endsWith("|")) row = row.slice(0, -1);
  return row.split("|").map((c) => c.trim());
}

function parseBlocks(src: string): Block[] {
  const lines = src.replace(/\r\n/g, "\n").split("\n");
  const blocks: Block[] = [];
  let i = 0;

  while (i < lines.length) {
    const raw = lines[i];
    const trimmed = raw.trim();

    if (!trimmed) {
      i++;
      continue;
    }

    // Fenced code block (gracefully handles unclosed fence while streaming)
    if (trimmed.startsWith("```")) {
      const lang = trimmed.slice(3).trim();
      i++;
      const codeLines: string[] = [];
      while (i < lines.length) {
        if (lines[i].trim().startsWith("```")) {
          i++;
          break;
        }
        codeLines.push(lines[i]);
        i++;
      }
      blocks.push({ type: "code", lang, code: codeLines.join("\n") });
      continue;
    }

    // Horizontal rule
    if (/^(?:---|\*\*\*|___)$/.test(trimmed)) {
      blocks.push({ type: "hr" });
      i++;
      continue;
    }

    // Heading
    const headingMatch = /^(#{1,4})\s+(.+)$/.exec(trimmed);
    if (headingMatch) {
      blocks.push({ type: "heading", level: headingMatch[1].length, text: headingMatch[2].trim() });
      i++;
      continue;
    }

    // GFM Table
    if (trimmed.includes("|") && i + 1 < lines.length && isTableSep(lines[i + 1])) {
      const headers = splitTableRow(trimmed);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length) {
        const r = lines[i].trim();
        if (!r || !r.includes("|")) break;
        rows.push(splitTableRow(r));
        i++;
      }
      blocks.push({ type: "table", headers, rows });
      continue;
    }

    // Blockquote
    if (trimmed.startsWith(">")) {
      const qLines: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith(">")) {
        qLines.push(lines[i].trim().replace(/^>\s?/, ""));
        i++;
      }
      blocks.push({ type: "quote", text: qLines.join("\n") });
      continue;
    }

    // Unordered list
    if (/^(?:[-*•])\s+/.test(trimmed)) {
      const items: string[] = [];
      while (i < lines.length) {
        const m = /^(?:[-*•])\s+(.+)$/.exec(lines[i].trim());
        if (!m) break;
        items.push(m[1].trim());
        i++;
      }
      blocks.push({ type: "ul", items });
      continue;
    }

    // Ordered list
    if (/^\d+[.)]\s+/.test(trimmed)) {
      const items: string[] = [];
      while (i < lines.length) {
        const m = /^\d+[.)]\s+(.+)$/.exec(lines[i].trim());
        if (!m) break;
        items.push(m[1].trim());
        i++;
      }
      blocks.push({ type: "ol", items });
      continue;
    }

    // Paragraph
    const para: string[] = [trimmed];
    i++;
    while (i < lines.length) {
      const next = lines[i].trim();
      if (
        !next ||
        next.startsWith("```") ||
        /^(#{1,4})\s+/.test(next) ||
        /^(?:---|\*\*\*|___)$/.test(next) ||
        next.startsWith(">") ||
        /^(?:[-*•])\s+/.test(next) ||
        /^\d+[.)]\s+/.test(next) ||
        (next.includes("|") && i + 1 < lines.length && isTableSep(lines[i + 1]))
      ) {
        break;
      }
      para.push(next);
      i++;
    }
    blocks.push({ type: "paragraph", text: para.join("\n") });
  }

  return blocks;
}

const INLINE_RE =
  /(`[^`\n]+`|\*\*[^*\n]+?\*\*|__[^_\n]+?__|~~[^~\n]+?~~|\*[^*\n]+?\*|\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)|(https?:\/\/[^\s<>)\]]+))/g;

function renderInline(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let k = 0;

  for (const m of text.matchAll(INLINE_RE)) {
    const idx = m.index ?? 0;
    const tok = m[0];
    if (idx > last) {
      out.push(text.slice(last, idx));
    }

    if (tok.startsWith("`") && tok.endsWith("`")) {
      out.push(
        <code key={k++} className="inline-code">
          {tok.slice(1, -1)}
        </code>,
      );
    } else if ((tok.startsWith("**") && tok.endsWith("**")) || (tok.startsWith("__") && tok.endsWith("__"))) {
      out.push(<strong key={k++}>{renderInline(tok.slice(2, -2))}</strong>);
    } else if (tok.startsWith("~~") && tok.endsWith("~~")) {
      out.push(<del key={k++}>{renderInline(tok.slice(2, -2))}</del>);
    } else if (tok.startsWith("*") && tok.endsWith("*")) {
      out.push(<em key={k++}>{renderInline(tok.slice(1, -1))}</em>);
    } else if (m[2] && m[3]) {
      const url = m[3];
      out.push(
        <a
          key={k++}
          href={url}
          onClick={(e) => {
            e.preventDefault();
            postToNative("openURL", { url });
          }}
        >
          {m[2]}
        </a>,
      );
    } else if (m[4]) {
      const url = m[4];
      out.push(
        <a
          key={k++}
          href={url}
          onClick={(e) => {
            e.preventDefault();
            postToNative("openURL", { url });
          }}
        >
          {url}
        </a>,
      );
    } else {
      out.push(tok);
    }
    last = idx + tok.length;
  }

  if (last < text.length) out.push(text.slice(last));
  return out;
}

function renderMultilineInline(text: string): ReactNode {
  const parts = text.split("\n");
  if (parts.length === 1) return renderInline(text);
  return parts.map((line, i) => (
    <span key={i}>
      {renderInline(line)}
      {i < parts.length - 1 && <br />}
    </span>
  ));
}

const MarkdownProse = memo(function MarkdownProse({
  markdown,
  isStreaming = false,
  locale = "zh",
  onInsertCode,
}: {
  markdown: string;
  isStreaming?: boolean;
  locale?: "zh" | "en";
  onInsertCode?: (code: string) => void;
}) {
  const blocks = parseBlocks(markdown);

  return (
    <div className="bui-prose">
      {blocks.map((b, idx) => {
        const isLast = idx === blocks.length - 1;
        switch (b.type) {
          case "heading": {
            const Tag = (`h${Math.min(4, Math.max(1, b.level))}`) as "h1" | "h2" | "h3" | "h4";
            return (
              <Tag key={idx}>
                {renderInline(b.text)}
                {isStreaming && isLast && <span className="stream-caret is-streaming" />}
              </Tag>
            );
          }
          case "paragraph":
            return (
              <p key={idx}>
                {renderMultilineInline(b.text)}
                {isStreaming && isLast && <span className="stream-caret is-streaming" />}
              </p>
            );
          case "quote":
            return (
              <blockquote key={idx}>
                {renderMultilineInline(b.text)}
                {isStreaming && isLast && <span className="stream-caret is-streaming" />}
              </blockquote>
            );
          case "ul":
            return (
              <ul key={idx}>
                {b.items.map((it, j) => (
                  <li key={j}>
                    {renderInline(it)}
                    {isStreaming && isLast && j === b.items.length - 1 && <span className="stream-caret is-streaming" />}
                  </li>
                ))}
              </ul>
            );
          case "ol":
            return (
              <ol key={idx}>
                {b.items.map((it, j) => (
                  <li key={j}>
                    {renderInline(it)}
                    {isStreaming && isLast && j === b.items.length - 1 && <span className="stream-caret is-streaming" />}
                  </li>
                ))}
              </ol>
            );
          case "code":
            return <CodeBlock key={idx} code={b.code} language={b.lang} locale={locale} onInsert={onInsertCode} />;
          case "table":
            return (
              <div key={idx} className="bui-table-wrap">
                <table>
                  <thead>
                    <tr>
                      {b.headers.map((h, ci) => (
                        <th key={ci}>{renderInline(h)}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {b.rows.map((row, ri) => (
                      <tr key={ri}>
                        {b.headers.map((_, ci) => (
                          <td key={ci}>{renderInline(row[ci] ?? "")}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
          case "hr":
            return <hr key={idx} />;
        }
      })}
      {isStreaming && blocks.length === 0 && <span className="stream-caret is-streaming" />}
    </div>
  );
});

export default MarkdownProse;
