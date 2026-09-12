use std::{
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    thread,
    time::{Duration, Instant},
};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use hmac::{Hmac, KeyInit, Mac};
use rand::random;
use sha2::{Digest, Sha256};
use url::Url;
use uuid::Uuid;

use crate::{CliError, credentials::Credential, protocol::Event};

const MAX_HTTP_BODY: usize = 4 * 1024 * 1024;

pub fn pair<F>(
    request_id: Uuid,
    client_name: &str,
    scheme: &str,
    timeout: Duration,
    opener: F,
) -> Result<Vec<Event>, CliError>
where
    F: FnOnce(String) -> Result<(), CliError> + Send + 'static,
{
    let server = CallbackServer::start()?;
    let mut url = Url::parse(&format!("{scheme}://cli/pair"))?;
    url.query_pairs_mut()
        .append_pair("protocolVersion", "1")
        .append_pair("requestID", &request_id.to_string())
        .append_pair("clientName", client_name)
        .append_pair("endpoint", &server.endpoint);
    server.wait(request_id, None, timeout, opener, url.into())
}

pub fn invoke<F>(
    request_id: Uuid,
    request_json: Vec<u8>,
    credential: &Credential,
    scheme: &str,
    timeout: Duration,
    opener: F,
) -> Result<Vec<Event>, CliError>
where
    F: FnOnce(String) -> Result<(), CliError> + Send + 'static,
{
    let server = CallbackServer::start()?;
    let digest = hex::encode(Sha256::digest(&request_json));
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|error| CliError::Protocol(error.to_string()))?
        .as_secs();
    let nonce = hex::encode(random::<[u8; 16]>());
    let secret = STANDARD
        .decode(&credential.secret)
        .map_err(|error| CliError::Credential(error.to_string()))?;
    let signature = request_signature(
        &secret,
        request_id,
        credential.client_id,
        &server.endpoint,
        &digest,
        timestamp,
        &nonce,
    )?;

    let mut url = Url::parse(&format!("{scheme}://cli/run"))?;
    url.query_pairs_mut()
        .append_pair("protocolVersion", "1")
        .append_pair("requestID", &request_id.to_string())
        .append_pair("clientID", &credential.client_id.to_string())
        .append_pair("endpoint", &server.endpoint)
        .append_pair("requestDigest", &digest)
        .append_pair("timestamp", &timestamp.to_string())
        .append_pair("nonce", &nonce)
        .append_pair("signature", &signature);
    server.wait(request_id, Some(request_json), timeout, opener, url.into())
}

fn request_signature(
    secret: &[u8],
    request_id: Uuid,
    client_id: Uuid,
    endpoint: &str,
    digest: &str,
    timestamp: u64,
    nonce: &str,
) -> Result<String, CliError> {
    let canonical =
        format!("1\n{request_id}\n{client_id}\n{endpoint}\n{digest}\n{timestamp}\n{nonce}");
    let mut mac = Hmac::<Sha256>::new_from_slice(secret)
        .map_err(|error| CliError::Protocol(error.to_string()))?;
    mac.update(canonical.as_bytes());
    Ok(hex::encode(mac.finalize().into_bytes()))
}

struct CallbackServer {
    listener: TcpListener,
    endpoint: String,
    path: String,
}

impl CallbackServer {
    fn start() -> Result<Self, CliError> {
        let listener = TcpListener::bind(("127.0.0.1", 0))?;
        listener.set_nonblocking(true)?;
        let port = listener.local_addr()?.port();
        let path = format!("/session/{}", hex::encode(random::<[u8; 16]>()));
        Ok(Self {
            listener,
            endpoint: format!("http://127.0.0.1:{port}{path}"),
            path,
        })
    }

