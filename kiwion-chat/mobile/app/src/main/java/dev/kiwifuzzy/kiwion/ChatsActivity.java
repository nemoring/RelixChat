package dev.kiwifuzzy.kiwion;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/** Dialog list: create, open, rename, delete; shows the model status. History is synced from the server. */
public class ChatsActivity extends BaseActivity {
    private final List<JSONObject> chats = new ArrayList<>();
    private BaseAdapter adapter;
    private TextView statusPill, empty;
    private final Runnable poll = new Runnable() {
        public void run() { loadStatus(); app.main.postDelayed(this, 15000); }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout root = Ui.vbox(this);
        LinearLayout bar = topBar("Kiwion Chat", false);
        statusPill = Ui.text(this, "…", 12, pal.muted, false);
        statusPill.setBackground(Ui.round(pal.surface2, Ui.dp(this, 99)));
        statusPill.setPadding(Ui.dp(this, 10), Ui.dp(this, 4), Ui.dp(this, 10), Ui.dp(this, 4));
        bar.addView(statusPill);
        TextView gear = Ui.text(this, "⚙", 22, pal.muted, false);
        gear.setPadding(Ui.dp(this, 14), 0, Ui.dp(this, 6), 0);
        gear.setContentDescription("Настройки");
        gear.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { startActivity(new Intent(ChatsActivity.this, SettingsActivity.class)); }
        });
        bar.addView(gear);
        root.addView(bar);

        FrameLayout body = new FrameLayout(this);
        ListView list = new ListView(this);
        list.setDivider(null);
        list.setPadding(Ui.dp(this, 8), 0, Ui.dp(this, 8), Ui.dp(this, 90));
        list.setClipToPadding(false);
        adapter = new BaseAdapter() {
            public int getCount() { return chats.size(); }
            public Object getItem(int i) { return chats.get(i); }
            public long getItemId(int i) { return i; }
            public View getView(int i, View cv, ViewGroup parent) {
                LinearLayout row = cv instanceof LinearLayout ? (LinearLayout) cv : makeRow();
                JSONObject c = chats.get(i);
                ((TextView) row.getChildAt(0)).setText(c.optString("title"));
                String upd = c.optString("updated_at", "");
                ((TextView) row.getChildAt(1)).setText(upd.length() >= 16 ? upd.substring(0, 10) + " " + upd.substring(11, 16) : upd);
                return row;
            }
        };
        list.setAdapter(adapter);
        list.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            public void onItemClick(AdapterView<?> a, View v, int i, long id) { open(chats.get(i).optString("id")); }
        });
        list.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            public boolean onItemLongClick(AdapterView<?> a, View v, int i, long id) { chatMenu(chats.get(i)); return true; }
        });
        body.addView(list);
        empty = Ui.text(this, "Пока нет диалогов.\nНажмите «Новый чат», чтобы поговорить с киви 🥝", 15, pal.muted, false);
        empty.setGravity(Gravity.CENTER);
        empty.setVisibility(View.GONE);
        body.addView(empty, new FrameLayout.LayoutParams(-1, -1));
        Button add = Ui.button(this, pal, "+  Новый чат", true);
        add.setElevation(Ui.dp(this, 6));
        FrameLayout.LayoutParams alp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.END);
        alp.setMargins(0, 0, Ui.dp(this, 18), Ui.dp(this, 22));
        add.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { newChat(); } });
        body.addView(add, alp);
        root.addView(body, new LinearLayout.LayoutParams(-1, 0, 1));
        setScreen(root);
    }

    private LinearLayout makeRow() {
        LinearLayout row = Ui.vbox(this);
        row.setPadding(Ui.dp(this, 14), Ui.dp(this, 12), Ui.dp(this, 14), Ui.dp(this, 12));
        row.setBackground(Ui.round(pal.surface, Ui.dp(this, 14)));
        TextView t = Ui.text(this, "", 16, pal.text, true);
        t.setSingleLine(true);
        row.addView(t);
        row.addView(Ui.text(this, "", 12, pal.muted, false));
        ListView.LayoutParams lp = new ListView.LayoutParams(-1, -2);
        row.setLayoutParams(lp);
        return row;
    }

    @Override
    protected void onResume() {
        super.onResume();
        load();
        app.main.post(poll);
    }

    @Override
    protected void onPause() {
        super.onPause();
        app.main.removeCallbacks(poll);
    }

    @Override
    protected void onBackOnline() { load(); loadStatus(); }

    private void load() {
        bg(new Task<JSONArray>() { public JSONArray run() throws ApiException { return app.api.getArray("/api/chats"); } },
                new Done<JSONArray>() {
                    public void done(JSONArray a) {
                        chats.clear();
                        for (int i = 0; i < a.length(); i++) chats.add(a.optJSONObject(i));
                        adapter.notifyDataSetChanged();
                        empty.setVisibility(chats.isEmpty() ? View.VISIBLE : View.GONE);
                    }
                }, new Fail() {
                    public void fail(ApiException e) {
                        if ("email_not_verified".equals(e.code)) {
                            startActivity(new Intent(ChatsActivity.this, AuthActivity.class).putExtra("mode", "verify"));
                            finish();
                        } else toast(e.getMessage());
                    }
                });
    }

    private void loadStatus() {
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.get("/api/model/status"); } },
                new Done<JSONObject>() { public void done(JSONObject s) { showStatus(s); } },
                new Fail() { public void fail(ApiException e) { showStatus(null); } });
    }

    private void showStatus(JSONObject s) {
        String state = s == null ? "offline" : s.optString("state");
        String text;
        int color;
        if ("online".equals(state)) {
            int waiting = s.optInt("queue_waiting");
            text = waiting > 0 ? "● очередь: " + waiting : "● модель онлайн";
            if ("mock".equals(s.optString("engine"))) text += " (тест)";
            color = s.optBoolean("busy") ? pal.warn : pal.green;
        } else if ("loading".equals(state)) { text = "● загрузка модели"; color = pal.warn; }
        else { text = "● модель офлайн"; color = pal.danger; }
        statusPill.setText(text);
        statusPill.setTextColor(color);
    }

    private void open(String id) {
        startActivity(new Intent(this, ChatActivity.class).putExtra("chat_id", id));
    }

    private void newChat() {
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/chats", new JSONObject()); } },
                new Done<JSONObject>() { public void done(JSONObject c) { open(c.optString("id")); } });
    }

    private void chatMenu(final JSONObject c) {
        new AlertDialog.Builder(this).setTitle(c.optString("title"))
                .setItems(new String[]{"Переименовать", "Удалить"}, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int which) { if (which == 0) rename(c); else delete(c); }
                }).show();
    }

    private void rename(final JSONObject c) {
        final EditText e = Ui.input(this, pal, "Название", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        e.setText(c.optString("title"));
        new AlertDialog.Builder(this).setTitle("Переименовать чат").setView(wrap(e))
                .setPositiveButton("Сохранить", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        final String t = e.getText().toString().trim();
                        if (t.isEmpty()) return;
                        bg(new Task<JSONObject>() {
                            public JSONObject run() throws ApiException { return app.api.patch("/api/chats/" + c.optString("id"), AuthActivity.json("title", t)); }
                        }, new Done<JSONObject>() { public void done(JSONObject r) { load(); } });
                    }
                }).setNegativeButton("Отмена", null).show();
    }

    private void delete(final JSONObject c) {
        new AlertDialog.Builder(this).setTitle("Удалить чат?").setMessage("Диалог будет удалён на всех устройствах.")
                .setPositiveButton("Удалить", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.delete("/api/chats/" + c.optString("id")); } },
                                new Done<JSONObject>() { public void done(JSONObject r) { app.prefs.draft(c.optString("id"), null); load(); } });
                    }
                }).setNegativeButton("Отмена", null).show();
    }

    View wrap(View v) {
        FrameLayout f = new FrameLayout(this);
        int p = Ui.dp(this, 20);
        f.setPadding(p, Ui.dp(this, 8), p, 0);
        f.addView(v);
        return f;
    }
}
