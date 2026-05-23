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
    private static final long DEFAULT_DISABLE_TIME_SEC = 1L;
    private static final int DEFAULT_BRIGHTNESS = 255;
    private static final String HBM_BACKLIGHT_VALUE = "2047";

    private static volatile boolean mAutoHBMActive = false;
    private ExecutorService mExecutorService;

    private SensorManager mSensorManager;
    private Sensor mLightSensor;
    private KeyguardManager mKeyguardManager;

    private SharedPreferences mSharedPrefs;
    private boolean dcDimmingEnabled;

    private int mStoredBrightness = -1;

    // Sensor thread'in en son okuduğu lux; worker thread sleep sonrası burayı okur (stale closure değil).
    private volatile float mLastLux = 0f;
    // Bekleyen disable runnable'ı; lux tekrar yükselirse iptal edilir, duplicate submit önlenir.
    private volatile Future<?> mPendingDisable;
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
        cancelPendingDisable();
        safeSubmit(() -> {
            try {
                if (mSensorManager != null) {
                    mSensorManager.unregisterListener(mSensorEventListener);
                }
                mAutoHBMActive = false;
                enableHBM(false);
            } catch (Exception e) {
                Log.w(TAG, "deactivateLightSensorRead failed", e);
            }
        });
    }

    private void enableHBM(boolean enable) {
        try {
            if (enable) {
                if (mStoredBrightness == -1) {
                    try {
                        mStoredBrightness = Settings.System.getInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS, DEFAULT_BRIGHTNESS);
                    } catch (Exception e) {
                        mStoredBrightness = DEFAULT_BRIGHTNESS;
                    }
                }
                FileUtils.writeLine(HBM, "1");
                FileUtils.writeLine(BACKLIGHT, HBM_BACKLIGHT_VALUE);
                try {
                    Settings.System.putInt(getContentResolver(),
                            Settings.System.SCREEN_BRIGHTNESS, DEFAULT_BRIGHTNESS);
                } catch (Exception e) {
                    Log.w(TAG, "Failed to set screen brightness", e);
                }
            } else {
                FileUtils.writeLine(HBM, "0");
                if (mStoredBrightness != -1) {
                    FileUtils.writeLine(BACKLIGHT, String.valueOf(mStoredBrightness));
                    try {
                        Settings.System.putInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS, mStoredBrightness);
                    } catch (Exception e) {
                        Log.w(TAG, "Failed to restore screen brightness", e);
                    }
                    mStoredBrightness = -1;
                }
            }
        } catch (Throwable t) {
            // Sysfs node yoksa / yazma izni yoksa / SELinux denial olursa
            // executor'u tıkamadan logla ve devam et.
            Log.e(TAG, "enableHBM(" + enable + ") failed", t);
        }
    }

    private boolean isCurrentlyEnabled() {
        try {
            return FileUtils.getFileValueAsBoolean(HBM, false);
        } catch (Throwable t) {
            return false;
        }
    }

    private final SensorEventListener mSensorEventListener = new SensorEventListener() {

        @Override
        public void onSensorChanged(SensorEvent event) {
            try {
                if (event == null || event.values == null || event.values.length == 0) {
                    return;
                }
                final float lux = event.values[0];
                mLastLux = lux;

                final KeyguardManager km = mKeyguardManager;
                final boolean keyguardShowing = km != null && km.isKeyguardLocked();

                final float luxThreshold = readFloatPref(
                        HBMFragment.KEY_AUTO_HBM_THRESHOLD, DEFAULT_LUX_THRESHOLD);
                final long timeToDisableHBM = readLongPref(
                        HBMFragment.KEY_HBM_DISABLE_TIME, DEFAULT_DISABLE_TIME_SEC);

                if (lux > luxThreshold) {
                    // Bekleyen disable varsa iptal et — lux tekrar yükseldi.
                    cancelPendingDisable();
                    if ((!mAutoHBMActive || !isCurrentlyEnabled())
                            && !keyguardShowing && !dcDimmingEnabled) {
                        mAutoHBMActive = true;
                        // Tüm HBM dosya I/O'sunu tek thread'de serileştir.
                        safeSubmit(() -> enableHBM(true));
                    }
                } else if (lux < luxThreshold) {
                    // Zaten bekleyen disable varsa yenisini submit etme.
                    final Future<?> pending = mPendingDisable;
                    if (mAutoHBMActive && (pending == null || pending.isDone())) {
                        mPendingDisable = safeSubmit(() -> {
                            if (timeToDisableHBM > 0L) {
                                try {
                                    Thread.sleep(timeToDisableHBM * 1000L);
                                } catch (InterruptedException ignored) {
                                    return; // cancel edildi
                                }
                            }
                            // Sleep sonrası en güncel lux'u oku — closure'dan eski değer değil.
                            if (mLastLux < luxThreshold && mAutoHBMActive) {
                                mAutoHBMActive = false;
                                enableHBM(false);
                            }
                        });
                    }
                }
            } catch (Throwable t) {
                // Sensor event'i hiçbir koşulda main thread'i çökertmemeli.
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
        cancelPendingDisable();
        safeSubmit(() -> {
            try {
                if (mSensorManager != null) {
                    mSensorManager.unregisterListener(mSensorEventListener);
                }
                mAutoHBMActive = false;
                enableHBM(false);
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
