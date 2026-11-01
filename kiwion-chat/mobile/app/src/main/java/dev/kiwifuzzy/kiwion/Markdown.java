package dev.kiwifuzzy.kiwion;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Typeface;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.method.LinkMovementMethod;
import android.text.style.BackgroundColorSpan;
import android.text.style.BulletSpan;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.StyleSpan;
import android.text.style.TypefaceSpan;
import android.text.style.URLSpan;
import android.view.Gravity;
import android.view.View;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Minimal, safe Markdown renderer (headings, lists, bold/italic, inline code, links, fenced code with highlighting). */
public final class Markdown {
    private Markdown() {}

    private static final Pattern INLINE = Pattern.compile(
            "(`[^`\\n]+`)|(\\*\\*[^*\\n]+\\*\\*)|(__[^_\\n]+__)|(\\*[^*\\n]+\\*)|(\\[[^\\]\\n]+\\]\\((https?://[^)\\s]+)\\))");
    private static final Pattern KEYWORDS = Pattern.compile("\\b(def|class|return|if|elif|else|for|while|in|import|from|as|with|try|except|"
            + "finally|raise|lambda|yield|async|await|function|const|let|var|new|this|public|private|static|void|int|float|double|"
            + "boolean|String|true|false|True|False|None|null|undefined|fun|val|package|interface|extends|implements|struct|fn|match|"
            + "switch|case|break|continue|echo|print|func|go|type|select|where|SELECT|FROM|WHERE|INSERT|UPDATE|DELETE)\\b");
    private static final Pattern STRINGS = Pattern.compile("(\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*')");
    private static final Pattern COMMENTS = Pattern.compile("(#[^\\n]*|//[^\\n]*|/\\*[\\s\\S]*?\\*/)");
    private static final Pattern NUMBERS = Pattern.compile("\\b\\d+(\\.\\d+)?\\b");

    public static View render(Context c, Palette p, String md) {
        LinearLayout box = Ui.vbox(c);
        String[] lines = (md == null ? "" : md).split("\n", -1);
        SpannableStringBuilder para = new SpannableStringBuilder();
        StringBuilder code = null;
        String lang = "";
        for (String line : lines) {
            if (line.trim().startsWith("```")) {
                if (code == null) {
                    flush(c, p, box, para);
                    para = new SpannableStringBuilder();
                    code = new StringBuilder();
                    lang = line.trim().substring(3).trim();
                } else {
                    box.addView(codeBlock(c, p, code.toString(), lang), Ui.matchWrap(c, 6));
                    code = null;
                }
                continue;
            }
            if (code != null) {
                if (code.length() > 0) code.append('\n');
                code.append(line);
                continue;
            }
            appendLine(p, para, line);
        }
        if (code != null) box.addView(codeBlock(c, p, code.toString(), lang), Ui.matchWrap(c, 6)); // still streaming
        flush(c, p, box, para);
        return box;
    }

