package luckypit;

/** A screen opened from somewhere that returns there on the right soft key. */
public abstract class BackScreen extends Screen {
    public Screen back;

    protected void goBack() {
        mm.sfx(SoundManager.MOVE);
        if (back != null) {
            mm.go(back);
        } else {
            mm.go(mm.mainMenu);
        }
    }
}
