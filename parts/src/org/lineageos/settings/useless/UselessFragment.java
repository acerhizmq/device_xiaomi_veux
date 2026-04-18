package org.lineageos.settings.useless;

import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Bundle;
import android.os.Vibrator;
import android.preference.PreferenceManager;
import android.util.Log;
import android.view.Window;
import android.view.WindowManager;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragment;
import androidx.preference.TwoStatePreference;
import org.lineageos.settings.R;
import java.util.Random;

public class UselessFragment extends PreferenceFragment
        implements Preference.OnPreferenceChangeListener {

    private static final String KEY_USELESS_MODE = "useless_mode";
    private static final float SOUND_PROBABILITY = 0.15f; // 15% chance

    private TwoStatePreference mUselessModePreference;
    private SharedPreferences mSharedPrefs;
    private Random mRandom;
    private Vibrator mVibrator;
    private MediaPlayer mMediaPlayer;
    private AudioManager mAudioManager;
    private int mOriginalVolume;

    // Vibration patterns (delay, vibrate, pause, vibrate...)
    private final long[][] mVibrationPatterns = {
        {0, 100, 100, 100},           // Quick double buzz
        {0, 200, 50, 200, 50, 200},   // Triple buzz
        {0, 500},                     // Long buzz
        {0, 50, 50, 50, 50, 50},      // Rapid fire
        {0, 100, 200, 300, 100, 100}, // Escalating pattern
        {0, 800},                     // Very long buzz
        {0, 25, 25, 25, 25, 25, 25, 25} // Morse code-ish
    };

    private final String[] mRandomSentences = {
        "Congratulations! You've successfully accomplished absolutely nothing!",
        "This toggle is as useful as a chocolate teapot.",
        "You just wasted 0.003 seconds of your life. Was it worth it?",
        "Fun fact: This button has been pressed 42 times by confused users.",
        "Warning: Excessive use of this toggle may cause mild confusion.",
        "This setting is brought to you by the Department of Redundancy Department.",
        "You've unlocked the achievement: 'Master of Pointless Actions'",
        "Error 404: Functionality not found.",
        "This toggle is working exactly as intended... which is not at all.",
        "Beep boop! Robot sounds make everything seem more important.",
        "Achievement unlocked: Professional Time Waster!",
        "This feature has the same effect as shouting at clouds.",
        "Congratulations! Your uselessness level has increased by 0%!",
        "*BZZZZT* Your phone is now vibrating for no reason!",
        "Screen flicker activated! Because why not?",
        "Your device is now experiencing a mild existential crisis."
    };

    private final String[] mWarningMessages = {
        "Are you sure you want to enable this completely useless feature?",
        "Warning: This action will have absolutely no effect on your device!",
        "Caution: Proceeding will result in nothing happening whatsoever.",
        "Alert: This toggle exists purely for entertainment purposes.",
        "Notice: No electrons were harmed in the making of this toggle.",
        "Disclaimer: This setting is certified 100% useless by experts.",
        "Warning: May cause sudden urges to toggle more useless settings.",
        "Alert: May cause random vibrations and screen flickering!",
        "Caution: Side effects include pointless buzzing and blinking."
    };

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.useless_settings, rootKey);

        mSharedPrefs = PreferenceManager.getDefaultSharedPreferences(getContext());
        mRandom = new Random();
        mVibrator = (Vibrator) getContext().getSystemService(Context.VIBRATOR_SERVICE);
        mAudioManager = (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);

        mUselessModePreference = (TwoStatePreference) findPreference(KEY_USELESS_MODE);
        if (mUselessModePreference != null) {
            boolean isUselessMode = mSharedPrefs.getBoolean(KEY_USELESS_MODE, false);
            mUselessModePreference.setChecked(isUselessMode);
            mUselessModePreference.setOnPreferenceChangeListener(this);
            updateSummary(isUselessMode);
        }
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        if (KEY_USELESS_MODE.equals(preference.getKey())) {
            boolean enabled = (Boolean) newValue;

            // Always add some random effects when toggling
            performRandomEffects();

            if (enabled) {
                showWarningDialog(() -> {
                    enableUselessMode(true);
                    updateSummary(true);
                });
                return false;
            } else {
                enableUselessMode(false);
                updateSummary(false);
                showRandomMessage();
                return true;
            }
        }
        return false;
    }

    private void performRandomEffects() {
        // 70% chance to vibrate
        if (mRandom.nextFloat() < 0.7f && mVibrator != null && mVibrator.hasVibrator()) {
            performRandomVibration();
        }

        // 50% chance to flicker screen
        if (mRandom.nextFloat() < 0.5f) {
            performScreenFlicker();
        }

        // 15% chance to play sound
        playRandomSound();
    }

    private void playRandomSound() {
        if (mRandom.nextFloat() >= SOUND_PROBABILITY) return;

        try {
            if (mMediaPlayer != null) {
                mMediaPlayer.release();
                mMediaPlayer = null;
            }

            // Save original volume
            mOriginalVolume = mAudioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
            int maxVolume = mAudioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVolume, 0);

            mMediaPlayer = MediaPlayer.create(getContext(), R.raw.useless_sound);
            if (mMediaPlayer == null) return;
            mMediaPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);

            mMediaPlayer.setOnCompletionListener(mp -> {
                cleanupMediaPlayer();
                mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, mOriginalVolume, 0);
            });

            mMediaPlayer.setOnErrorListener((mp, what, extra) -> {
                cleanupMediaPlayer();
                mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, mOriginalVolume, 0);
                return true;
            });

            mMediaPlayer.start();
        } catch (Exception e) {
            Log.e("UselessMode", "Error playing sound", e);
            cleanupMediaPlayer();
            if (mAudioManager != null) {
                mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, mOriginalVolume, 0);
            }
        }
    }

    private void cleanupMediaPlayer() {
        if (mMediaPlayer != null) {
            try {
                mMediaPlayer.stop();
            } catch (Exception ignored) {}
            mMediaPlayer.release();
            mMediaPlayer = null;
        }
    }

    private void performRandomVibration() {
        long[] pattern = mVibrationPatterns[mRandom.nextInt(mVibrationPatterns.length)];
        mVibrator.vibrate(pattern, -1); // -1 means don't repeat
    }

    private void performScreenFlicker() {
        if (getActivity() == null) return;

        Window window = getActivity().getWindow();
        WindowManager.LayoutParams params = window.getAttributes();
        float originalBrightness = params.screenBrightness;

        // Create flicker effect
        new Thread(() -> {
            try {
                for (int i = 0; i < 3; i++) {
                    // Dim screen
                    getActivity().runOnUiThread(() -> {
                        params.screenBrightness = 0.1f;
                        window.setAttributes(params);
                    });
                    Thread.sleep(100);

                    // Brighten screen
                    getActivity().runOnUiThread(() -> {
                        params.screenBrightness = 1.0f;
                        window.setAttributes(params);
                    });
                    Thread.sleep(100);
                }

                // Restore original brightness
                getActivity().runOnUiThread(() -> {
                    params.screenBrightness = originalBrightness;
                    window.setAttributes(params);
                });

            } catch (InterruptedException e) {
                // Restore brightness if interrupted
                getActivity().runOnUiThread(() -> {
                    params.screenBrightness = originalBrightness;
                    window.setAttributes(params);
                });
            }
        }).start();
    }

    private void showWarningDialog(Runnable onConfirm) {
        String warningMessage = mWarningMessages[mRandom.nextInt(mWarningMessages.length)];

        // Vibrate when showing warning
        if (mVibrator != null && mVibrator.hasVibrator()) {
            mVibrator.vibrate(200);
        }

        new AlertDialog.Builder(getContext())
            .setTitle(getString(R.string.useless_mode_warning_title))
            .setMessage(warningMessage)
            .setPositiveButton(getString(R.string.useless_mode_accept), (dialog, which) -> {
                // Celebration vibration
                if (mVibrator != null && mVibrator.hasVibrator()) {
                    long[] celebrationPattern = {0, 100, 50, 100, 50, 300};
                    mVibrator.vibrate(celebrationPattern, -1);
                }
                onConfirm.run();
                mUselessModePreference.setChecked(true);
                showRandomMessage();
            })
            .setNegativeButton(getString(R.string.useless_mode_cancel), (dialog, which) -> {
                // Sad vibration
                if (mVibrator != null && mVibrator.hasVibrator()) {
                    mVibrator.vibrate(500);
                }
            })
            .setIcon(android.R.drawable.ic_dialog_alert)
            .show();
    }

    private void showRandomMessage() {
        String randomSentence = mRandomSentences[mRandom.nextInt(mRandomSentences.length)];

        // Random vibration with message
        performRandomEffects();

        new AlertDialog.Builder(getContext())
            .setTitle(getString(R.string.useless_mode_status_title))
            .setMessage(randomSentence)
            .setPositiveButton(getString(R.string.useless_mode_amazing), (dialog, which) -> {
                // Final celebration effect
                if (mRandom.nextBoolean() && mVibrator != null && mVibrator.hasVibrator()) {
                    mVibrator.vibrate(100);
                }
            })
            .setIcon(android.R.drawable.ic_dialog_info)
            .show();
    }

    private void enableUselessMode(boolean enabled) {
        mSharedPrefs.edit().putBoolean(KEY_USELESS_MODE, enabled).apply();

        // Extra effects when enabling/disabling
        if (enabled) {
            // Enabling effects
            performScreenFlicker();
            if (mVibrator != null && mVibrator.hasVibrator()) {
                long[] enablePattern = {0, 50, 50, 50, 50, 200};
                mVibrator.vibrate(enablePattern, -1);
            }
        } else {
            // Disabling effects
            if (mVibrator != null && mVibrator.hasVibrator()) {
                mVibrator.vibrate(300);
            }
        }

        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            // Even our fake processing failed!
        }
    }

    private void updateSummary(boolean enabled) {
        if (mUselessModePreference != null) {
            String summary = enabled ?
                getString(R.string.useless_mode_enabled_summary) :
                getString(R.string.useless_mode_disabled_summary);
            mUselessModePreference.setSummary(summary);
        }
    }
}
