import java.awt.Rectangle;
import java.awt.Robot;
import java.awt.event.InputEvent;
import java.awt.event.KeyEvent;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/**
 * Drives MicroEmulator under Xvfb with real key presses and grabs the
 * 240x320 device display.  Commands: k:5 k:F1 k:STAR k:POUND k:UP ...
 * w:ms (wait), s:file.png (screenshot), r:N:k:5:w:300 (repeat), c (click to focus)
 */
public class EmuDriver {
    static int X0 = 0, Y0 = 22;

    public static void main(String[] a) throws Exception {
        Robot r = new Robot();
        r.setAutoDelay(30);
        String dir = System.getProperty("out", ".");
        for (int i = 0; i < a.length; i++) {
            run(r, a[i], dir);
        }
    }

    static void run(Robot r, String cmd, String dir) throws Exception {
        if (cmd.equals("c")) {
            r.mouseMove(X0 + 120, Y0 + 160);
            r.mousePress(InputEvent.BUTTON1_DOWN_MASK);
            r.mouseRelease(InputEvent.BUTTON1_DOWN_MASK);
        } else if (cmd.startsWith("w:")) {
            Thread.sleep(Integer.parseInt(cmd.substring(2)));
        } else if (cmd.startsWith("s:")) {
            BufferedImage im = r.createScreenCapture(new Rectangle(X0, Y0, 240, 320));
            ImageIO.write(im, "png", new File(dir, cmd.substring(2)));
        } else if (cmd.equals("k:HASH")) {
            r.keyPress(KeyEvent.VK_SHIFT);
            r.keyPress(KeyEvent.VK_3);
            Thread.sleep(60);
            r.keyRelease(KeyEvent.VK_3);
            r.keyRelease(KeyEvent.VK_SHIFT);
            Thread.sleep(80);
        } else if (cmd.startsWith("k:")) {
            int code = code(cmd.substring(2));
            r.keyPress(code);
            Thread.sleep(60);
            r.keyRelease(code);
            Thread.sleep(80);
        } else if (cmd.startsWith("r:")) {
            String[] p = cmd.split(":", 3);
            int n = Integer.parseInt(p[1]);
            String[] sub = p[2].split(",");
            for (int i = 0; i < n; i++) {
                for (int j = 0; j < sub.length; j++) {
                    run(r, sub[j].replace('=', ':'), dir);
                }
            }
        }
    }

    static int code(String k) {
        if (k.length() == 1 && Character.isDigit(k.charAt(0))) {
            return KeyEvent.VK_0 + (k.charAt(0) - '0');
        }
        if (k.equals("F1")) return KeyEvent.VK_F1;
        if (k.equals("F2")) return KeyEvent.VK_F2;
        if (k.equals("UP")) return KeyEvent.VK_UP;
        if (k.equals("DOWN")) return KeyEvent.VK_DOWN;
        if (k.equals("LEFT")) return KeyEvent.VK_LEFT;
        if (k.equals("RIGHT")) return KeyEvent.VK_RIGHT;
        if (k.equals("ENTER")) return KeyEvent.VK_ENTER;
        if (k.equals("STAR")) return KeyEvent.VK_MULTIPLY;
        if (k.equals("POUND")) return KeyEvent.VK_SUBTRACT; // MicroEmulator maps numpad "-" to #
        if (k.equals("ESC")) return KeyEvent.VK_ESCAPE;
        if (k.equals("BS")) return KeyEvent.VK_BACK_SPACE;
        throw new IllegalArgumentException(k);
    }
}
