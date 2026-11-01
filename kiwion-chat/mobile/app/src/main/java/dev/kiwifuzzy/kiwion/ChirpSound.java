package dev.kiwifuzzy.kiwion;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;

/** A tiny synthesized "happy kiwi" chirp — generated in code, so no audio files and no internet. */
public final class ChirpSound {
    private ChirpSound() {}

    public static void play() {
        new Thread(new Runnable() {
            public void run() {
                try {
                    int rate = 22050;
                    float[][] notes = {{1250, 1750, 0f}, {1500, 2100, 0.16f}, {1900, 1600, 0.34f}};
                    int total = (int) (rate * 0.52f);
                    short[] pcm = new short[total];
                    for (float[] n : notes) {
                        int start = (int) (n[2] * rate), len = (int) (0.14f * rate);
                        double phase = 0;
                        for (int i = 0; i < len && start + i < total; i++) {
                            double t = i / (double) len;
                            double f = n[0] * Math.pow(n[1] / n[0], Math.min(1, t / 0.85));
                            phase += 2 * Math.PI * f / rate;
                            double env = Math.min(1, t * 12) * Math.pow(1 - t, 2);
                            pcm[start + i] += (short) (Math.sin(phase) * env * 6500);
                        }
                    }
                    @SuppressWarnings("deprecation")
                    AudioTrack track = new AudioTrack(AudioManager.STREAM_MUSIC, rate, AudioFormat.CHANNEL_OUT_MONO,
                            AudioFormat.ENCODING_PCM_16BIT, pcm.length * 2, AudioTrack.MODE_STATIC);
                    track.write(pcm, 0, pcm.length);
                    track.play();
                    Thread.sleep(700);
                    track.release();
                } catch (Exception ignored) {
                    // sound is optional (e.g. no audio device)
                }
            }
        }, "kiwi-chirp").start();
    }
}
