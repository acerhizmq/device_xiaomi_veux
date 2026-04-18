/*
 * Copyright (C) 2025 KamiKaonashi
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 */

package org.lineageos.settings.kernelmanager;

import android.os.Bundle;
import android.widget.Toast;
import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragment;
import org.lineageos.settings.R;

public class KernelManagerFragment extends PreferenceFragment
        implements Preference.OnPreferenceChangeListener {

    private static final String KEY_CPU_GOVERNOR = "cpu_governor";
    private static final String KEY_EFFICIENCY_MIN_FREQ = "efficiency_min_freq";
    private static final String KEY_EFFICIENCY_MAX_FREQ = "efficiency_max_freq";
    private static final String KEY_PERFORMANCE_MIN_FREQ = "performance_min_freq";
    private static final String KEY_PERFORMANCE_MAX_FREQ = "performance_max_freq";
    private static final String KEY_APPLY_SETTINGS = "apply_settings";
    private static final String KEY_RESET_SETTINGS = "reset_settings";
    
    private KernelManagerUtils mKernelUtils;
    private ListPreference mGovernorPreference;
    private ListPreference mEfficiencyMinFreq, mEfficiencyMaxFreq;
    private ListPreference mPerformanceMinFreq, mPerformanceMaxFreq;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.kernel_manager_settings, rootKey);
        mKernelUtils = new KernelManagerUtils();
        
        initializePreferences();
        loadCurrentSettings();
    }

    private void initializePreferences() {
        mGovernorPreference = (ListPreference) findPreference(KEY_CPU_GOVERNOR);
        mEfficiencyMinFreq = (ListPreference) findPreference(KEY_EFFICIENCY_MIN_FREQ);
        mEfficiencyMaxFreq = (ListPreference) findPreference(KEY_EFFICIENCY_MAX_FREQ);
        mPerformanceMinFreq = (ListPreference) findPreference(KEY_PERFORMANCE_MIN_FREQ);
        mPerformanceMaxFreq = (ListPreference) findPreference(KEY_PERFORMANCE_MAX_FREQ);
        
        // Set listeners
        if (mGovernorPreference != null) {
            mGovernorPreference.setOnPreferenceChangeListener(this);
        }
        
        setFrequencyPreferenceListeners();
        
        // Apply and Reset buttons
        Preference applyPref = findPreference(KEY_APPLY_SETTINGS);
        if (applyPref != null) {
            applyPref.setOnPreferenceClickListener(preference -> {
                applySettings();
                return true;
            });
        }
        
        Preference resetPref = findPreference(KEY_RESET_SETTINGS);
        if (resetPref != null) {
            resetPref.setOnPreferenceClickListener(preference -> {
                resetSettings();
                return true;
            });
        }
    }

    private void setFrequencyPreferenceListeners() {
        if (mEfficiencyMinFreq != null) mEfficiencyMinFreq.setOnPreferenceChangeListener(this);
        if (mEfficiencyMaxFreq != null) mEfficiencyMaxFreq.setOnPreferenceChangeListener(this);
        if (mPerformanceMinFreq != null) mPerformanceMinFreq.setOnPreferenceChangeListener(this);
        if (mPerformanceMaxFreq != null) mPerformanceMaxFreq.setOnPreferenceChangeListener(this);
    }

    private void loadCurrentSettings() {
        // Load available governors
        String[] governors = mKernelUtils.getAvailableGovernors();
        if (governors != null && mGovernorPreference != null) {
            mGovernorPreference.setEntries(governors);
            mGovernorPreference.setEntryValues(governors);
            String currentGovernor = mKernelUtils.getCurrentGovernor(KernelManagerUtils.EFFICIENCY_CLUSTER);
            mGovernorPreference.setValue(currentGovernor);
            mGovernorPreference.setSummary(getString(R.string.cpu_governor_summary, currentGovernor));
        }
        
        // Load available frequencies for each cluster
        loadFrequenciesForCluster(KernelManagerUtils.EFFICIENCY_CLUSTER, mEfficiencyMinFreq, mEfficiencyMaxFreq);
        loadFrequenciesForCluster(KernelManagerUtils.PERFORMANCE_CLUSTER, mPerformanceMinFreq, mPerformanceMaxFreq);
    }

    private void loadFrequenciesForCluster(int cluster, ListPreference minPref, ListPreference maxPref) {
        String[] frequencies = mKernelUtils.getAvailableFrequencies(cluster);
        if (frequencies != null) {
            String[] frequencyLabels = new String[frequencies.length];
            for (int i = 0; i < frequencies.length; i++) {
                int freqMhz = Integer.parseInt(frequencies[i]) / 1000;
                frequencyLabels[i] = freqMhz + " MHz";
            }
            
            if (minPref != null) {
                minPref.setEntries(frequencyLabels);
                minPref.setEntryValues(frequencies);
                String currentMinFreq = mKernelUtils.getCurrentMinFrequency(cluster);
                minPref.setValue(currentMinFreq);
                int minFreqMhz = Integer.parseInt(currentMinFreq) / 1000;
                minPref.setSummary(minFreqMhz + " MHz");
            }
            
            if (maxPref != null) {
                maxPref.setEntries(frequencyLabels);
                maxPref.setEntryValues(frequencies);
                String currentMaxFreq = mKernelUtils.getCurrentMaxFrequency(cluster);
                maxPref.setValue(currentMaxFreq);
                int maxFreqMhz = Integer.parseInt(currentMaxFreq) / 1000;
                maxPref.setSummary(maxFreqMhz + " MHz");
            }
        }
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        String key = preference.getKey();
        String value = (String) newValue;
        
        if (KEY_CPU_GOVERNOR.equals(key)) {
            mGovernorPreference.setSummary(getString(R.string.cpu_governor_summary, value));
            return true;
        } else if (key.contains("freq")) {
            int freqMhz = Integer.parseInt(value) / 1000;
            preference.setSummary(freqMhz + " MHz");
            return true;
        }
        
        return false;
    }

    private void applySettings() {
        // Apply governor
        if (mGovernorPreference != null) {
            String governor = mGovernorPreference.getValue();
            mKernelUtils.setGovernor(governor);
        }
        
        // Apply frequencies
        applyFrequencySettings();
        
        Toast.makeText(getContext(), R.string.settings_applied, Toast.LENGTH_SHORT).show();
    }

    private void applyFrequencySettings() {
        if (mEfficiencyMinFreq != null && mEfficiencyMaxFreq != null) {
            mKernelUtils.setEfficiencyClusterFrequency(
                mEfficiencyMinFreq.getValue(), mEfficiencyMaxFreq.getValue());
        }
        if (mPerformanceMinFreq != null && mPerformanceMaxFreq != null) {
            mKernelUtils.setPerformanceClusterFrequency(
                mPerformanceMinFreq.getValue(), mPerformanceMaxFreq.getValue());
        }
    }

    private void resetSettings() {
        mKernelUtils.resetToDefaults();
        loadCurrentSettings();
        Toast.makeText(getContext(), R.string.settings_reset, Toast.LENGTH_SHORT).show();
    }
}
