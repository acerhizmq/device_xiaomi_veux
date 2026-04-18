/*
 * Copyright (C) 2025 KamiKaonashi
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 */

package org.lineageos.settings.gpumanager;

import android.os.Bundle;
import android.os.Handler;
import android.widget.Toast;
import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragment;
import androidx.preference.TwoStatePreference;
import org.lineageos.settings.R;

public class GpuManagerFragment extends PreferenceFragment
        implements Preference.OnPreferenceChangeListener {

    private static final String KEY_GPU_GOVERNOR = "gpu_governor";
    private static final String KEY_GPU_MIN_FREQ = "gpu_min_freq";
    private static final String KEY_GPU_MAX_FREQ = "gpu_max_freq";
    private static final String KEY_GPU_CURRENT_FREQ = "gpu_current_freq";
    private static final String KEY_GPU_MODEL = "gpu_model";
    private static final String KEY_GPU_BUSY_PERCENTAGE = "gpu_busy_percentage";
    private static final String KEY_GPU_TEMPERATURE = "gpu_temperature";
    private static final String KEY_GPU_THERMAL_PWRLEVEL = "gpu_thermal_pwrlevel";
    private static final String KEY_GPU_FORCE_CLK_ON = "gpu_force_clk_on";
    private static final String KEY_GPU_FORCE_BUS_ON = "gpu_force_bus_on";
    private static final String KEY_GPU_FORCE_RAIL_ON = "gpu_force_rail_on";
    private static final String KEY_GPU_FORCE_NO_NAP = "gpu_force_no_nap";
    private static final String KEY_GPU_BUS_SPLIT = "gpu_bus_split";
    private static final String KEY_APPLY_GPU_SETTINGS = "apply_gpu_settings";
    private static final String KEY_RESET_GPU_SETTINGS = "reset_gpu_settings";
    
    private GpuManagerUtils mGpuUtils;
    private Handler mHandler;
    private Runnable mUpdateRunnable;
    
    // Preferences
    private ListPreference mGovernorPreference;
    private ListPreference mMinFreqPreference, mMaxFreqPreference;
    private Preference mCurrentFreqPreference;
    private Preference mGpuModelPreference;
    private Preference mGpuBusyPreference;
    private Preference mGpuTemperaturePreference;
    private Preference mThermalPowerLevelPreference;
    private TwoStatePreference mForceClkOnPreference;
    private TwoStatePreference mForceBusOnPreference;
    private TwoStatePreference mForceRailOnPreference;
    private TwoStatePreference mForceNoNapPreference;
    private TwoStatePreference mBusSplitPreference;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.gpu_manager_settings, rootKey);
        mGpuUtils = new GpuManagerUtils();
        mHandler = new Handler();
        
        initializePreferences();
        loadCurrentSettings();
        startPeriodicUpdates();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        stopPeriodicUpdates();
    }

    private void initializePreferences() {
        mGovernorPreference = (ListPreference) findPreference(KEY_GPU_GOVERNOR);
        mMinFreqPreference = (ListPreference) findPreference(KEY_GPU_MIN_FREQ);
        mMaxFreqPreference = (ListPreference) findPreference(KEY_GPU_MAX_FREQ);
        mCurrentFreqPreference = findPreference(KEY_GPU_CURRENT_FREQ);
        mGpuModelPreference = findPreference(KEY_GPU_MODEL);
        mGpuBusyPreference = findPreference(KEY_GPU_BUSY_PERCENTAGE);
        mGpuTemperaturePreference = findPreference(KEY_GPU_TEMPERATURE);
        mThermalPowerLevelPreference = findPreference(KEY_GPU_THERMAL_PWRLEVEL);
        mForceClkOnPreference = (TwoStatePreference) findPreference(KEY_GPU_FORCE_CLK_ON);
        mForceBusOnPreference = (TwoStatePreference) findPreference(KEY_GPU_FORCE_BUS_ON);
        mForceRailOnPreference = (TwoStatePreference) findPreference(KEY_GPU_FORCE_RAIL_ON);
        mForceNoNapPreference = (TwoStatePreference) findPreference(KEY_GPU_FORCE_NO_NAP);
        mBusSplitPreference = (TwoStatePreference) findPreference(KEY_GPU_BUS_SPLIT);
        
        // Set listeners
        if (mGovernorPreference != null) {
            mGovernorPreference.setOnPreferenceChangeListener(this);
        }
        if (mMinFreqPreference != null) {
            mMinFreqPreference.setOnPreferenceChangeListener(this);
        }
        if (mMaxFreqPreference != null) {
            mMaxFreqPreference.setOnPreferenceChangeListener(this);
        }
        
        // Switch preferences
        if (mForceClkOnPreference != null) {
            mForceClkOnPreference.setOnPreferenceChangeListener(this);
        }
        if (mForceBusOnPreference != null) {
            mForceBusOnPreference.setOnPreferenceChangeListener(this);
        }
        if (mForceRailOnPreference != null) {
            mForceRailOnPreference.setOnPreferenceChangeListener(this);
        }
        if (mForceNoNapPreference != null) {
            mForceNoNapPreference.setOnPreferenceChangeListener(this);
        }
        if (mBusSplitPreference != null) {
            mBusSplitPreference.setOnPreferenceChangeListener(this);
        }
        
        // Apply and Reset buttons
        Preference applyPref = findPreference(KEY_APPLY_GPU_SETTINGS);
        if (applyPref != null) {
            applyPref.setOnPreferenceClickListener(preference -> {
                applySettings();
                return true;
            });
        }
        
        Preference resetPref = findPreference(KEY_RESET_GPU_SETTINGS);
        if (resetPref != null) {
            resetPref.setOnPreferenceClickListener(preference -> {
                resetSettings();
                return true;
            });
        }
    }

    private void loadCurrentSettings() {
        // Load GPU model
        if (mGpuModelPreference != null) {
            String gpuModel = mGpuUtils.getGpuModel();
            mGpuModelPreference.setSummary(gpuModel);
        }
        
        // Load available governors
        String[] governors = mGpuUtils.getAvailableGovernors();
        if (governors != null && mGovernorPreference != null) {
            mGovernorPreference.setEntries(governors);
            mGovernorPreference.setEntryValues(governors);
            String currentGovernor = mGpuUtils.getCurrentGovernor();
            mGovernorPreference.setValue(currentGovernor);
            mGovernorPreference.setSummary(getString(R.string.gpu_governor_summary, currentGovernor));
        }
        
        // Load available frequencies
        loadFrequencies();
        
        // Load switch states
        loadSwitchStates();
        
        // Update dynamic info
        updateDynamicInfo();
    }

    private void loadFrequencies() {
        String[] frequencies = mGpuUtils.getAvailableFrequencies();
        if (frequencies != null) {
            String[] frequencyLabels = new String[frequencies.length];
            for (int i = 0; i < frequencies.length; i++) {
                int freqMhz = Integer.parseInt(frequencies[i]) / 1000000;
                frequencyLabels[i] = freqMhz + " MHz";
            }
            
            if (mMinFreqPreference != null) {
                mMinFreqPreference.setEntries(frequencyLabels);
                mMinFreqPreference.setEntryValues(frequencies);
                String currentMinFreq = mGpuUtils.getCurrentMinFrequency();
                mMinFreqPreference.setValue(currentMinFreq);
                int minFreqMhz = Integer.parseInt(currentMinFreq) / 1000000;
                mMinFreqPreference.setSummary(minFreqMhz + " MHz");
            }
            
            if (mMaxFreqPreference != null) {
                mMaxFreqPreference.setEntries(frequencyLabels);
                mMaxFreqPreference.setEntryValues(frequencies);
                String currentMaxFreq = mGpuUtils.getCurrentMaxFrequency();
                mMaxFreqPreference.setValue(currentMaxFreq);
                int maxFreqMhz = Integer.parseInt(currentMaxFreq) / 1000000;
                mMaxFreqPreference.setSummary(maxFreqMhz + " MHz");
            }
        }
    }

    private void loadSwitchStates() {
        if (mForceClkOnPreference != null) {
            mForceClkOnPreference.setChecked(mGpuUtils.getForceClkOn());
        }
        if (mForceBusOnPreference != null) {
            mForceBusOnPreference.setChecked(mGpuUtils.getForceBusOn());
        }
        if (mForceRailOnPreference != null) {
            mForceRailOnPreference.setChecked(mGpuUtils.getForceRailOn());
        }
        if (mForceNoNapPreference != null) {
            mForceNoNapPreference.setChecked(mGpuUtils.getForceNoNap());
        }
        if (mBusSplitPreference != null) {
            mBusSplitPreference.setChecked(mGpuUtils.getBusSplit());
        }
    }

    private void updateDynamicInfo() {
        // Update current frequency
        if (mCurrentFreqPreference != null) {
            String currentFreq = mGpuUtils.getCurrentFrequency();
            if (!currentFreq.equals("0")) {
                int freqMhz = Integer.parseInt(currentFreq) / 1000000;
                mCurrentFreqPreference.setSummary(freqMhz + " MHz");
            } else {
                mCurrentFreqPreference.setSummary("Unknown");
            }
        }
        
        // Update GPU busy percentage
        if (mGpuBusyPreference != null) {
            String busyPercentage = mGpuUtils.getGpuBusyPercentage();
            mGpuBusyPreference.setSummary(busyPercentage);
        }
        
        // Update GPU temperature
        if (mGpuTemperaturePreference != null) {
            String temperature = mGpuUtils.getGpuTemperature();
            if (!temperature.equals("0")) {
                mGpuTemperaturePreference.setSummary(temperature + "°C");
            } else {
                mGpuTemperaturePreference.setSummary("Unknown");
            }
        }
        
        // Update thermal power level
        if (mThermalPowerLevelPreference != null) {
            String thermalLevel = mGpuUtils.getThermalPowerLevel();
            mThermalPowerLevelPreference.setSummary("Level " + thermalLevel);
        }
    }

    private void startPeriodicUpdates() {
        mUpdateRunnable = new Runnable() {
            @Override
            public void run() {
                updateDynamicInfo();
                mHandler.postDelayed(this, 2000); // Update every 2 seconds
            }
        };
        mHandler.post(mUpdateRunnable);
    }

    private void stopPeriodicUpdates() {
        if (mHandler != null && mUpdateRunnable != null) {
            mHandler.removeCallbacks(mUpdateRunnable);
        }
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        String key = preference.getKey();
        
        if (KEY_GPU_GOVERNOR.equals(key)) {
            String value = (String) newValue;
            mGovernorPreference.setSummary(getString(R.string.gpu_governor_summary, value));
            return true;
        } else if (KEY_GPU_MIN_FREQ.equals(key) || KEY_GPU_MAX_FREQ.equals(key)) {
            String value = (String) newValue;
            int freqMhz = Integer.parseInt(value) / 1000000;
            preference.setSummary(freqMhz + " MHz");
            return true;
        }
        
        return true;
    }

    private void applySettings() {
        // Apply governor
        if (mGovernorPreference != null) {
            String governor = mGovernorPreference.getValue();
            mGpuUtils.setGovernor(governor);
        }
        
        // Apply frequencies
        if (mMinFreqPreference != null && mMaxFreqPreference != null) {
            mGpuUtils.setFrequencyRange(mMinFreqPreference.getValue(), mMaxFreqPreference.getValue());
        }
        
        Toast.makeText(getContext(), R.string.settings_applied, Toast.LENGTH_SHORT).show();
    }

    private void resetSettings() {
        mGpuUtils.resetToDefaults();
        loadCurrentSettings();
        Toast.makeText(getContext(), R.string.settings_reset, Toast.LENGTH_SHORT).show();
    }
}
