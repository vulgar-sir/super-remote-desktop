//! super远程桌面 防窥: RustDesk's privacy mode as a cover over the controlled computer's screen. The
//! controller turns it on by default for every session (`superdesk-privacy-auto` = "N" turns that
//! off) and sends what the cover shows and whether the computer locks when the session ends. The
//! controlled side draws the text with the patched WindowInjection.dll, lets a reconnecting session
//! take the cover over from the connection it left behind, ignores the local Ctrl+P exit, and locks
//! the computer before uncovering it.
use base::message_proto::{SdPrivacyCover, TogglePrivacyMode};
use hbb_common::config::Config;
#[cfg(not(target_os = "ios"))]
use hbb_common::{allow_err, log};
#[cfg(not(target_os = "ios"))]
use std::sync::Mutex;

pub const OPTION_AUTO: &str = "superdesk-privacy-auto";
/// "" (black screen + text) | "black" | "display-off" (physical displays off; needs an installed peer)
pub const OPTION_COVER: &str = "superdesk-privacy-cover";
pub const OPTION_TEXT: &str = "superdesk-privacy-text";
/// "" (lock, then uncover) | "restore"
pub const OPTION_AFTER: &str = "superdesk-privacy-after";
pub const DEFAULT_TEXT: &str = "此电脑正在被远程使用，屏幕内容已隐藏";

// ---------------------------------------------------------------------------------- controller

/// Whether a remote-desktop session turns the cover on as soon as it shows the screen.
pub fn auto_on() -> bool {
    Config::get_option(OPTION_AUTO) != "N"
}

/// Implementation asked for by the automatic request: the virtual display one for "display-off"
/// when the peer can plug one in, otherwise the peer's default (the cover window).
pub fn auto_impl_key(peer_supports_virtual_display: bool) -> String {
    if Config::get_option(OPTION_COVER) == "display-off" && peer_supports_virtual_display {
        crate::privacy_mode::PRIVACY_MODE_IMPL_WIN_VIRTUAL_DISPLAY.to_owned()
    } else {
        String::new()
    }
}

fn cover_text(cover: &str, custom: &str) -> String {
    if cover == "black" {
        String::new()
    } else if custom.trim().is_empty() {
        DEFAULT_TEXT.to_owned()
    } else {
        custom.trim().to_owned()
    }
}

/// Adds this side's cover settings to a turn-on request.
pub fn fill_request(t: &mut TogglePrivacyMode, auto: bool) {
    if !t.on {
        return;
    }
    t.sd_cover = Some(SdPrivacyCover {
        text: cover_text(
            &Config::get_option(OPTION_COVER),
            &Config::get_option(OPTION_TEXT),
        ),
        keep_unlocked: Config::get_option(OPTION_AFTER) == "restore",
        auto,
        ..Default::default()
    })
    .into();
}

// ------------------------------------------------------------------------------ controlled side

/// Platform addition telling controllers this side draws the 防窥 cover, so they may turn it on
/// by themselves (older versions lack the cover window and would only report a failure).
pub const PLATFORM_ADDITION: &str = "sd_privacy_cover";

#[cfg(windows)]
pub fn add_platform_additions(m: &mut serde_json::Map<String, serde_json::Value>) {
    let has_cover = crate::privacy_mode::is_privacy_mode_supported()
        && std::env::current_exe()
            .ok()
            .and_then(|exe| Some(exe.parent()?.join("WindowInjection.dll").exists()))
            .unwrap_or(false);
    if has_cover {
        m.insert(PLATFORM_ADDITION.into(), serde_json::Value::Bool(true));
    }
}

#[cfg(not(target_os = "ios"))]
lazy_static::lazy_static! {
    /// The connection that last asked for the cover, with its settings (None: a controller without
    /// 防窥, which keeps RustDesk's behaviour).
    static ref ACTIVE: Mutex<Option<(i32, Option<SdPrivacyCover>)>> = Default::default();
}

/// Called for each privacy-mode request; false drops the request. 员工助手 ignores the automatic
/// one, so the person being helped still sees their screen unless the helper turns the cover on.
#[cfg(not(target_os = "ios"))]
pub fn on_request(conn_id: i32, key: &crate::server::SessionKey, t: &TogglePrivacyMode) -> bool {
    if !t.on {
        return true;
    }
    let cover = t.sd_cover.clone().into_option();
    if cover.as_ref().map_or(false, |c| c.auto) && hbb_common::config::is_incoming_only() {
        log::info!("防窥: automatic request from conn {conn_id} ignored (incoming-only client)");
        return false;
    }
    take_over_from_replaced(conn_id, key);
    *ACTIVE.lock().unwrap() = Some((conn_id, cover));
    true
}

