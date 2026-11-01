package dev.kiwifuzzy.kiwion;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assume.assumeFalse;
import static org.robolectric.Shadows.shadowOf;

import android.content.Intent;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

import java.util.ArrayList;
import java.util.List;

/** Runs the real app code on the JVM (Robolectric): screens, easter egg, and chat against a live backend. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, application = KiwionApp.class)
@LooperMode(LooperMode.Mode.PAUSED)
public class KiwionUiTest {

    // ------------------------------------------------------------- view helpers
    static void collect(View v, List<View> out) {
        out.add(v);
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) collect(g.getChildAt(i), out);
        }
    }

    static List<View> all(android.app.Activity a) {
        List<View> out = new ArrayList<>();
        collect(a.getWindow().getDecorView(), out);
        return out;
    }

    static View byDescription(android.app.Activity a, String d) {
        for (View v : all(a)) if (d.contentEquals(v.getContentDescription() == null ? "" : v.getContentDescription())) return v;
        return null;
    }

    static TextView byText(android.app.Activity a, String text) {
        for (View v : all(a)) if (v instanceof TextView && v.isShown() && text.contentEquals(((TextView) v).getText())) return (TextView) v;
        return null;
    }

    static TextView containing(android.app.Activity a, String part) {
        for (View v : all(a)) if (v instanceof TextView && ((TextView) v).getText().toString().contains(part)) return (TextView) v;
        return null;
    }

    static void idle() { shadowOf(Looper.getMainLooper()).idle(); }

    interface Cond { boolean ok(); }

    /** Background network threads are real; pump the main looper until the condition holds. */
    static void waitFor(Cond c, long ms) throws InterruptedException {
        long end = System.currentTimeMillis() + ms;
        while (System.currentTimeMillis() < end) {
            idle();
            if (c.ok()) return;
            Thread.sleep(30);
        }
        idle();
        assertTrue("condition not met in " + ms + " ms", c.ok());
    }

    // ------------------------------------------------------------- easter egg (offline)
    @Test
    public void easterEgg_fiveQuickTapsOnVersion_opensFluffyKiwi_andCanBeReplayed() throws Exception {
        KiwionApp.get().prefs.token("kws_offline-test");
        ActivityController<SettingsActivity> ctl = Robolectric.buildActivity(SettingsActivity.class,
                new Intent().putExtra("page", "about")).setup();
        final SettingsActivity a = ctl.get();
        View version = byDescription(a, "Версия приложения " + BuildConfigKiwion.VERSION_NAME);
        assertNotNull("version row exists", version);

        for (int i = 0; i < 4; i++) { version.performClick(); idle(); }
        assertNull("4 taps are not enough", byDescription(a, "Fluffy Kiwi"));
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(1600));   // > 1.5 s pause resets
        for (int i = 0; i < 4; i++) { version.performClick(); idle(); }
        assertNull("counter was reset by the pause", byDescription(a, "Fluffy Kiwi"));
        version.performClick();
        idle();
        assertNotNull("5th quick tap opens the easter egg overlay", byDescription(a, "Fluffy Kiwi"));
        assertNotNull(containing(a, "You've found the Fluffy Kiwi!"));

        // let the whole sequence play: jump, blink, hops, spin, then the pet button appears
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(12));
        TextView pet = byText(a, "Погладить киви");
        assertNotNull(pet);
        assertTrue("pet button enabled after the show", pet.isEnabled() && pet.getAlpha() > 0.9f);
        KiwiView bird = null;
        for (View v : all(a)) if (v instanceof KiwiView && byDescription(a, "Fluffy Kiwi") != null && v.getParent() == byDescription(a, "Fluffy Kiwi")) bird = (KiwiView) v;
        assertNotNull(bird);
        boolean clicked = pet.performClick();
        idle();
        assertTrue("pet click handled", clicked);
        assertTrue("kiwi closes its eyes when petted (bird=" + System.identityHashCode(bird) + ")", bird.isEyesClosed());
        assertTrue("'Kiwi is happy!' is shown", containing(a, "Kiwi is happy!").getAlpha() > 0.9f
                || containing(a, "Kiwi is happy!").animate() != null);
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(3));
        assertFalse("eyes open again", bird.isEyesClosed());

        // close via the × button; UI below is usable again
        byDescription(a, "Закрыть").performClick();
        idle();
        assertNull(byDescription(a, "Fluffy Kiwi"));
        // replay works
        for (int i = 0; i < 5; i++) { version.performClick(); idle(); }
        assertNotNull("can be replayed", byDescription(a, "Fluffy Kiwi"));
        a.onBackPressed();   // back closes the overlay, not the screen
        idle();
        assertNull(byDescription(a, "Fluffy Kiwi"));
        assertFalse(a.isFinishing());
        ctl.pause().stop().destroy();
    }

    @Test
    public void tapCounter_resetsAfterPause() {
        final long[] now = {0};
        TapCounter t = new TapCounter(5, 1500, new TapCounter.Clock() { public long now() { return now[0]; } });
        for (int i = 0; i < 4; i++) { now[0] += 100; assertFalse(t.tap()); }
        now[0] += 2000;
        assertFalse(t.tap());
        assertEquals(1, t.count());
    }

    @Test
    public void splash_showsKiwiAndName_andErrorScreenWhenServerDown() throws Exception {
        KiwionApp.get().prefs.server("http://127.0.0.1:9");   // nothing listens here
        KiwionApp.get().prefs.token(null);
        final SplashActivity a = Robolectric.buildActivity(SplashActivity.class).setup().get();
        assertNotNull(byText(a, "Kiwion Chat"));
        boolean hasKiwi = false;
        for (View v : all(a)) if (v instanceof KiwiView) hasKiwi = true;
        assertTrue("mascot on the launch screen", hasKiwi);
        waitFor(new Cond() { public boolean ok() { return byText(a, "Повторить") != null; } }, 10000);
        assertNotNull(containing(a, "Сервер недоступен"));
    }

    // ------------------------------------------------------------- live backend
    static String server() {
        String s = System.getProperty("kiwion.testServer", "");
        assumeFalse("set KIWION_TEST_SERVER (mobile/run_ui_tests.sh) to run live tests", s.isEmpty());
        return s;
    }

    @Test
    public void live_registerVerifyChatStreamStop() throws Exception {
        String srv = server();
        final KiwionApp app = KiwionApp.get();
        app.prefs.server(srv);
        app.prefs.token(null);
        final String email = "android" + System.nanoTime() + "@kiwion.dev";

        // registration screen with proof-of-work
        final AuthActivity auth = Robolectric.buildActivity(AuthActivity.class, new Intent().putExtra("mode", "register")).setup().get();
        List<EditText> inputs = new ArrayList<>();
        for (View v : all(auth)) if (v instanceof EditText) inputs.add((EditText) v);
        inputs.get(0).setText("Android Kiwi");
        inputs.get(1).setText(email);
        inputs.get(2).setText("kiwi12345");
        byText(auth, "Создать аккаунт").performClick();
        waitFor(new Cond() { public boolean ok() { return byText(auth, "Подтвердите email") != null; } }, 30000);
        assertNotNull("session token stored", app.prefs.token());

        // confirm the e-mail with the code from the mail (the test server exposes the outbox)
        String code = TestMail.verifyCode(srv, email);
        for (View v : all(auth)) if (v instanceof EditText && v.isShown()) ((EditText) v).setText(code);
        byText(auth, "Подтвердить").performClick();
        waitFor(new Cond() { public boolean ok() { return shadowOf(auth).getNextStartedActivity() != null || auth.isFinishing(); } }, 15000);

        // chat list -> new chat via API, then the chat screen streams an answer
        JSONObject chat = app.api.post("/api/chats", new JSONObject());
        final ChatActivity c = Robolectric.buildActivity(ChatActivity.class,
                new Intent().putExtra("chat_id", chat.getString("id"))).setup().get();
        waitFor(new Cond() { public boolean ok() { return containing(c, "Привет! Я киви") != null; } }, 10000);
        EditText input = null;
        for (View v : all(c)) if (v instanceof EditText) input = (EditText) v;
        input.setText("Привет из Android!");
        final Button send = (Button) byDescription(c, "Отправить");
        send.performClick();
        waitFor(new Cond() { public boolean ok() { return "Остановить".contentEquals(send.getContentDescription()); } }, 5000);
        waitFor(new Cond() { public boolean ok() { return "Отправить".contentEquals(send.getContentDescription())
                && containing(c, "Kiwion (mock) получил") != null; } }, 30000);
        assertNotNull("streamed markdown answer contains the prompt", containing(c, "Привет из Android!"));
        assertNotNull("code block rendered with copy action", byText(c, "Копировать"));
        assertEquals("input cleared after send", "", input.getText().toString());

        // stop: start a long answer and press stop
        input.setText("длинный ответ " + new String(new char[30]).replace("\0", "киви "));
        send.performClick();
        waitFor(new Cond() { public boolean ok() { return "Остановить".contentEquals(send.getContentDescription()); } }, 5000);
        Thread.sleep(400);
        idle();
        send.performClick();
        waitFor(new Cond() { public boolean ok() { return containing(c, "Генерация остановлена") != null; } }, 20000);
        JSONObject stored = app.api.get("/api/chats/" + chat.getString("id"));
        assertEquals(4, stored.getJSONArray("messages").length());
        assertEquals("stopped", stored.getJSONArray("messages").getJSONObject(3).getString("status"));
    }

    @Test
    public void live_overloadKeepsText() throws Exception {
        String srv = server();
        final KiwionApp app = KiwionApp.get();
        app.prefs.server(srv);
        String token = TestMail.registerVerified(srv, "ovl" + System.nanoTime() + "@kiwion.dev");
        app.prefs.token(token);
        JSONObject chat = app.api.post("/api/chats", new JSONObject());
        // 9999 chars > max_message_chars: the server rejects it before anything is stored
        final ChatActivity c = Robolectric.buildActivity(ChatActivity.class,
                new Intent().putExtra("chat_id", chat.getString("id"))).setup().get();
        waitFor(new Cond() { public boolean ok() { return containing(c, "Привет! Я киви") != null; } }, 10000);
        EditText input = null;
        for (View v : all(c)) if (v instanceof EditText) input = (EditText) v;
        final String text = new String(new char[9000]).replace("\0", "к");
        input.setText(text);
        final Button send = (Button) byDescription(c, "Отправить");
        send.performClick();
        final EditText in = input;
        waitFor(new Cond() { public boolean ok() { return "Отправить".contentEquals(send.getContentDescription()); } }, 10000);
        assertEquals("text is kept after a rejected send", text, in.getText().toString());
        assertEquals(0, app.api.get("/api/chats/" + chat.getString("id")).getJSONArray("messages").length());
    }
}