    fn wait<F>(
        self,
        request_id: Uuid,
        request_json: Option<Vec<u8>>,
        timeout: Duration,
        opener: F,
        url: String,
    ) -> Result<Vec<Event>, CliError>
    where
        F: FnOnce(String) -> Result<(), CliError> + Send + 'static,
    {
        let mut open_task = Some(thread::spawn(move || opener(url)));
        let started = Instant::now();
        let mut events = Vec::new();
        let mut served_request = false;
        loop {
            if open_task.as_ref().is_some_and(|task| task.is_finished()) {
                let open_result = open_task
                    .take()
                    .expect("finished app opener is present")
                    .join()
                    .map_err(|_| CliError::AppUnavailable)?;
                open_result?;
            }
            if started.elapsed() >= timeout {
                return Err(CliError::Timeout(timeout.as_secs()));
            }
            match self.listener.accept() {
                Ok((stream, _)) => {
                    if let Some(event) = handle_connection(
                        stream,
                        &self.path,
                        request_json.as_deref(),
                        &mut served_request,
                    )? {
                        if event.request_id != request_id {
                            return Err(CliError::Protocol(
                                "callback request ID does not match this invocation".into(),
                            ));
                        }
                        let expected_sequence = events
                            .last()
                            .map_or(0, |previous: &Event| previous.sequence + 1);
                        if event.sequence != expected_sequence {
                            return Err(CliError::Protocol(format!(
                                "callback sequence {} arrived; expected {expected_sequence}",
                                event.sequence
                            )));
                        }
                        let terminal = event.kind.is_terminal();
                        events.push(event);
                        if terminal {
                            break;
                        }
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(20));
                }
                Err(error) => return Err(error.into()),
            }
        }
        if let Some(open_task) = open_task {
            open_task.join().map_err(|_| CliError::AppUnavailable)??;
        }
        Ok(events)
    }
}

fn handle_connection(
    mut stream: TcpStream,
    expected_path: &str,
    request_json: Option<&[u8]>,
    served_request: &mut bool,
) -> Result<Option<Event>, CliError> {
    stream.set_nonblocking(false)?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    let request = read_http_request(&mut stream)?;
    match (request.method.as_str(), request.path == expected_path) {
        ("GET", true) if request_json.is_some() && !*served_request => {
            *served_request = true;
            write_response(&mut stream, 200, "OK", request_json.unwrap())?;
            Ok(None)
        }
        ("POST", true) => {
            let event = serde_json::from_slice::<Event>(&request.body)?;
            write_response(&mut stream, 204, "No Content", &[])?;
            Ok(Some(event))
        }
        _ => {
            write_response(&mut stream, 410, "Gone", &[])?;
            Ok(None)
        }
    }
}

struct HttpRequest {
    method: String,
    path: String,
    body: Vec<u8>,
}

fn read_http_request(stream: &mut TcpStream) -> Result<HttpRequest, CliError> {
    let mut data = Vec::new();
    let mut buffer = [0_u8; 8192];
    let header_end;
    loop {
        let count = stream.read(&mut buffer)?;
        if count == 0 {
            return Err(CliError::Protocol("incomplete HTTP request".into()));
        }
        data.extend_from_slice(&buffer[..count]);
        if data.len() > 32 * 1024 {
            return Err(CliError::Protocol("HTTP headers are too large".into()));
        }
        if let Some(index) = data.windows(4).position(|window| window == b"\r\n\r\n") {
            header_end = index + 4;
            break;
        }
    }
    let headers = std::str::from_utf8(&data[..header_end])
        .map_err(|error| CliError::Protocol(error.to_string()))?;
    let mut lines = headers.split("\r\n");
    let mut request_line = lines.next().unwrap_or_default().split_whitespace();
    let method = request_line.next().unwrap_or_default().to_string();
    let path = request_line.next().unwrap_or_default().to_string();
    let content_length = lines
        .find_map(|line| {
            line.split_once(':')
                .filter(|(name, _)| name.eq_ignore_ascii_case("content-length"))
        })
        .map(|(_, value)| value.trim().parse::<usize>())
        .transpose()
        .map_err(|error| CliError::Protocol(error.to_string()))?
        .unwrap_or(0);
    if content_length > MAX_HTTP_BODY {
        return Err(CliError::Protocol("HTTP body is too large".into()));
    }
    while data.len() - header_end < content_length {
        let count = stream.read(&mut buffer)?;
        if count == 0 {
            return Err(CliError::Protocol("incomplete HTTP body".into()));
        }
        data.extend_from_slice(&buffer[..count]);
    }
    Ok(HttpRequest {
        method,
        path,
        body: data[header_end..header_end + content_length].to_vec(),
    })
}