/// A controller whose link dropped reconnects while its old connection still holds the cover until
/// it times out; the new connection could not get the cover, and the screen would be uncovered when
/// the old one closes. The cover moves to the new connection of the same session instead.
#[cfg(not(target_os = "ios"))]
fn take_over_from_replaced(conn_id: i32, key: &crate::server::SessionKey) {
    use crate::privacy_mode::{get_privacy_mode_conn_id, turn_off_privacy, INVALID_PRIVACY_MODE_CONN_ID};
    let Some(owner) = get_privacy_mode_conn_id() else {
        return;
    };
    if owner == INVALID_PRIVACY_MODE_CONN_ID || owner >= conn_id {
        return;
    }
    let replaced = crate::server::AUTHED_CONNS.lock().unwrap().iter().any(|c| {
        c.conn_id == owner
            && c.conn_type == crate::server::AuthConnType::Remote
            && &c.session_key == key
    });
    if replaced {
        log::info!("防窥: conn {conn_id} takes the cover over from replaced conn {owner}");
        if let Some(res) = turn_off_privacy(owner, None) {
            allow_err!(res);
        }
    }
}

/// Text for the cover being shown: the controller's, or the default for a controller without 防窥.
#[cfg(windows)]
fn shown_text() -> String {
    match &*ACTIVE.lock().unwrap() {
        Some((_, Some(cover))) => cover.text.clone(),
        _ => DEFAULT_TEXT.to_owned(),
    }
}

/// Hands the text to the cover windows (drawn by the patched WindowInjection.dll).
#[cfg(windows)]
pub fn apply_cover(hwnds: &[winapi::shared::windef::HWND]) {
    use winapi::um::winuser::{SendMessageTimeoutW, COPYDATASTRUCT, SMTO_ABORTIFHUNG, WM_COPYDATA};
    const SD_COPYDATA_COVER_TEXT: usize = 0x53445043;
    let text: Vec<u16> = shown_text().encode_utf16().collect();
    let cds = COPYDATASTRUCT {
        dwData: SD_COPYDATA_COVER_TEXT,
        cbData: (text.len() * 2) as _,
        lpData: text.as_ptr() as _,
    };
    for &hwnd in hwnds {
        let mut res = 0;
        unsafe {
            SendMessageTimeoutW(
                hwnd,
                WM_COPYDATA,
                0,
                &cds as *const _ as _,
                SMTO_ABORTIFHUNG,
                1000,
                &mut res,
            );
        }
    }
}

/// RustDesk lets the person at the computer press Ctrl+P to leave privacy mode; a 防窥 cover stays.
#[cfg(windows)]
pub fn local_exit_allowed() -> bool {
    !matches!(&*ACTIVE.lock().unwrap(), Some((_, Some(_))))
}

#[cfg(windows)]
const LOCK_SETTLE: std::time::Duration = std::time::Duration::from_millis(1500);

/// Called when the session holding the cover ends, before the cover comes off: locks the computer
/// unless the controller asked to restore the desktop as it is. The cover stays above the lock
/// screen, so nothing shows in between.
#[cfg(not(target_os = "ios"))]
pub async fn before_restore(conn_id: i32) {
    let lock = matches!(
        &*ACTIVE.lock().unwrap(),
        Some((id, Some(cover))) if *id == conn_id && !cover.keep_unlocked
    );
    #[cfg(windows)]
    if lock {
        log::info!("防窥: session {conn_id} ended, locking before uncovering");
        crate::platform::lock_screen();
        hbb_common::tokio::time::sleep(LOCK_SETTLE).await;
    }
    #[cfg(not(windows))]
    let _ = lock;
}

/// A cover left on screen by a server that stopped mid-session (crash, killed): lock, then hide it.
#[cfg(windows)]
pub fn clear_stale_cover() {
    use winapi::um::winuser::{FindWindowExW, IsWindowVisible, PostMessageW, WM_APP};
    const WM_RUSTDESK_HIDE_WINDOWS: u32 = WM_APP + 4;
    std::thread::spawn(|| {
        let class: Vec<u16> = "RustDeskPrivacyWindowClass\0".encode_utf16().collect();
        let mut visible = Vec::new();
        let mut after = std::ptr::null_mut();
        loop {
            let hwnd = unsafe {
                FindWindowExW(std::ptr::null_mut(), after, class.as_ptr(), std::ptr::null())
            };
            if hwnd.is_null() {
                break;
            }
            if unsafe { IsWindowVisible(hwnd) } != 0 {
                visible.push(hwnd as usize);
            }
            after = hwnd;
        }
        if visible.is_empty() {
            return;
        }
        log::info!("防窥: {} cover window(s) left from a previous run, locking and hiding", visible.len());
        crate::platform::lock_screen();
        std::thread::sleep(LOCK_SETTLE);
        for hwnd in visible {
            unsafe { PostMessageW(hwnd as _, WM_RUSTDESK_HIDE_WINDOWS, 0, 0) };
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cover_text_follows_the_settings() {
        assert_eq!(cover_text("", ""), DEFAULT_TEXT);
        assert_eq!(cover_text("", "  IT 正在维护  "), "IT 正在维护");
        assert_eq!(cover_text("black", "ignored"), "");
    }
}
