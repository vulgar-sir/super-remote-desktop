//! super远程桌面: client settings baked in at build time.
//!
//! `SUPERDESK_CONFIG` holds the same JSON shape as RustDesk's custom-client config
//! (`default-settings` / `override-settings`) but unsigned, since it only ever comes from our
//! own build (superdesk/scripts reads it from the git-ignored secrets/superdesk.json).
use base::config::keys;
use hbb_common::{config, log};
use std::collections::HashMap;

pub mod quick_apps;

/// Upload incoming-session recordings to our console (`/api/record`). Switched on per device
/// group by the console through the heartbeat strategy (`superdesk-record-upload` = "Y").
pub fn record_upload_enabled() -> bool {
    config::Config::get_option("superdesk-record-upload") == "Y"
}

pub fn load_builtin_config() {
    let Some(json) = option_env!("SUPERDESK_CONFIG") else {
        return;
    };
    let Ok(mut data) = serde_json::from_str::<HashMap<String, serde_json::Value>>(json) else {
        log::error!("Failed to parse built-in SuperDesk config");
        return;
    };

    let mut map_display_settings = HashMap::new();
    for s in keys::KEYS_DISPLAY_SETTINGS {
        map_display_settings.insert(s.replace("_", "-"), s);
    }
    let mut map_local_settings = HashMap::new();
    for s in keys::KEYS_LOCAL_SETTINGS {
        map_local_settings.insert(s.replace("_", "-"), s);
    }
    let mut map_settings = HashMap::new();
    for s in keys::KEYS_SETTINGS {
        map_settings.insert(s.replace("_", "-"), s);
    }
    let mut map_buildin_settings = HashMap::new();
    for s in keys::KEYS_BUILDIN_SETTINGS {
        map_buildin_settings.insert(s.replace("_", "-"), s);
    }
    for (name, is_override) in [("default-settings", false), ("override-settings", true)] {
        if let Some(settings) = data.remove(name) {
            crate::common::read_custom_client_advanced_settings(
                settings,
                &map_display_settings,
                &map_local_settings,
                &map_settings,
                &map_buildin_settings,
                is_override,
            );
        }
    }
    // Remaining top-level keys are hard settings, e.g. "conn-type": "incoming" for the
    // employee helper build, "disable-settings": "Y".
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    for (k, v) in data {
        if let Some(v) = v.as_str() {
            hard.insert(k, v.to_owned());
        }
    }
}
