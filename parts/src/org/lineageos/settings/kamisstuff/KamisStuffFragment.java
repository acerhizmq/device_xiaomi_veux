/*
 * Copyright (C) 2025 KamiKaonashi
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.lineageos.settings.kamisstuff;

import android.content.Intent;
import android.os.Bundle;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragment;
import org.lineageos.settings.R;
import org.lineageos.settings.corecontrol.CoreControlActivity;
import org.lineageos.settings.zram.ZramActivity;
import org.lineageos.settings.useless.UselessActivity;
import org.lineageos.settings.kernelmanager.KernelManagerActivity;
import org.lineageos.settings.gpumanager.GpuManagerActivity;

public class KamisStuffFragment extends PreferenceFragment {

    private static final String KEY_CORE_CONTROL = "core_control";
    private static final String KEY_ZRAM = "zram";
    private static final String KEY_USELESS = "useless";
    private static final String KEY_KERNEL_MANAGER = "kernel_manager";
    private static final String KEY_GPU_MANAGER = "gpu_manager";

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.kamis_stuff_settings, rootKey);

        // Core Control preference
        Preference coreControlPref = findPreference(KEY_CORE_CONTROL);
        if (coreControlPref != null) {
            coreControlPref.setOnPreferenceClickListener(preference -> {
                Intent intent = new Intent(getActivity(), CoreControlActivity.class);
                startActivity(intent);
                return true;
            });
        }

        // ZRAM preference
        Preference zramPref = findPreference(KEY_ZRAM);
        if (zramPref != null) {
            zramPref.setOnPreferenceClickListener(preference -> {
                Intent intent = new Intent(getActivity(), ZramActivity.class);
                startActivity(intent);
                return true;
            });
        }
        
        // Useless preference
	Preference uselessPref = findPreference(KEY_USELESS);
	if (uselessPref != null) {
    	    uselessPref.setOnPreferenceClickListener(preference -> {
        	Intent intent = new Intent(getActivity(), UselessActivity.class);
		startActivity(intent);
        	return true;
    	    });
	}

        // Kernel Manager preference
        Preference kernelManagerPref = findPreference(KEY_KERNEL_MANAGER);
        if (kernelManagerPref != null) {
            kernelManagerPref.setOnPreferenceClickListener(preference -> {
                Intent intent = new Intent(getActivity(), KernelManagerActivity.class);
                startActivity(intent);
                return true;
            });
        }

        // GPU Manager preference
        Preference gpuManagerPref = findPreference(KEY_GPU_MANAGER);
        if (gpuManagerPref != null) {
            gpuManagerPref.setOnPreferenceClickListener(preference -> {
                Intent intent = new Intent(getActivity(), GpuManagerActivity.class);
                startActivity(intent);
                return true;
            });
        }
    }
}