    private static void appendLine(Palette p, SpannableStringBuilder sb, String line) {
        if (sb.length() > 0) sb.append('\n');
        int start = sb.length();
        String t = line;
        if (t.startsWith("### ") || t.startsWith("## ") || t.startsWith("# ")) {
            int level = t.indexOf(' ');
            inline(p, sb, t.substring(level + 1));
            sb.setSpan(new StyleSpan(Typeface.BOLD), start, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            sb.setSpan(new RelativeSizeSpan(level == 1 ? 1.3f : level == 2 ? 1.18f : 1.08f), start, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        } else if (t.matches("^\\s*[-*+] .*")) {
            inline(p, sb, t.replaceFirst("^\\s*[-*+] ", ""));
            sb.setSpan(new BulletSpan(24, p.green), start, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        } else if (t.startsWith("> ")) {
            inline(p, sb, t.substring(2));
            sb.setSpan(new ForegroundColorSpan(p.muted), start, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        } else {
            inline(p, sb, t);
        }
    }

    private static void inline(Palette p, SpannableStringBuilder sb, String s) {
        Matcher m = INLINE.matcher(s);
        int last = 0;
        while (m.find()) {
            sb.append(s, last, m.start());
            int st = sb.length();
            if (m.group(1) != null) {
                sb.append(m.group(1), 1, m.group(1).length() - 1);
                sb.setSpan(new TypefaceSpan("monospace"), st, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                sb.setSpan(new BackgroundColorSpan(p.surface2), st, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            } else if (m.group(2) != null || m.group(3) != null) {
                String g = m.group(2) != null ? m.group(2) : m.group(3);
                sb.append(g, 2, g.length() - 2);
                sb.setSpan(new StyleSpan(Typeface.BOLD), st, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            } else if (m.group(4) != null) {
                sb.append(m.group(4), 1, m.group(4).length() - 1);
                sb.setSpan(new StyleSpan(Typeface.ITALIC), st, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            } else if (m.group(5) != null) {
                String label = m.group(5).substring(1, m.group(5).indexOf(']'));
                sb.append(label);
                sb.setSpan(new URLSpan(m.group(6)), st, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            last = m.end();
        }
        sb.append(s, last, s.length());
    }

    private static void flush(Context c, Palette p, LinearLayout box, SpannableStringBuilder sb) {
        String s = sb.toString();
        if (s.trim().isEmpty()) return;
        TextView t = Ui.text(c, trimEnd(sb), 16, p.text, false);
        t.setLineSpacing(0, 1.15f);
        t.setTextIsSelectable(true);
        t.setMovementMethod(LinkMovementMethod.getInstance());
        t.setLinkTextColor(p.greenStrong);
        box.addView(t, Ui.matchWrap(c, box.getChildCount() == 0 ? 0 : 6));
    }

    private static CharSequence trimEnd(SpannableStringBuilder sb) {
        int end = sb.length();
        while (end > 0 && Character.isWhitespace(sb.charAt(end - 1))) end--;
        int start = 0;
        while (start < end && sb.charAt(start) == '\n') start++;
        return sb.subSequence(start, end);
    }

    public static CharSequence highlight(Palette p, String code) {
        SpannableStringBuilder sb = new SpannableStringBuilder(code);
        int kw = p.dark ? 0xFFFF7B72 : 0xFFCF222E, str = p.dark ? 0xFFA5D6FF : 0xFF0A3069,
                com = p.muted, num = p.dark ? 0xFF79C0FF : 0xFF0550AE;
        color(sb, NUMBERS.matcher(code), num);
        color(sb, KEYWORDS.matcher(code), kw);
        color(sb, STRINGS.matcher(code), str);
        color(sb, COMMENTS.matcher(code), com);
        return sb;
    }

    private static void color(SpannableStringBuilder sb, Matcher m, int color) {
        while (m.find()) sb.setSpan(new ForegroundColorSpan(color), m.start(), m.end(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
    }

    private static View codeBlock(final Context c, Palette p, final String code, String lang) {
        LinearLayout box = Ui.vbox(c);
        box.setBackground(Ui.roundStroke(p.surface2, p.border, Ui.dp(c, 1), Ui.dp(c, 12)));
        LinearLayout head = Ui.hbox(c);
        head.setPadding(Ui.dp(c, 12), Ui.dp(c, 6), Ui.dp(c, 6), 0);
        TextView l = Ui.text(c, lang.isEmpty() ? "код" : lang, 12, p.muted, false);
        head.addView(l, new LinearLayout.LayoutParams(0, -2, 1));
        TextView copy = Ui.text(c, "Копировать", 12, p.greenStrong, true);
        copy.setPadding(Ui.dp(c, 8), Ui.dp(c, 4), Ui.dp(c, 8), Ui.dp(c, 4));
        copy.setGravity(Gravity.CENTER);
        copy.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                ClipboardManager cm = (ClipboardManager) c.getSystemService(Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("code", code));
                Toast.makeText(c, "Код скопирован", Toast.LENGTH_SHORT).show();
            }
        });
        head.addView(copy);
        box.addView(head);
        HorizontalScrollView hs = new HorizontalScrollView(c);
        hs.setHorizontalScrollBarEnabled(false);
        TextView t = Ui.text(c, highlight(p, code), 13, p.text, false);
        t.setTypeface(Typeface.MONOSPACE);
        t.setTextIsSelectable(true);
        t.setPadding(Ui.dp(c, 12), Ui.dp(c, 4), Ui.dp(c, 12), Ui.dp(c, 12));
        hs.addView(t);
        box.addView(hs);
        return box;
    }
}
