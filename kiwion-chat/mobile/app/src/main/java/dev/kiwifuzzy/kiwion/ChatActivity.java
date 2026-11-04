package dev.kiwifuzzy.kiwion;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.os.Bundle;
import android.os.SystemClock;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/** A single conversation with streaming answers, stop, regenerate, edit and copy. */
public class ChatActivity extends BaseActivity {
    static final String AI_NOTE = "Kiwion — это ИИ, и он может ошибаться";
    private String chatId;
    private final List<JSONObject> messages = new ArrayList<>();
    private LinearLayout list;
    private ScrollView scroll;
    private EditText input;
    private Button send;
    private TextView titleView, hint;
    private Api.Stream streaming;
    private boolean stopRequested;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        chatId = getIntent().getStringExtra("chat_id");
        app.prefs.lastChat(chatId);
        LinearLayout root = Ui.vbox(this);
        LinearLayout bar = topBar("Чат", true);
        titleView = (TextView) bar.getChildAt(1);
        root.addView(bar);

        scroll = new ScrollView(this);
        list = Ui.vbox(this);
        int p = Ui.dp(this, 12);
        list.setPadding(p, p, p, p);
        scroll.addView(list);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        hint = Ui.text(this, "", 12, pal.muted, false);
        hint.setPadding(Ui.dp(this, 16), 0, Ui.dp(this, 16), 0);
        root.addView(hint);
        LinearLayout composer = Ui.hbox(this);
        composer.setPadding(Ui.dp(this, 10), Ui.dp(this, 6), Ui.dp(this, 10), Ui.dp(this, 10));
        input = Ui.input(this, pal, "Напишите сообщение…", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        input.setMaxLines(6);
        input.setBackground(Ui.roundStroke(pal.surface, pal.border, Ui.dp(this, 1), Ui.dp(this, 20)));
        input.setText(app.prefs.draft(chatId));
        input.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int a, int b, int c) { }
            public void onTextChanged(CharSequence s, int a, int b, int c) { }
            public void afterTextChanged(Editable s) { app.prefs.draft(chatId, s.toString()); }
        });
        composer.addView(input, new LinearLayout.LayoutParams(0, -2, 1));
        send = Ui.button(this, pal, "➤", true);
        send.setContentDescription("Отправить");
        send.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { if (streaming != null) stop(); else sendMessage(); }
        });
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(Ui.dp(this, 52), Ui.dp(this, 52));
        slp.leftMargin = Ui.dp(this, 8);
        composer.addView(send, slp);
        root.addView(composer);
        setScreen(root);
        load();
    }

    private void load() {
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.get("/api/chats/" + chatId); } },
                new Done<JSONObject>() {
                    public void done(JSONObject c) {
                        titleView.setText(c.optString("title"));
                        JSONArray a = c.optJSONArray("messages");
                        messages.clear();
                        boolean stillStreaming = false;
                        for (int i = 0; a != null && i < a.length(); i++) {
                            messages.add(a.optJSONObject(i));
                            if ("streaming".equals(a.optJSONObject(i).optString("status"))) stillStreaming = true;
                        }
                        renderAll();
                        if (stillStreaming && streaming == null) app.main.postDelayed(new Runnable() { public void run() { load(); } }, 1000);
                    }
                }, new Fail() {
                    public void fail(ApiException e) { toast(e.getMessage()); if (e.status == 404) finish(); }
                });
    }

    @Override
    protected void onBackOnline() { if (streaming == null) load(); }

    @Override
    protected void onDestroy() {
        if (streaming != null) streaming.cancel();
        super.onDestroy();
    }

    // ------------------------------------------------------------- rendering
    private void renderAll() {
        list.removeAllViews();
        if (messages.isEmpty()) {
            LinearLayout e = Ui.vbox(this);
            e.setGravity(Gravity.CENTER_HORIZONTAL);
            e.addView(new KiwiView(this), new LinearLayout.LayoutParams(Ui.dp(this, 140), Ui.dp(this, 128)));
            TextView t = Ui.text(this, "Привет! Я киви 🥝\nСпросите что-нибудь.", 17, pal.text, true);
            t.setGravity(Gravity.CENTER);
            e.addView(t);
            list.addView(e, Ui.matchWrap(this, 40));
            return;
        }
        int lastAssistant = -1;
        for (int i = 0; i < messages.size(); i++) if ("assistant".equals(messages.get(i).optString("role"))) lastAssistant = i;
        for (int i = 0; i < messages.size(); i++) list.addView(bubble(messages.get(i), i == lastAssistant));
        scrollDown();
    }

    private void scrollDown() {
        scroll.post(new Runnable() { public void run() { scroll.fullScroll(View.FOCUS_DOWN); } });
    }

    private View bubble(final JSONObject m, boolean last) {
        boolean user = "user".equals(m.optString("role"));
        LinearLayout wrap = Ui.vbox(this);
        wrap.setGravity(user ? Gravity.END : Gravity.START);
        LinearLayout.LayoutParams wlp = Ui.matchWrap(this, 10);
        wrap.setLayoutParams(wlp);
        if (user) {
            TextView t = Ui.text(this, m.optString("content"), 16, pal.onGreen, false);
            t.setBackground(Ui.round(pal.green, Ui.dp(this, 18)));
            t.setPadding(Ui.dp(this, 14), Ui.dp(this, 10), Ui.dp(this, 14), Ui.dp(this, 10));
            t.setMaxWidth((int) (getResources().getDisplayMetrics().widthPixels * 0.82f));
            wrap.addView(t);
            t.setOnLongClickListener(new View.OnLongClickListener() { public boolean onLongClick(View v) { userMenu(m); return true; } });
        } else {
            LinearLayout content = Ui.vbox(this);
            content.addView(Markdown.render(this, pal, m.optString("content")));
            String st = m.optString("status");
            if ("stopped".equals(st)) content.addView(Ui.text(this, "⏹ Генерация остановлена", 12, pal.muted, false));
            if ("error".equals(st)) content.addView(Ui.text(this, "⚠ Ответ не получен", 12, pal.danger, false));
            TextView aiNote = Ui.text(this, AI_NOTE, 12, pal.muted, false);
            aiNote.setPadding(0, Ui.dp(this, 6), 0, 0);
            content.addView(aiNote);
            wrap.addView(content, new LinearLayout.LayoutParams(-1, -2));
            content.setOnLongClickListener(new View.OnLongClickListener() { public boolean onLongClick(View v) { copy(m.optString("content")); return true; } });
            LinearLayout actions = Ui.hbox(this);
            actions.addView(action("Копировать", new View.OnClickListener() { public void onClick(View v) { copy(m.optString("content")); } }));
            if (last) actions.addView(action("Повторить", new View.OnClickListener() { public void onClick(View v) { regenerate(); } }));
            int tokens = m.optInt("completion_tokens");
            if (tokens > 0) actions.addView(Ui.text(this, "  " + tokens + " ток.", 12, pal.muted, false));
            wrap.addView(actions);
        }
        return wrap;
    }

    private TextView action(String label, View.OnClickListener l) {
        TextView t = Ui.text(this, label, 13, pal.greenStrong, true);
        t.setPadding(0, Ui.dp(this, 6), Ui.dp(this, 16), Ui.dp(this, 6));
        t.setOnClickListener(l);
        return t;
    }

    private void copy(String text) {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("Kiwion", text));
        toast("Скопировано");
    }

    private void userMenu(final JSONObject m) {
        new AlertDialog.Builder(this).setItems(new String[]{"Копировать", "Редактировать"}, new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface d, int w) { if (w == 0) copy(m.optString("content")); else edit(m); }
        }).show();
    }

    private void edit(final JSONObject m) {
        if (streaming != null) { toast("Дождитесь окончания ответа"); return; }
        final EditText e = Ui.input(this, pal, "Сообщение", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        e.setText(m.optString("content"));
        new AlertDialog.Builder(this).setTitle("Редактировать сообщение").setView(padded(e))
                .setPositiveButton("Отправить", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        String t = e.getText().toString().trim();
                        if (!t.isEmpty()) generate("PUT", "/api/chats/" + chatId + "/messages/" + m.optString("id"),
                                AuthActivity.json("content", t), null);
                    }
                }).setNegativeButton("Отмена", null).show();
    }

    private View padded(View v) {
        LinearLayout f = Ui.vbox(this);
        int p = Ui.dp(this, 20);
        f.setPadding(p, Ui.dp(this, 8), p, 0);
        f.addView(v);
        return f;
    }

    // ------------------------------------------------------------- generation
    private void sendMessage() {
        String text = input.getText().toString().trim();
        if (text.isEmpty()) return;
        if (!isOnline()) { toast("Нет подключения к интернету. Сообщение сохранено в поле ввода."); return; }
        generate("POST", "/api/chats/" + chatId + "/messages", AuthActivity.json("content", text), text);
    }

    private void regenerate() {
        if (streaming != null) return;
        generate("POST", "/api/chats/" + chatId + "/regenerate", new JSONObject(), null);
    }

    private void stop() {
        if (streaming == null) return;
        stopRequested = true;
        hint.setText("Останавливаем…");
        final Api.Stream s = streaming;
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/chats/" + chatId + "/stop", null); } },
                null, new Fail() { public void fail(ApiException e) { s.cancel(); } });
        app.main.postDelayed(new Runnable() { public void run() { if (streaming == s) s.cancel(); } }, 4000);
    }

    private void setBusy(boolean busy) {
        send.setText(busy ? "■" : "➤");
        send.setContentDescription(busy ? "Остановить" : "Отправить");
    }

    private void generate(final String method, final String path, final JSONObject body, final String optimisticText) {
        if (streaming != null) return;
        final Api.Stream handle = new Api.Stream();
        streaming = handle;
        stopRequested = false;
        setBusy(true);
        if (messages.isEmpty()) list.removeAllViews();
        final View pendingUser;
        if (optimisticText != null) {
            pendingUser = bubble(AuthActivity.json("role", "user", "content", optimisticText), false);
            list.addView(pendingUser);
        } else pendingUser = null;
        final LinearLayout answer = Ui.vbox(this);
        final TextView label = Ui.text(this, "🥝 Киви думает…", 14, pal.muted, false);
        answer.addView(label);
        list.addView(answer, Ui.matchWrap(this, 10));
        scrollDown();
        final StringBuilder text = new StringBuilder();
        final boolean[] gotToken = {false};
        final long started = SystemClock.uptimeMillis();
        final Runnable slowHint = new Runnable() {
            public void run() {
                if (streaming == handle && !gotToken[0])
                    label.setText("🥝 Модель думает дольше обычного — на слабом сервере ответ может занять до минуты…");
            }
        };
        app.main.postDelayed(slowHint, 15000);
        final long[] lastPaint = {0};
        final Runnable paint = new Runnable() {
            public void run() {
                lastPaint[0] = SystemClock.uptimeMillis();
                answer.removeAllViews();
                answer.addView(Markdown.render(ChatActivity.this, pal, text.toString() + " ▍"));
                scrollDown();
            }
        };
        app.io.execute(new Runnable() {
            public void run() {
                ApiException error = null;
                try {
                    app.api.stream(method, path, body, handle, new Api.EventHandler() {
                        public void onEvent(final JSONObject ev) {
                            final String type = ev.optString("type");
                            if ("token".equals(type)) {
                                synchronized (text) { text.append(ev.optString("text")); }
                                gotToken[0] = true;
                                long since = SystemClock.uptimeMillis() - lastPaint[0];
                                app.main.removeCallbacks(paint);
                                app.main.postDelayed(paint, since > 120 ? 0 : 120 - since);
                                return;
                            }
                            app.main.post(new Runnable() {
                                public void run() {
                                    if ("meta".equals(type)) {
                                        if (optimisticText != null && input.getText().toString().trim().equals(optimisticText)) {
                                            input.setText("");
                                            app.prefs.draft(chatId, null);
                                        }
                                        JSONObject chat = ev.optJSONObject("chat");
                                        if (chat != null) titleView.setText(chat.optString("title"));
                                    } else if ("queued".equals(type)) {
                                        label.setText("🥝 Вы в очереди: " + ev.optInt("position") + ". Киви скоро ответит…");
                                    } else if ("start".equals(type)) {
                                        label.setText("🥝 Киви печатает…");
                                    } else if ("error".equals(type)) {
                                        toast(ev.optString("message"));
                                    }
                                }
                            });
                        }
                    });
                } catch (ApiException e) {
                    error = e;
                }
                final ApiException err = error;
                app.main.post(new Runnable() {
                    public void run() {
                        app.main.removeCallbacks(slowHint);
                        app.main.removeCallbacks(paint);
                        if (destroyed) return;
                        streaming = null;
                        setBusy(false);
                        hint.setText("");
                        if (err != null && !gotToken[0]) {
                            // nothing was saved on the server: keep the user's text so it can be resent
                            list.removeView(answer);
                            if (pendingUser != null) list.removeView(pendingUser);
                            if (optimisticText != null && input.getText().toString().trim().isEmpty()) input.setText(optimisticText);
                            if (err.status == 401) { toLogin(); return; }
                            if ("overloaded".equals(err.code)) {
                                new AlertDialog.Builder(ChatActivity.this).setTitle("🥝").setMessage(Api.OVERLOADED)
                                        .setPositiveButton("Понятно", null).show();
                            } else toast(err.getMessage());
                            if (messages.isEmpty()) renderAll();
                            return;
                        }
                        if (err != null) toast(err.getMessage());
                        load();   // re-sync with the server (exact stored state)
                    }
                });
            }
        });
    }
}
