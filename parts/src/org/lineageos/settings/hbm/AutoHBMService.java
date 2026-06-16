package org.lineageos.settings.hbm;

import android.app.KeyguardManager;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;

import androidx.preference.PreferenceManager;

import org.lineageos.settings.utils.FileUtils;
import org.lineageos.settings.display.*;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;

public class AutoHBMService extends Service {
    private static final String TAG = "AutoHBMService";

    private static final String HBM = "/sys/devices/platform/soc/5e00000.qcom,mdss_mdp/drm/card0/card0-DSI-1/hbm";
    private static final String BACKLIGHT = "/sys/class/backlight/panel0-backlight/brightness";

    // SharedPreferences corrupt olsa bile uygulanacak güvenli varsayılanlar.
    private static final float DEFAULT_LUX_THRESHOLD = 20000f;
    private static final long DEFAULT_ENABLE_TIME_SEC = 2L;
    private static final long DEFAULT_DISABLE_TIME_SEC = 5L;
    private static final int DEFAULT_BRIGHTNESS = 255;
    private static final int BACKLIGHT_MAX = 2047;

    // Histerezis: kapatma eşiği açma eşiğinin bu oranı kadar düşük olmalı.
    private static final float HBM_OFF_THRESHOLD_RATIO = 0.65f;
    private static final int LUX_AVG_SAMPLES = 12;
    private static final long MIN_TOGGLE_INTERVAL_MS = 4500L;
    private static final int BRIGHTNESS_RAMP_STEPS = 24;
    private static final long BRIGHTNESS_RAMP_STEP_MS = 70L;

    private static volatile boolean mAutoHBMActive = false;
    private ExecutorService mExecutorService;

    private SensorManager mSensorManager;
    private Sensor mLightSensor;
    private KeyguardManager mKeyguardManager;

    private SharedPreferences mSharedPrefs;

    private int mStoredBrightness = -1;

    private final float[] mLuxSamples = new float[LUX_AVG_SAMPLES];
    private int mLuxSampleIndex = 0;
    private int mLuxSampleCount = 0;

    // Sensor thread'in en son okuduğu lux; worker thread sleep sonrası burayı okur (stale closure değil).
    private volatile float mLastLux = 0f;
    private volatile long mLastToggleTime = 0L;
    // Bekleyen enable/disable runnable'ları; lux tersine dönerse iptal edilir.
    private volatile Future<?> mPendingEnable;
    private volatile Future<?> mPendingDisable;
    private volatile boolean mTransitionInProgress = false;
    // Çift unregisterReceiver / shutdown koruması için bayraklar.
    private volatile boolean mReceiverRegistered = false;