fn write_response(
    stream: &mut TcpStream,
    status: u16,
    reason: &str,
    body: &[u8],
) -> Result<(), CliError> {
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\nContent-Length: {}\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n",
        body.len()
    )?;
    stream.write_all(body)?;
    stream.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{EventKind, Request};
    use serde::Deserialize;

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct AuthenticationFixture {
        #[serde(rename = "requestID")]
        request_id: Uuid,
        #[serde(rename = "clientID")]
        client_id: Uuid,
        endpoint: String,
        request_digest: String,
        timestamp: u64,
        nonce: String,
        secret: String,
        signature: String,
    }

    #[test]
    fn authentication_matches_swift_fixture() {
        let fixture: AuthenticationFixture =
            serde_json::from_str(include_str!("../protocol/v1/fixtures/authentication.json"))
                .unwrap();
        let signature = request_signature(
            fixture.secret.as_bytes(),
            fixture.request_id,
            fixture.client_id,
            &fixture.endpoint,
            &fixture.request_digest,
            fixture.timestamp,
            &fixture.nonce,
        )
        .unwrap();
        assert_eq!(signature, fixture.signature);
    }

    #[test]
    fn request_body_and_terminal_result_round_trip() {
        let request_id = Uuid::new_v4();
        let credential = Credential {
            client_id: Uuid::new_v4(),
            secret: STANDARD.encode(b"test secret"),
        };
        let request = Request {
            protocol_version: 1,
            request_id,
            command: crate::protocol::Command::Doctor,
            arguments: Default::default(),
            output: Default::default(),
        };
        let request_json = serde_json::to_vec(&request).unwrap();
        let events = invoke(
            request_id,
            request_json,
            &credential,
            "luxel",
            Duration::from_secs(3),
            move |url| fake_app(&url, request_id),
        )
        .unwrap();
        assert_eq!(events.last().unwrap().kind, EventKind::Result);
    }

    fn fake_app(url: &str, request_id: Uuid) -> Result<(), CliError> {
        let url = Url::parse(url)?;
        let endpoint = url
            .query_pairs()
            .find(|(name, _)| name == "endpoint")
            .unwrap()
            .1;
        let endpoint = Url::parse(&endpoint)?;
        let address = format!(
            "{}:{}",
            endpoint.host_str().unwrap(),
            endpoint.port().unwrap()
        );
        let path = endpoint.path();
        let mut get = TcpStream::connect(&address)?;
        thread::sleep(Duration::from_millis(80));
        write!(get, "GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")?;
        let mut response = Vec::new();
        get.read_to_end(&mut response)?;
        assert!(response.windows(8).any(|window| window == b"\"doctor\""));

        post_event(
            &address,
            path,
            &Event {
                protocol_version: 1,
                request_id,
                sequence: 0,
                kind: EventKind::Accepted,
                job_id: Some(request_id),
                progress: None,
                result: None,
                error: None,
            },
        )?;
        post_event(
            &address,
            path,
            &Event {
                protocol_version: 1,
                request_id,
                sequence: 1,
                kind: EventKind::Result,
                job_id: Some(request_id),
                progress: None,
                result: Some(Default::default()),
                error: None,
            },
        )?;
        Ok(())
    }

    fn post_event(address: &str, path: &str, event: &Event) -> Result<(), CliError> {
        let body = serde_json::to_vec(event)?;
        let mut post = TcpStream::connect(address)?;
        write!(
            post,
            "POST {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {}\r\n\r\n",
            body.len()
        )?;
        post.write_all(&body)?;
        let mut response = Vec::new();
        post.read_to_end(&mut response)?;
        assert!(response.starts_with(b"HTTP/1.1 204"));
        Ok(())
    }
}
