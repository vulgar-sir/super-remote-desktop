//! super远程桌面 快速启动. The controlled side lists its Start-menu shortcuts (with icons) and opens
//! one of them as the signed-in user when the controller asks; the controller forwards the reply to
//! its session UI. Only ids from the controlled side's own list can be launched.
use base::message_proto::{Message, Misc, SdQuickApp, SdQuickApps};

#[cfg(windows)]
const MAX_APPS: usize = 300;

fn make_msg(q: SdQuickApps) -> Message {
    let mut misc = Misc::new();
    misc.set_sd_quick_apps(q);
    let mut msg = Message::new();
    msg.set_misc(misc);
    msg
}

// ---------------------------------------------------------------------------------- controller

/// Commands the session UI sends through `Session::toggle_option`: "sd-quick-apps" asks for the
/// app list, "sd-launch-app:<id>" opens an app.
pub fn client_command(name: &str) -> Option<Message> {
    if name == "sd-quick-apps" {
        return Some(make_msg(SdQuickApps {
            request: true,
            ..Default::default()
        }));
    }
    let id = name.strip_prefix("sd-launch-app:")?;
    Some(make_msg(SdQuickApps {
        launch: id.to_owned(),
        ..Default::default()
    }))
}

#[cfg(feature = "flutter")]
pub fn on_reply(peer_id: &str, conn_type: hbb_common::rendezvous_proto::ConnType, q: SdQuickApps) {
    let apps: Vec<_> = q
        .apps
        .iter()
        .map(|a| {
            serde_json::json!({
                "id": a.id,
                "name": a.name,
                "icon": crate::common::encode64(&a.icon),
            })
        })
        .collect();
    let data = serde_json::json!({
        "apps": apps,
        "launch": q.launch,
        "error": q.error,
    })
    .to_string();
    if let Some(s) = crate::flutter::sessions::get_session_by_peer_id(peer_id.to_owned(), conn_type)
    {
        s.push_event("sd_quick_apps", &[("data", data.as_str())], &[]);
    }
}

// ---------------------------------------------------------------------------------- controlled

/// Answers a controller's request; `None` when there is nothing to send back.
pub async fn serve(q: SdQuickApps) -> Option<Message> {
    if q.request {
        let apps = hbb_common::tokio::task::spawn_blocking(list_apps)
            .await
            .unwrap_or_default();
        let error = if apps.is_empty() {
            "对方电脑上没有找到可启动的应用".to_owned()
        } else {
            String::new()
        };
        return Some(make_msg(SdQuickApps {
            apps,
            error,
            ..Default::default()
        }));
    }
    if q.launch.is_empty() {
        return None;
    }
    let id = q.launch.clone();
    let res = hbb_common::tokio::task::spawn_blocking(move || launch(&id))
        .await
        .unwrap_or_else(|e| Err(e.to_string()));
    if let Err(e) = &res {
        hbb_common::log::error!("quick app launch failed: {}", e);
    }
    Some(make_msg(SdQuickApps {
        launch: q.launch,
        error: res.err().unwrap_or_default(),
        ..Default::default()
    }))
}

#[cfg(not(windows))]
fn list_apps() -> Vec<SdQuickApp> {
    Vec::new()
}

#[cfg(not(windows))]
fn launch(_id: &str) -> Result<(), String> {
    Err("对方系统暂不支持快速启动".to_owned())
}

#[cfg(windows)]
fn start_menu_dirs() -> Vec<std::path::PathBuf> {
    use std::path::PathBuf;
    let mut dirs = Vec::new();
    if let Ok(pd) = std::env::var("ProgramData") {
        dirs.push(PathBuf::from(pd).join(r"Microsoft\Windows\Start Menu\Programs"));
    }
    let home = if crate::platform::is_root() {
        crate::platform::get_active_user_home()
    } else {
        std::env::var("USERPROFILE").ok().map(PathBuf::from)
    };
    if let Some(home) = home {
        dirs.push(home.join(r"AppData\Roaming\Microsoft\Windows\Start Menu\Programs"));
    }
    dirs
}

/// (shortcut path, display name), de-duplicated by name, sorted.
#[cfg(windows)]
fn shortcuts() -> Vec<(String, String)> {
    fn walk(
        dir: &std::path::Path,
        depth: usize,
        out: &mut Vec<(String, String)>,
        seen: &mut std::collections::HashSet<String>,
    ) {
        if depth > 3 {
            return;
        }
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for e in entries.flatten() {
            let path = e.path();
            if path.is_dir() {
                walk(&path, depth + 1, out, seen);
                continue;
            }
            if !path
                .extension()
                .map_or(false, |x| x.eq_ignore_ascii_case("lnk"))
            {
                continue;
            }
            let Some(name) = path.file_stem().map(|s| s.to_string_lossy().to_string()) else {
                continue;
            };
            let lower = name.to_lowercase();
            const SKIP: [&str; 7] = ["uninstall", "卸载", "readme", "help", "帮助", "website", "documentation"];
            if SKIP.iter().any(|k| lower.contains(k)) {
                continue;
            }
            if seen.insert(lower) {
                out.push((path.to_string_lossy().to_string(), name));
            }
        }
    }
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for dir in start_menu_dirs() {
        walk(&dir, 0, &mut out, &mut seen);
    }
    out.sort_by(|a, b| a.1.to_lowercase().cmp(&b.1.to_lowercase()));
    out.truncate(MAX_APPS);
    out
}