    public void activateLightSensorRead() {
        safeSubmit(() -> {
            try {
                if (mSensorManager == null) {
                    mSensorManager = (SensorManager) getApplicationContext()
                            .getSystemService(Context.SENSOR_SERVICE);
                }
                if (mSensorManager == null) {
                    Log.w(TAG, "SensorManager unavailable; skipping sensor register");
                    return;
                }
                if (mLightSensor == null) {
                    mLightSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_LIGHT);
                }
                if (mLightSensor == null) {
                    Log.w(TAG, "Light sensor not available on this device");
                    return;
                }
                mSensorManager.registerListener(mSensorEventListener, mLightSensor,
                        SensorManager.SENSOR_DELAY_NORMAL);
            } catch (Exception e) {
                Log.e(TAG, "activateLightSensorRead failed", e);
            }
        });
    }

    public void deactivateLightSensorRead() {
        cancelPendingEnable();
        cancelPendingDisable();
        safeSubmit(() -> {
            try {
                if (mSensorManager != null) {
                    mSensorManager.unregisterListener(mSensorEventListener);
                }
                mAutoHBMActive = false;
                setHbmImmediate(false);
            } catch (Exception e) {
                Log.w(TAG, "deactivateLightSensorRead failed", e);
            }
        });
    }

    private int getCurrentBrightness() {
        try {
            return Settings.System.getInt(getContentResolver(),
                    Settings.System.SCREEN_BRIGHTNESS, DEFAULT_BRIGHTNESS);
        } catch (Exception e) {
            return DEFAULT_BRIGHTNESS;
        }
    }

    private int readBacklightLevel() {
        final String raw = FileUtils.readOneLine(BACKLIGHT);
        if (raw == null) {
            return settingsToBacklight(getCurrentBrightness());
        }
        try {
            return Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            return settingsToBacklight(getCurrentBrightness());
        }
    }

    private static int settingsToBacklight(int settingsBrightness) {
        return (settingsBrightness * BACKLIGHT_MAX) / DEFAULT_BRIGHTNESS;
    }

    private void rampBacklight(int from, int to) throws InterruptedException {
        if (from == to) {
            FileUtils.writeLine(BACKLIGHT, String.valueOf(to));
            return;
        }
        for (int step = 1; step <= BRIGHTNESS_RAMP_STEPS; step++) {
            if (Thread.currentThread().isInterrupted()) {
                return;
            }
            final int value = from + (to - from) * step / BRIGHTNESS_RAMP_STEPS;
            FileUtils.writeLine(BACKLIGHT, String.valueOf(value));
            Thread.sleep(BRIGHTNESS_RAMP_STEP_MS);
        }
    }

    private void rampSettingsBrightness(int from, int to) throws InterruptedException {
        if (from == to) {
            try {
                Settings.System.putInt(getContentResolver(),
                        Settings.System.SCREEN_BRIGHTNESS, to);
            } catch (Exception e) {
                Log.w(TAG, "Failed to set screen brightness", e);
            }
            return;
        }
        for (int step = 1; step <= BRIGHTNESS_RAMP_STEPS; step++) {
            if (Thread.currentThread().isInterrupted()) {
                return;
            }
            final int value = from + (to - from) * step / BRIGHTNESS_RAMP_STEPS;
            try {
                Settings.System.putInt(getContentResolver(),
                        Settings.System.SCREEN_BRIGHTNESS, value);
            } catch (Exception e) {
                Log.w(TAG, "Failed to ramp screen brightness", e);
                return;
            }
            Thread.sleep(BRIGHTNESS_RAMP_STEP_MS);
        }
    }

    private void transitionToHbmEnabled() throws InterruptedException {
        if (mStoredBrightness == -1) {
            mStoredBrightness = getCurrentBrightness();
        }
        final int startSettings = mStoredBrightness;
        final int startBacklight = readBacklightLevel();

        FileUtils.writeLine(HBM, "1");
        rampBacklight(startBacklight, BACKLIGHT_MAX);
        rampSettingsBrightness(startSettings, DEFAULT_BRIGHTNESS);
    }

    private void transitionToHbmDisabled() throws InterruptedException {
        if (mStoredBrightness == -1) {
            FileUtils.writeLine(HBM, "0");
            return;
        }
        final int targetSettings = mStoredBrightness;
        final int targetBacklight = settingsToBacklight(targetSettings);
        final int startBacklight = readBacklightLevel();

        rampBacklight(startBacklight, targetBacklight);
        FileUtils.writeLine(HBM, "0");
        try {
            Settings.System.putInt(getContentResolver(),
                    Settings.System.SCREEN_BRIGHTNESS, targetSettings);
        } catch (Exception e) {
            Log.w(TAG, "Failed to restore screen brightness", e);
        }
        mStoredBrightness = -1;
    }

    private void setHbmImmediate(boolean enable) {
        try {
            if (enable) {
                if (mStoredBrightness == -1) {
                    mStoredBrightness = getCurrentBrightness();
                }
                FileUtils.writeLine(HBM, "1");
                FileUtils.writeLine(BACKLIGHT, String.valueOf(BACKLIGHT_MAX));
                Settings.System.putInt(getContentResolver(),
                        Settings.System.SCREEN_BRIGHTNESS, DEFAULT_BRIGHTNESS);
            } else {
                FileUtils.writeLine(HBM, "0");
                if (mStoredBrightness != -1) {
                    Settings.System.putInt(getContentResolver(),
                            Settings.System.SCREEN_BRIGHTNESS, mStoredBrightness);
                    mStoredBrightness = -1;
                }
            }
        } catch (Throwable t) {
            Log.e(TAG, "setHbmImmediate(" + enable + ") failed", t);
        }
    }

    private void enableHBM(boolean enable) {
        if (mTransitionInProgress) {
            return;
        }
        mTransitionInProgress = true;
        try {
            if (enable) {
                transitionToHbmEnabled();
            } else {
                transitionToHbmDisabled();
            }
        } catch (InterruptedException ignored) {
            setHbmImmediate(false);
            Thread.currentThread().interrupt();
        } catch (Throwable t) {
            Log.e(TAG, "enableHBM(" + enable + ") failed", t);
        } finally {
            mTransitionInProgress = false;
        }
    }

    private boolean isCurrentlyEnabled() {
        try {
            return FileUtils.getFileValueAsBoolean(HBM, false);
        } catch (Throwable t) {
            return false;
        }
    }

    private void recordLuxSample(float lux) {
        mLastLux = lux;
        mLuxSamples[mLuxSampleIndex] = lux;
        mLuxSampleIndex = (mLuxSampleIndex + 1) % LUX_AVG_SAMPLES;
        if (mLuxSampleCount < LUX_AVG_SAMPLES) {
            mLuxSampleCount++;
        }
    }

    private float getSmoothedLux() {
        if (mLuxSampleCount == 0) {
            return mLastLux;
        }
        float sum = 0f;
        for (int i = 0; i < mLuxSampleCount; i++) {
            sum += mLuxSamples[i];
        }
        return sum / mLuxSampleCount;
    }

    private float getOffThreshold(float onThreshold) {
        return onThreshold * HBM_OFF_THRESHOLD_RATIO;
    }

    private boolean canToggleState() {
        return SystemClock.elapsedRealtime() - mLastToggleTime >= MIN_TOGGLE_INTERVAL_MS;
    }

    private void markToggled() {
        mLastToggleTime = SystemClock.elapsedRealtime();
    }

    private boolean isDcDimmingEnabled() {
        return mSharedPrefs.getBoolean(DcDimmingTileService.DC_DIMMING_ENABLE_KEY, false);
    }

    private final SensorEventListener mSensorEventListener = new SensorEventListener() {

        @Override
        public void onSensorChanged(SensorEvent event) {
            try {
                if (event == null || event.values == null || event.values.length == 0) {
                    return;
                }
                recordLuxSample(event.values[0]);
                final float avgLux = getSmoothedLux();

                final KeyguardManager km = mKeyguardManager;
                final boolean keyguardShowing = km != null && km.isKeyguardLocked();

                final float luxThreshold = readFloatPref(
                        HBMFragment.KEY_AUTO_HBM_THRESHOLD, DEFAULT_LUX_THRESHOLD);
                final float offThreshold = getOffThreshold(luxThreshold);
                final long timeToEnableHBM = DEFAULT_ENABLE_TIME_SEC;
                final long timeToDisableHBM = readLongPref(
                        HBMFragment.KEY_HBM_DISABLE_TIME, DEFAULT_DISABLE_TIME_SEC);

                if (mTransitionInProgress) {
                    return;
                }

                if (avgLux > luxThreshold) {
                    cancelPendingDisable();
                    if ((!mAutoHBMActive || !isCurrentlyEnabled())
                            && !keyguardShowing && !isDcDimmingEnabled()
                            && canToggleState()) {
                        final Future<?> pendingEnable = mPendingEnable;
                        if (pendingEnable == null || pendingEnable.isDone()) {
                            final float enableLuxThreshold = luxThreshold;
                            mPendingEnable = safeSubmit(() -> {
                                if (timeToEnableHBM > 0L) {
                                    try {
                                        Thread.sleep(timeToEnableHBM * 1000L);
                                    } catch (InterruptedException ignored) {
                                        return;
                                    }
                                }
                                if (getSmoothedLux() > enableLuxThreshold
                                        && !mAutoHBMActive && canToggleState()
                                        && !isDcDimmingEnabled()) {
                                    enableHBM(true);
                                    if (isCurrentlyEnabled()) {
                                        mAutoHBMActive = true;
                                        markToggled();
                                    }
                                }
                            });
                        }
                    }
                } else if (avgLux < offThreshold) {
                    cancelPendingEnable();
                    final Future<?> pending = mPendingDisable;
                    if (mAutoHBMActive && (pending == null || pending.isDone())) {
                        final float disableLuxThreshold = offThreshold;
                        mPendingDisable = safeSubmit(() -> {
                            if (timeToDisableHBM > 0L) {
                                try {
                                    Thread.sleep(timeToDisableHBM * 1000L);
                                } catch (InterruptedException ignored) {
                                    return;
                                }
                            }
                            if (getSmoothedLux() < disableLuxThreshold && mAutoHBMActive
                                    && canToggleState()) {
                                enableHBM(false);
                                if (!isCurrentlyEnabled()) {
                                    mAutoHBMActive = false;
                                    markToggled();
                                }
                            }
                        });
                    }
                } else {
                    cancelPendingEnable();
                    cancelPendingDisable();
                }
            } catch (Throwable t) {
                Log.e(TAG, "onSensorChanged failed", t);
            }
        }

        @Override
        public void onAccuracyChanged(Sensor sensor, int accuracy) {
            // do nothing
        }
    };

    private float readFloatPref(String key, float defaultVal) {
        try {
            final String raw = mSharedPrefs.getString(key, String.valueOf(defaultVal));
            return raw != null ? Float.parseFloat(raw) : defaultVal;
        } catch (NumberFormatException | ClassCastException | NullPointerException e) {
            return defaultVal;
        }
    }

    private long readLongPref(String key, long defaultVal) {
        try {
            final String raw = mSharedPrefs.getString(key, String.valueOf(defaultVal));
            return raw != null ? Long.parseLong(raw) : defaultVal;
        } catch (NumberFormatException | ClassCastException | NullPointerException e) {
            return defaultVal;
        }
    }

    private void cancelPendingEnable() {
        final Future<?> pending = mPendingEnable;
        if (pending != null && !pending.isDone()) {
            pending.cancel(true);
        }
        mPendingEnable = null;
    }

    private void cancelPendingDisable() {
        final Future<?> pending = mPendingDisable;
        if (pending != null && !pending.isDone()) {
            pending.cancel(true);
        }
        mPendingDisable = null;
    }

    private final BroadcastReceiver mScreenStateReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent == null || intent.getAction() == null) {
                return;
            }
            if (Intent.ACTION_SCREEN_ON.equals(intent.getAction())) {
                activateLightSensorRead();
            } else if (Intent.ACTION_SCREEN_OFF.equals(intent.getAction())) {
                deactivateLightSensorRead();
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        mExecutorService = Executors.newSingleThreadExecutor(r -> {
            final Thread t = new Thread(r, "AutoHBM-Worker");
            t.setDaemon(true);
            return t;
        });
        mSharedPrefs = PreferenceManager.getDefaultSharedPreferences(getApplicationContext());
        mKeyguardManager = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);

        final IntentFilter screenStateFilter = new IntentFilter(Intent.ACTION_SCREEN_ON);
        screenStateFilter.addAction(Intent.ACTION_SCREEN_OFF);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // API 33+ explicit export flag zorunlu.
                registerReceiver(mScreenStateReceiver, screenStateFilter,
                        Context.RECEIVER_NOT_EXPORTED);
            } else {
                registerReceiver(mScreenStateReceiver, screenStateFilter);
            }
            mReceiverRegistered = true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to register screen state receiver", e);
        }

        try {
            final PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && pm.isInteractive()) {
                activateLightSensorRead();
            }
        } catch (Exception e) {
            Log.w(TAG, "PowerManager.isInteractive failed", e);
        }
    }

    private Future<?> safeSubmit(Runnable runnable) {
        final ExecutorService exec = mExecutorService;
        if (exec == null || exec.isShutdown()) {
            return null;
        }
        try {
            return exec.submit(runnable);
        } catch (RejectedExecutionException e) {
            // Executor kapanış sırasında yarışı kayıpla — sessiz geç.
            return null;
        }
    }

    private void shutdownExecutor() {
        final ExecutorService exec = mExecutorService;
        if (exec == null) return;
        exec.shutdown();
        try {
            if (!exec.awaitTermination(500, TimeUnit.MILLISECONDS)) {
                exec.shutdownNow();
            }
        } catch (InterruptedException e) {
            exec.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        // 1) Yeni sensor event'i gelmemesi için receiver'ı kaldır.
        if (mReceiverRegistered) {
            try {
                unregisterReceiver(mScreenStateReceiver);
            } catch (IllegalArgumentException ignored) {
                // already unregistered — yarış durumuna karşı sessiz geç.
            } catch (Exception e) {
                Log.w(TAG, "unregisterReceiver failed", e);
            }
            mReceiverRegistered = false;
        }

        // 2) Bekleyen işleri iptal et + temizlik işini kuyruğa koy.
        cancelPendingEnable();
        cancelPendingDisable();
        safeSubmit(() -> {
            try {
                if (mSensorManager != null) {
                    mSensorManager.unregisterListener(mSensorEventListener);
                }
                mAutoHBMActive = false;
                setHbmImmediate(false);
            } catch (Exception e) {
                Log.w(TAG, "onDestroy cleanup failed", e);
            }
        });

        // 3) Executor'u kapat (thread leak yok).
        shutdownExecutor();

        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
