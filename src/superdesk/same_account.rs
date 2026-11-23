//! super远程桌面 同账号免密: a device signed in to the same console account as this one connects
//! without the device password. The controller gets a single-use ticket from the console, which only
//! issues one when both devices are signed in to the caller's account, and sends it in the login
//! request; the controlled side has the console check it. Turned off on the controlled side with
//! `superdesk-allow-same-account` = "N"; the click-only approve mode keeps asking for a click.
use base::message_proto::{message, Hash, LoginRequest, Message};
use hbb_common::{
    config::{Config, LocalConfig},
    log,
    password_security::{approve_mode, ApproveMode},
    tokio,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

pub const OPTION_ALLOW_SAME_ACCOUNT: &str = "superdesk-allow-same-account";
const TICKET_TTL: Duration = Duration::from_secs(50);
const HTTP_TIMEOUT: Duration = Duration::from_secs(3);

lazy_static::lazy_static! {
    /// Fetched tickets waiting for their login request, by peer id.
    static ref TICKETS: Mutex<HashMap<String, (String, Instant)>> = Default::default();
}

async fn post(path: &str, body: Value, header: &str) -> Option<Value> {
    let api = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if api.is_empty() || crate::is_public(&api) {
        return None;
    }
    let req = crate::post_request(format!("{api}{path}"), body.to_string(), header);
    match tokio::time::timeout(HTTP_TIMEOUT, req).await {
        Ok(Ok(text)) => serde_json::from_str(&text).ok(),
        Ok(Err(e)) => {
            log::warn!("same-account {path}: {e}");
            None
        }
        Err(_) => {
            log::warn!("same-account {path}: timed out");
            None
        }
    }
}

// ---------------------------------------------------------------------------- controlled side

fn accepts_same_account() -> bool {
    Config::get_option(OPTION_ALLOW_SAME_ACCOUNT) != "N" && approve_mode() != ApproveMode::Click
}

/// Marks the login challenge, so controllers know they may skip the password prompt and send a ticket.
pub fn advertise(msg: &mut Message) {
    if let Some(message::Union::Hash(h)) = msg.union.as_mut() {
        h.sd_account_login = accepts_same_account();
    }
}

/// `Some(true)`: the ticket checks out. `Some(false)`: it does not, and no password came with it (the
/// controller skipped its prompt, so it must be asked for one). `None`: no ticket, or a password came
/// with it, so the usual checks apply.
pub async fn verify(lr: &LoginRequest) -> Option<bool> {
    if lr.sd_account_ticket.is_empty() {
        return None;
    }
    let ok = accepts_same_account()
        && post(
            "/api/superdesk/same-account/verify",
            json!({ "ticket": lr.sd_account_ticket, "id": Config::get_id(), "peer": lr.my_id }),
            "",
        )
        .await
        .and_then(|v| v.get("ok").and_then(Value::as_bool))
        .unwrap_or(false);
    log::info!("same-account login from {}: {}", lr.my_id, if ok { "accepted" } else { "rejected" });
    if ok {
        Some(true)
    } else if lr.password.is_empty() {
        Some(false)
    } else {
        None
    }
}

// ---------------------------------------------------------------------------------- controller

/// Called instead of prompting for a password: when the peer accepts same-account logins and this
/// client is signed in, ask the console for a ticket. True when one was issued; the next login request
/// to the peer carries it.
pub async fn fetch_ticket(peer_id: &str, hash: &Hash) -> bool {
    if !hash.sd_account_login {
        return false;
    }
    let token = LocalConfig::get_option("access_token");
    if token.is_empty() {
        return false;
    }
    let Some(v) = post(
        "/api/superdesk/same-account/ticket",
        json!({ "id": Config::get_id(), "target": peer_id }),
        &format!("Authorization: Bearer {token}"),
    )
    .await
    else {
        return false;
    };
    let Some(ticket) = v.get("ticket").and_then(Value::as_str).filter(|t| !t.is_empty()) else {
        return false;
    };
    TICKETS
        .lock()
        .unwrap()
        .insert(peer_id.to_owned(), (ticket.to_owned(), Instant::now()));
    true
}

/// Puts a fetched ticket into the login request (each ticket is sent once).
pub fn attach(peer_id: &str, lr: &mut LoginRequest) {
    let mut tickets = TICKETS.lock().unwrap();
    tickets.retain(|_, (_, at)| at.elapsed() < TICKET_TTL);
    if let Some((ticket, _)) = tickets.remove(peer_id) {
        lr.sd_account_ticket = ticket;
    }
}
