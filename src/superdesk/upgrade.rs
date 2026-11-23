//! super远程桌面: opening a newer package on a computer where an older SuperDesk is installed
//! upgrades the installation. RustDesk would instead bring up the installed (old) window, or run the
//! package beside it while the installed service stays old. Each package carries its build number in
//! `superdesk-build.txt`, which installing and upgrading copy into the installation directory.
use hbb_common::{config, log};
use std::path::Path;

const BUILD_FILE: &str = "superdesk-build.txt";

/// Build number next to the program in `dir`; 0 for installations made before the file existed.
fn build_in(dir: &Path) -> u64 {
    std::fs::read_to_string(dir.join(BUILD_FILE))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

/// Called for a plain start (no arguments). True when the elevated upgrade (`--update`, which stops
/// the service, copies this package over the installation and restarts it) was launched, so this run
/// ends here. A declined UAC prompt or an installation that is not older keeps the usual start.
pub fn upgrade_older_installation() -> bool {
    if config::is_disable_installation()
        || !crate::platform::is_installed()
        || crate::platform::is_cur_exe_the_installed()
    {
        return false;
    }
    let Ok(exe) = std::env::current_exe() else {
        return false;
    };
    let mine = exe.parent().map(build_in).unwrap_or(0);
    if mine == 0 {
        return false;
    }
    let (_, install_dir, _, _) = crate::platform::get_install_info();
    let installed = build_in(Path::new(&install_dir));
    if installed >= mine {
        return false;
    }
    log::info!("installed build {installed} is older than this package's {mine}, upgrading");
    match crate::platform::run_uac(&exe.to_string_lossy(), "--update") {
        Ok(true) => true,
        res => {
            log::warn!("upgrade not started ({res:?}), starting as usual");
            false
        }
    }
}