#[cfg(windows)]
fn list_apps() -> Vec<SdQuickApp> {
    use windows::Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_APARTMENTTHREADED};
    let com = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) }.is_ok();
    let apps = shortcuts()
        .into_iter()
        .map(|(id, name)| SdQuickApp {
            icon: icon_png(&id).map(Into::into).unwrap_or_default(),
            id,
            name,
            ..Default::default()
        })
        .collect();
    if com {
        unsafe { CoUninitialize() };
    }
    apps
}

#[cfg(windows)]
fn launch(id: &str) -> Result<(), String> {
    if !shortcuts().iter().any(|(path, _)| path == id) {
        return Err("应用不存在或已被卸载".to_owned());
    }
    let explorer = format!(
        "{}\\explorer.exe",
        std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".to_owned())
    );
    // run_exe_in_session (service) pastes args into a command line; Command (portable) quotes them itself
    let arg = if crate::platform::is_root() {
        format!("\"{}\"", id)
    } else {
        id.to_owned()
    };
    crate::platform::run_exe_in_cur_session(&explorer, vec![arg.as_str()], true)
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// The shortcut's large shell icon as PNG.
#[cfg(windows)]
fn icon_png(path: &str) -> Option<Vec<u8>> {
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::{
        shellapi::{SHGetFileInfoW, SHFILEINFOW, SHGFI_ICON, SHGFI_LARGEICON},
        wingdi::{
            DeleteObject, GetDIBits, GetObjectW, BITMAP, BITMAPINFO, BITMAPINFOHEADER, BI_RGB,
            DIB_RGB_COLORS,
        },
        winuser::{DestroyIcon, GetDC, GetIconInfo, ReleaseDC, ICONINFO},
    };
    let wide: Vec<u16> = std::ffi::OsStr::new(path)
        .encode_wide()
        .chain(Some(0))
        .collect();
    unsafe {
        let mut sfi: SHFILEINFOW = std::mem::zeroed();
        let ok = SHGetFileInfoW(
            wide.as_ptr(),
            0,
            &mut sfi,
            std::mem::size_of::<SHFILEINFOW>() as u32,
            SHGFI_ICON | SHGFI_LARGEICON,
        );
        if ok == 0 || sfi.hIcon.is_null() {
            return None;
        }
        let mut ii: ICONINFO = std::mem::zeroed();
        let got = GetIconInfo(sfi.hIcon, &mut ii) != 0;
        DestroyIcon(sfi.hIcon);
        if !got {
            return None;
        }
        let mut out = None;
        let mut bm: BITMAP = std::mem::zeroed();
        if !ii.hbmColor.is_null()
            && GetObjectW(
                ii.hbmColor as _,
                std::mem::size_of::<BITMAP>() as i32,
                &mut bm as *mut BITMAP as _,
            ) != 0
        {
            let (w, h) = (bm.bmWidth, bm.bmHeight);
            if w > 0 && h > 0 && w <= 256 && h <= 256 {
                let mut bi: BITMAPINFO = std::mem::zeroed();
                bi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
                bi.bmiHeader.biWidth = w;
                bi.bmiHeader.biHeight = -h;
                bi.bmiHeader.biPlanes = 1;
                bi.bmiHeader.biBitCount = 32;
                bi.bmiHeader.biCompression = BI_RGB;
                let mut buf = vec![0u8; (w * h * 4) as usize];
                let dc = GetDC(std::ptr::null_mut());
                let lines = GetDIBits(
                    dc,
                    ii.hbmColor,
                    0,
                    h as u32,
                    buf.as_mut_ptr() as _,
                    &mut bi,
                    DIB_RGB_COLORS,
                );
                ReleaseDC(std::ptr::null_mut(), dc);
                if lines != 0 {
                    let has_alpha = buf.chunks(4).any(|p| p[3] != 0);
                    for p in buf.chunks_mut(4) {
                        p.swap(0, 2);
                        if !has_alpha {
                            p[3] = 255;
                        }
                    }
                    out = encode_png(&buf, w as u32, h as u32);
                }
            }
        }
        if !ii.hbmColor.is_null() {
            DeleteObject(ii.hbmColor as _);
        }
        if !ii.hbmMask.is_null() {
            DeleteObject(ii.hbmMask as _);
        }
        out
    }
}

#[cfg(windows)]
fn encode_png(rgba: &[u8], w: u32, h: u32) -> Option<Vec<u8>> {
    use image::ImageEncoder;
    let mut out = Vec::new();
    image::codecs::png::PngEncoder::new(&mut out)
        .write_image(rgba, w, h, image::ColorType::Rgba8)
        .ok()?;
    Some(out)
}
